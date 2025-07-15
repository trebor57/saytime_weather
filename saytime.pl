#!/usr/bin/perl

# saytime.pl - Announces the time and weather information.
# Copyright 2025, Jory A. Pratt, W5GLE
# Based on original work by D. Crompton, WA3DSP
#
# This script retrieves the current time and optionally the weather,
# then generates a concatenated audio file of the time and weather announcement.
# It can either play the audio, or save the sound file.

use strict;
use warnings;
use File::Spec;
use Getopt::Long;
use Log::Log4perl qw(:easy);
use DateTime;
use DateTime::TimeZone;
use LWP::UserAgent;
use JSON;
use Config::Simple;
use URI::Escape;
use HTTP::Request;
use HTTP::Response;
use HTTP::Headers;

use constant {
    TMP_DIR => "/tmp",
    BASE_SOUND_DIR => "/usr/share/asterisk/sounds/en",
    WEATHER_SCRIPT => "/usr/sbin/weather.pl",
    DEFAULT_VERBOSE => 0,
    DEFAULT_DRY_RUN => 0,
    DEFAULT_TEST_MODE => 0,
    DEFAULT_WEATHER_ENABLED => 1,
    DEFAULT_24HOUR => 0,
    DEFAULT_GREETING => 1,
    ASTERISK_BIN => "/usr/sbin/asterisk",
    DEFAULT_PLAY_METHOD => 'localplay',
    PLAY_DELAY => 5,
    VERSION => '2.6.4',
    TIMEZONE_API_URL => "http://api.timezonedb.com/v2.1/get-time-zone",
};

my %options = (
    location_id => undef,
    node_number => undef,
    silent => 0,
    use_24hour => DEFAULT_24HOUR,
    verbose => DEFAULT_VERBOSE,
    dry_run => DEFAULT_DRY_RUN,
    test_mode => DEFAULT_TEST_MODE,
    weather_enabled => DEFAULT_WEATHER_ENABLED,
    greeting_enabled => DEFAULT_GREETING,
    custom_sound_dir => undef,
    log_file => undef,
    play_method => 'localplay',
);

GetOptions(
    "location_id|l=s" => \$options{location_id},
    "node_number|n=s" => \$options{node_number},
    "silent|s=i" => \$options{silent},
    "use_24hour|h!" => \$options{use_24hour},
    "verbose|v!" => \$options{verbose},
    "dry-run|d!" => \$options{dry_run},
    "test|t!" => \$options{test_mode},
    "weather|w!" => \$options{weather_enabled},
    "greeting|g!" => \$options{greeting_enabled},
    "sound-dir=s" => \$options{custom_sound_dir},
    "log=s" => \$options{log_file},
    "method|m" => sub { $options{play_method} = 'playback' },
) or show_usage();

$options{play_method} //= 'localplay';

setup_logging();

my %config;
my $config_file = '/etc/asterisk/local/weather.ini';
if (-f $config_file) {
    Config::Simple->import_from($config_file, \%config)
        or die "Cannot load config file $config_file: " . Config::Simple->error();
} else {
    DEBUG("Creating default configuration file: $config_file") if $options{verbose};
    open my $fh, '>', $config_file
        or die "Cannot create config file $config_file: $!";
    print $fh <<'EOT';
; Weather configuration
[weather]
; Process weather condition announcements (YES/NO)
process_condition = YES

; Temperature display mode (F for Fahrenheit, C for Celsius)
Temperature_mode = F

; Weather data sources
use_accuweather = YES

; Weather Underground API key (if using Wunderground stations)
wunderground_api_key = 

; TimeZoneDB API key for timezone lookup (get free key from https://timezonedb.com)
timezone_api_key = 

; Geocoding API key for location coordinates (get free key from https://opencagedata.com)
geocode_api_key = 

; AeroDataBox RapidAPI key for airport lookups (get from https://rapidapi.com/aerodatabox/api/aerodatabox)
aerodatabox_rapidapi_key = 

; Cache settings
cache_enabled = YES
cache_duration = 1800
EOT
    close $fh;
    chmod 0644, $config_file
        or die "Cannot set permissions on $config_file: $!";
}

$config{"weather.wunderground_api_key"} ||= "";
$config{"weather.timezone_api_key"} ||= "";
$config{"weather.geocode_api_key"} ||= "";
$config{"weather.aerodatabox_rapidapi_key"} ||= "";
$config{"weather.use_accuweather"} ||= "YES";

validate_options();

my $critical_error_occurred = 0;

my $now = get_current_time($options{location_id});

my $time_sound_files = process_time($now, $options{use_24hour});
my $weather_sound_files = process_weather($options{location_id});

my $output_file = File::Spec->catfile(TMP_DIR, "current-time.ulaw");
my $final_sound_files = combine_sound_files($time_sound_files, $weather_sound_files);

if ($options{dry_run}) {
    INFO("Dry run mode - would play: $final_sound_files");
    exit 0;
}

if ($final_sound_files) {
    create_output_file($final_sound_files, $output_file);
}

if ($options{silent} == 0) {
    play_announcement($options{node_number}, $output_file);
    cleanup_files($output_file, $options{weather_enabled}, $options{silent});
} elsif ($options{silent} == 1 || $options{silent} == 2) {
    INFO("Saved sound file to $output_file");
    cleanup_files(undef, $options{weather_enabled}, $options{silent});
}

exit $critical_error_occurred;

sub setup_logging {
    my $log_level = $options{verbose} ? $DEBUG : $INFO;
    my %log_params = (
        level  => $log_level,
        layout => '%d [%p] %m%n'
    );
    $log_params{file} = ">>$options{log_file}" if $options{log_file};
    Log::Log4perl->easy_init(\%log_params);
}

sub validate_options {
    if ($options{play_method} !~ /^(localplay|playback)$/) {
        die "Invalid play method: $options{play_method} (must be 'localplay' or 'playback')\n";
    }
    
    show_usage() unless defined $options{node_number} || @ARGV;
    
    $options{node_number} = shift @ARGV if @ARGV && !defined $options{node_number};
    
    die "Node number is required\n" unless defined $options{node_number};
    die "Invalid node number format: $options{node_number}\n" unless $options{node_number} =~ /^\d+$/;
    die "Invalid silent value: $options{silent}\n" if $options{silent} < 0 || $options{silent} > 2;
    
    if ($options{weather_enabled} && !defined $options{location_id}) {
        die "Location ID is required when weather is enabled\n";
    }
    
    if (defined $options{location_id} && 
        $options{location_id} !~ /^\d{5}$/ &&
        $options{location_id} !~ /^[A-Z]{3,4}$/
    ) {
        die "Invalid location ID format: $options{location_id} (must be 5 digits or 3-4 letter airport code)\n";
    }
    
    if ($options{custom_sound_dir}) {
        die "Custom sound directory does not exist: $options{custom_sound_dir}\n" 
            unless -d $options{custom_sound_dir};
    }
}

sub get_current_time {
    my ($location_id) = @_;
    
    if (defined $location_id) {
        DEBUG("Getting timezone for location: $location_id") if $options{verbose};
        my ($lat, $long) = get_location_coordinates($location_id);
        unless (defined $lat && defined $long) {
            Log::Log4perl::get_logger()->warn("Coordinates for location ID $location_id are not defined. Falling back to local time.");
            return DateTime->now(time_zone => 'local');
        }
        DEBUG("Found coordinates: $lat, $long") if $options{verbose};
        my $timezone = get_location_timezone($lat, $long);
        if ($timezone ne 'local') {
            DEBUG("Using timezone: $timezone") if $options{verbose};
            my $dt = DateTime->now;
            $dt->set_time_zone($timezone);
            DEBUG("Time in $timezone: " . $dt->hms) if $options{verbose};
            return $dt;
        }
        Log::Log4perl::get_logger()->warn("Timezone lookup failed for $lat, $long. Falling back to local time.");
    }
    
    DEBUG("Using system local time") if $options{verbose};
    return DateTime->now(time_zone => 'local');
}

sub get_location_timezone {
    my ($lat, $long) = @_;
    if (exists $options{_airport_timezone} && $options{_airport_timezone}) {
        my $tz = $options{_airport_timezone};
        delete $options{_airport_timezone};
        return $tz;
    }
    return 'local' unless defined $lat && defined $long;
    
    DEBUG("Getting timezone for coordinates: $lat, $long") if $options{verbose};
    
    my $api_key = $config{"weather.timezone_api_key"};
    if (!$api_key) {
        Log::Log4perl::get_logger()->warn("No timezone API key configured. Falling back to local time.");
        return 'local';
    }
    
    my $ua = LWP::UserAgent->new(timeout => 10);
    my $url = sprintf(
        "%s?key=%s&format=json&by=position&lat=%s&lng=%s",
        TIMEZONE_API_URL,
        $api_key,
        $lat,
        $long
    );
    
    DEBUG("Fetching timezone URL: $url") if $options{verbose};
    
    my $response = $ua->get($url);
    if ($response->is_success) {
        my $data = decode_json($response->content);
        DEBUG("Got timezone response: " . $response->content) if $options{verbose};
        if ($data->{status} eq 'OK') {
            DEBUG("Found timezone: $data->{zoneName}") if $options{verbose};
            return $data->{zoneName};
        }
        DEBUG("Invalid timezone response status: $data->{status}") if $options{verbose};
    } else {
        DEBUG("Timezone request failed: " . $response->status_line) if $options{verbose};
    }
    Log::Log4perl::get_logger()->warn("Failed to get timezone from API, using system local time");
    return 'local';
}

sub get_location_coordinates {
    my ($location_id) = @_;
    return (undef, undef) unless defined $location_id;
    
    DEBUG("Getting coordinates for location: $location_id") if $options{verbose};
    
    # Use AeroDataBox for airport codes
    if ($location_id =~ /^[A-Z]{3,4}$/) {
        my ($lat, $lon, $tz) = get_airport_info_aerodatabox($location_id);
        if (defined $lat && defined $lon) {
            $options{_airport_timezone} = $tz if $tz;
            return ($lat, $lon);
        } else {
            Log::Log4perl::get_logger()->warn("AeroDataBox lookup failed for airport code $location_id. Falling back to AccuWeather/geocoding.");
        }
    }

    if ($config{"weather.use_accuweather"} eq "YES") {
        my $ua = LWP::UserAgent->new(timeout => 10);
        my $url = "https://rss.accuweather.com/rss/liveweather_rss.asp?locCode=$location_id";
        DEBUG("Fetching AccuWeather URL: $url") if $options{verbose};
        
        my $response = $ua->get($url);
        if ($response->is_success) {
            my $content = $response->decoded_content;
            DEBUG("Got AccuWeather response:\n$content") if $options{verbose};
            
            if ($content =~ m{<title>([^,]+),\s*([A-Z]{2}) - AccuWeather\.com Forecast</title>}i) {
                my $city = $1;
                my $state = $2;
                DEBUG("Found location: $city, $state") if $options{verbose};
                
                my $location_name = "$city, $state";
                DEBUG("Using cleaned location name for geocoding: $location_name") if $options{verbose};
                
                return get_coordinates_from_geocoding_api($location_name);
            } else {
                DEBUG("Could not find location name in AccuWeather response") if $options{verbose};
            }
        } else {
            DEBUG("AccuWeather request failed: " . $response->status_line) if $options{verbose};
            Log::Log4perl::get_logger()->warn("AccuWeather request failed: " . $response->status_line);
        }
    }
    
    Log::Log4perl::get_logger()->warn("Failed to get coordinates for location: $location_id");
    return (undef, undef);
}

sub get_airport_info_aerodatabox {
    my ($code) = @_;
    my $api_key = $config{"weather.aerodatabox_rapidapi_key"};
    unless ($api_key && $code) {
        Log::Log4perl::get_logger()->warn("AeroDataBox RapidAPI key is missing or code is undefined. Skipping AeroDataBox lookup.");
        return;
    }
    my $ua = LWP::UserAgent->new(timeout => 10);
    my $host = 'aerodatabox.p.rapidapi.com';
    my $url;
    if ($code =~ /^[A-Z]{3}$/) {
        $url = "https://$host/airports/iata/$code";
    } elsif ($code =~ /^[A-Z]{4}$/) {
        $url = "https://$host/airports/icao/$code";
    } else {
        Log::Log4perl::get_logger()->warn("Code $code is not a valid IATA or ICAO code for AeroDataBox lookup.");
        return;
    }
    DEBUG("AeroDataBox: Using API key: $api_key");
    DEBUG("AeroDataBox: Fetching URL: $url");
    my $req = HTTP::Request->new(GET => $url);
    $req->header('X-RapidAPI-Key' => $api_key);
    $req->header('X-RapidAPI-Host' => $host);
    my $resp = $ua->request($req);
    if ($resp->is_success) {
        DEBUG("AeroDataBox: Response: " . $resp->decoded_content);
        my $data = eval { decode_json($resp->decoded_content) };
        if ($@) {
            Log::Log4perl::get_logger()->warn("AeroDataBox: Failed to parse JSON response: $@");
            return;
        }
        if ($data && $data->{location} && $data->{location}->{lat} && $data->{location}->{lon} && $data->{timeZone}) {
            DEBUG("AeroDataBox: Parsed lat=$data->{location}->{lat}, lon=$data->{location}->{lon}, timezone=$data->{timeZone}");
            return ($data->{location}->{lat}, $data->{location}->{lon}, $data->{timeZone});
        } else {
            Log::Log4perl::get_logger()->warn("AeroDataBox: Incomplete data in response for code $code");
        }
    } else {
        Log::Log4perl::get_logger()->warn("AeroDataBox: API request failed for $code: " . $resp->status_line);
    }
    return;
}

sub get_coordinates_from_geocoding_api {
    my ($location_name) = @_;
    
    my $api_key = $config{"weather.geocode_api_key"};
    unless ($api_key) {
        Log::Log4perl::get_logger()->warn("Geocoding API key is not set in the configuration.");
        return (undef, undef);
    }
    
    my $ua = LWP::UserAgent->new(timeout => 10);
    my $geocode_url = "https://api.opencagedata.com/geocode/v1/json?q=" . uri_escape($location_name) . "&key=" . $api_key;
    
    DEBUG("Fetching geocoding URL: $geocode_url") if $options{verbose};
    
    my $response = $ua->get($geocode_url);
    if ($response->is_success) {
        my $data = decode_json($response->content);
        if ($data->{results} && @{$data->{results}}) {
            my $lat = $data->{results}->[0]->{geometry}->{lat};
            my $long = $data->{results}->[0]->{geometry}->{lng};
            DEBUG("Found coordinates from geocoding API: $lat, $long") if $options{verbose};
            return ($lat, $long);
        } else {
            DEBUG("No results found in geocoding response") if $options{verbose};
        }
    } else {
        DEBUG("Geocoding request failed: " . $response->status_line) if $options{verbose};
    }
    Log::Log4perl::get_logger()->warn("Failed to get coordinates from geocoding API for $location_name");
    return (undef, undef);
}

sub process_time {
    my ($now, $use_24hour) = @_;
    my @files;
    my $sound_dir = $options{custom_sound_dir} || BASE_SOUND_DIR;
    
    if ($options{greeting_enabled}) {
        my $hour = $now->hour;
        my $greeting = $hour < 12 ? "morning" : $hour < 18 ? "afternoon" : "evening";
        push @files, "$sound_dir/rpt/good$greeting.ulaw ";
    }
    
    push @files, "$sound_dir/rpt/thetimeis.ulaw ";
    
    my ($hour, $minute) = ($now->hour, $now->minute);
    
    if ($use_24hour) {
        if ($hour < 10) {
            push @files, "$sound_dir/digits/0.ulaw ";
        }
        push @files, format_number($hour, $sound_dir);
        
        if ($minute == 0) {
            push @files, "$sound_dir/digits/hundred.ulaw ";
            push @files, "$sound_dir/hours.ulaw ";
        } else {
            if ($minute < 10) {
                push @files, "$sound_dir/digits/0.ulaw ";
            }
            push @files, format_number($minute, $sound_dir);
            push @files, "$sound_dir/hours.ulaw ";
        }
    } else {
        my $display_hour = ($hour == 0 || $hour == 12) ? 12 : ($hour > 12 ? $hour - 12 : $hour);
        push @files, "$sound_dir/digits/$display_hour.ulaw ";
        
        if ($minute != 0) {
            if ($minute < 10) {
                push @files, "$sound_dir/digits/0.ulaw ";
            }
            push @files, format_number($minute, $sound_dir);
        }
        push @files, "$sound_dir/digits/" . ($hour < 12 ? "a-m" : "p-m") . ".ulaw ";
    }
    
    return join("", @files);
}

sub process_weather {
    my ($location_id) = @_;
    return "" unless $options{weather_enabled} && defined $location_id;
    
    DEBUG("Fetching weather for location: $location_id") if $options{verbose};

    my $temp_file_to_clean = File::Spec->catfile(TMP_DIR, "temperature");
    my $weather_condition_file_to_clean = File::Spec->catfile(TMP_DIR, "condition.ulaw");
    unlink $temp_file_to_clean if -e $temp_file_to_clean;
    unlink $weather_condition_file_to_clean if -e $weather_condition_file_to_clean;
    
    my $weather_cmd = sprintf("%s %s", WEATHER_SCRIPT, $location_id);
    my $weather_result_raw = system($weather_cmd);
    
    if ($weather_result_raw != 0) {
        my $exit_code = $? >> 8;
        ERROR("Weather script failed:");
        ERROR("  Location: $location_id");
        ERROR("  Command: $weather_cmd");
        ERROR("  Exit code: $exit_code");
        $critical_error_occurred = 1;
        return "";
    }
    
    my $temp_file = File::Spec->catfile(TMP_DIR, "temperature");
    my $weather_condition_file = File::Spec->catfile(TMP_DIR, "condition.ulaw");
    my $sound_dir = $options{custom_sound_dir} || BASE_SOUND_DIR;
    
    my $files = "";
    if (-f $temp_file) {
        open my $temp_fh, '<', $temp_file or die "Cannot open temperature file: $!";
        chomp(my $temp = <$temp_fh>);
        close $temp_fh;
        
        $files = "$sound_dir/silence/1.ulaw " .
                 "$sound_dir/wx/weather.ulaw " .
                 "$sound_dir/wx/conditions.ulaw $weather_condition_file " .
                 "$sound_dir/wx/temperature.ulaw ";
                 
        if ($temp < 0) {
            $files .= "$sound_dir/digits/minus.ulaw ";
            $temp = abs($temp);
        }
        
        $files .= format_number($temp, $sound_dir);
        $files .= "$sound_dir/wx/degrees.ulaw ";
    } else {
        Log::Log4perl::get_logger()->warn("Temperature file not found after running weather script: $temp_file");
    }
    
    return $files;
}

sub format_number {
    my ($num, $sound_dir) = @_;
    my $files = "";
    my $abs_num = abs($num);

    if ($abs_num == 0 && $files eq "") {
        return "$sound_dir/digits/0.ulaw ";
    }
    if ($abs_num == 0 && $files ne "") {
        return $files;
    }

    if ($abs_num >= 100) {
        my $hundreds = int($abs_num / 100);
        $files .= "$sound_dir/digits/$hundreds.ulaw ";
        $files .= "$sound_dir/digits/hundred.ulaw ";
        $abs_num %= 100;
        if ($abs_num == 0) { return $files; }
    }
    
    if ($abs_num == 0 && $files eq "") { # Should not happen if logic above is correct, but as safeguard
        return "$sound_dir/digits/0.ulaw "; # Or maybe return "" if files is already populated
    }
    if ($abs_num == 0 && $files ne "") {
         return $files; # Number like 100, 200, 1000 etc.
    }


    if ($abs_num < 20) {
        $files .= "$sound_dir/digits/$abs_num.ulaw ";
    } else {
        my $tens = int($abs_num / 10) * 10;
        my $ones = $abs_num % 10;
        $files .= "$sound_dir/digits/$tens.ulaw ";
        if ($ones) {
            $files .= "$sound_dir/digits/$ones.ulaw ";
        }
    }
    return $files;
}

sub combine_sound_files {
    my ($time_files, $weather_files) = @_;
    my $files = "";
    
    if ($options{silent} == 0 || $options{silent} == 1) {
        $files = "$time_files $weather_files";
    } elsif ($options{silent} == 2) {
        $files = $weather_files;
    }
    
    return $files;
}

sub create_output_file {
    my ($input_files, $output_file) = @_;
    my $cat_result_raw = system("cat $input_files > $output_file");
    if ($cat_result_raw != 0) {
        my $exit_code = $? >> 8;
        my $signal_num = $? & 127;
        my $dumped_core = $? & 128;
        ERROR("cat command failed. Exit code: $exit_code, Signal: $signal_num, Core dump: $dumped_core. Files: $input_files");
        $critical_error_occurred = 1;
    }
}

sub play_announcement {
    my ($node, $asterisk_file) = @_;
    
    $asterisk_file =~ s/\.ulaw$//;

    if ($options{test_mode}) {
        INFO("Test mode - would execute: rpt $options{play_method} $node $asterisk_file");
        return;
    }
    
    my $asterisk_cmd = sprintf(
        "%s -rx \"rpt %s %s %s\"",
        ASTERISK_BIN,
        $options{play_method},
        $node,
        $asterisk_file
    );

    DEBUG("Executing: $asterisk_cmd") if $options{verbose};

    my $asterisk_result_raw = system($asterisk_cmd);
    if ($asterisk_result_raw != 0) {
        my $exit_code = $? >> 8;
        ERROR("Failed to play announcement:");
        ERROR("  Method: $options{play_method}");
        ERROR("  Command: $asterisk_cmd");
        ERROR("  Exit code: $exit_code");
        $critical_error_occurred = 1;
    }
    sleep PLAY_DELAY;
}

sub cleanup_files {
    my ($file_to_delete, $weather_enabled, $silent) = @_;
    
    DEBUG("Cleaning up temporary files:") if $options{verbose};
    
    if (defined $file_to_delete && $silent == 0) {
        DEBUG("  Removing announcement file: $file_to_delete") if $options{verbose};
        unlink $file_to_delete if -e $file_to_delete;
    }
    
    if ($weather_enabled && ($silent == 1 || $silent == 2 || $silent == 0)) {
        my $temp_file = File::Spec->catfile(TMP_DIR, "temperature");
        my $cond_file = File::Spec->catfile(TMP_DIR, "condition.ulaw");
        
        DEBUG("  Removing weather files:") if $options{verbose};
        DEBUG("    - $temp_file") if $options{verbose};
        DEBUG("    - $cond_file") if $options{verbose};
        
        unlink $temp_file if -e $temp_file;
        unlink $cond_file if -e $cond_file;
    }
}

sub show_usage {
    print "saytime.pl version " . VERSION . "\n\n";
    die "Usage: $0 [options] node_number\n" .
    "Options:\n" .
    "  -l, --location_id=ID    Location ID for weather (default: none)\n" .
    "  -n, --node_number=NUM   Node number for announcement (if not provided as argument)\n" .
    "  -s, --silent=NUM        Silent mode (default: 0)\n" .
    "                          0=voice, 1=save time+weather, 2=save weather only\n" .
    "  -h, --use_24hour        Use 24-hour clock (default: off)\n" .    
    "  -v, --verbose           Enable verbose output (default: off)\n" .
    "  -d, --dry-run           Don't actually play or save files (default: off)\n" .
    "  -t, --test              Log playback command instead of executing (default: off)\n" .
    "  -w, --weather           Enable weather announcements (default: on)\n" .
    "  -g, --greeting          Enable greeting messages (default: on)\n" .
    "  -m                      Enable playback mode (default: localplay)\n" .
    "      --sound-dir=DIR     Use custom sound directory\n" .
    "                          (default: /usr/share/asterisk/sounds/en)\n" .
    "      --log=FILE          Log to specified file (default: none)\n" .
    "      --help              Show this help message and exit\n\n" .
    "Location ID can be either:\n" .
    "  - 5-digit location code (e.g., 77511)\n" .
    "  - 3-4 letter airport code (e.g., KHOU)\n" .
    "Examples:\n" .
    "  perl saytime.pl -l 77511 -n 546054 -m\n" .
    "  perl saytime.pl -l 77511 546054 -m\n" .
    "  perl saytime.pl -l 77511 546054 -s 1\n" .
    "  perl saytime.pl -l 77511 546054 -h\n" .
    "Configuration in /etc/asterisk/local/weather.ini:\n" .
    "  - timezone_api_key: Your TimeZoneDB API key (get from https://timezonedb.com)\n" .
    "  - geocode_api_key: Your Geocoding API key (get from https://opencagedata.com)\n" .
    "  - aerodatabox_rapidapi_key: Your AeroDataBox RapidAPI key (get from https://rapidapi.com/aerodatabox/api/aerodatabox)\n" .
    "  - Temperature_mode: F/C (set to C for Celsius, F for Fahrenheit)\n";
}