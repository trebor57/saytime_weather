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
use Time::Piece;
use File::Spec;
use Getopt::Long;
use Log::Log4perl qw(:easy);
use DateTime;
use DateTime::TimeZone;
use LWP::UserAgent;
use JSON;
use Config::Simple;
use URI::Escape;

# Constants
use constant {
    TMP_DIR => "/tmp",
    BASE_SOUND_DIR => "/usr/share/asterisk/sounds/en",
    WEATHER_SCRIPT => "/usr/local/sbin/weather.pl",
    DEFAULT_VERBOSE => 0,
    DEFAULT_DRY_RUN => 0,
    DEFAULT_TEST_MODE => 0,
    DEFAULT_WEATHER_ENABLED => 1,
    DEFAULT_24HOUR => 0,
    DEFAULT_GREETING => 1,
    ASTERISK_BIN => "/usr/sbin/asterisk",
    DEFAULT_PLAY_METHOD => 'localplay',
    PLAY_DELAY => 5,  # Seconds to wait after playing announcement
    VERSION => '2.6.4',
    TIMEZONE_API_URL => "http://api.timezonedb.com/v2.1/get-time-zone",
    TIMEZONE_API_KEY => "",  # Would need to be configurable in weather.ini
};

# Command line options
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
    play_method => 'localplay',  # Default playback method
);

# Parse command line options
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
    "method|m" => sub { $options{play_method} = 'playback' },  # Set playback if -m is passed
) or show_usage();

# Set default playback method if not set
$options{play_method} //= 'localplay';  # Default to localplay if not set

# Setup logging
setup_logging();

# Load configuration
my %config;
my $config_file = '/etc/asterisk/local/weather.ini';
if (-f $config_file) {
    Config::Simple->import_from($config_file, \%config)
        or die "Cannot load config file $config_file: " . Config::Simple->error();
} else {
    # Create default config file if it doesn't exist
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

; Cache settings
cache_enabled = YES
cache_duration = 1800
EOT
    close $fh;
    
    chmod 0644, $config_file
        or die "Cannot set permissions on $config_file: $!";
}

# Set defaults if not in config
$config{"weather.wunderground_api_key"} ||= "";  # Ensure wunderground_api_key is set
$config{"weather.timezone_api_key"} ||= "";
$config{"weather.geocode_api_key"} ||= "";  # Ensure geocode API key is set
$config{"weather.use_accuweather"} ||= "YES"; # Set default value for use_accuweather

# Validate options
validate_options();

# Get current time in specified timezone
my $now = get_current_time($options{location_id});

# Process time and weather
my $time_sound_files = process_time($now, $options{use_24hour});
my $weather_sound_files = process_weather($options{location_id});

# Combine and play
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

# Subroutines
sub setup_logging {
    my $log_level = $options{verbose} ? $DEBUG : $INFO;
    if ($options{verbose}) {
        $log_level = $DEBUG;
    } else {
        $log_level = $INFO;
    }
    if ($options{log}) {
        Log::Log4perl->easy_init({
            level => $log_level,
            file => ">>$options{log}",
            layout => '%d [%p] %m%n'
        });
    } else {
        Log::Log4perl->easy_init({
            level => $log_level,
            layout => '%d [%p] %m%n'
        });
    }
}

sub validate_options {
    # Validate play method first since it's used in play_announcement
    if ($options{play_method} !~ /^(localplay|playback)$/) {
        die "Invalid play method: $options{play_method} (must be 'localplay' or 'playback')\n";
    }
    
    # Show usage if no node number provided via options or arguments
    show_usage() unless defined $options{node_number} || @ARGV;
    
    # If node number was provided as argument, use it
    $options{node_number} = shift @ARGV if @ARGV && !defined $options{node_number};
    
    # Now validate all options
    die "Node number is required\n" unless defined $options{node_number};
    die "Invalid node number format: $options{node_number}\n" unless $options{node_number} =~ /^\d+$/;
    die "Invalid silent value: $options{silent}\n" if $options{silent} < 0 || $options{silent} > 2;
    
    # Validate location ID if weather is enabled
    if ($options{weather_enabled} && !defined $options{location_id}) {
        die "Location ID is required when weather is enabled\n";
    }
    
    if (defined $options{location_id} && 
        $options{location_id} !~ /^\d{5}$/ &&      # 5-digit code
        $options{location_id} !~ /^[A-Z]{3,4}$/    # 3-4 letter airport code
    ) {
        die "Invalid location ID format: $options{location_id} (must be 5 digits or 3-4 letter airport code)\n";
    }
    
    # Validate sound directory if specified
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
            if ($options{verbose}) {
            WARN("Coordinates for location ID $location_id are not defined.");
            }
            return DateTime->now(time_zone => 'local');
        }
        DEBUG("Found coordinates: $lat, $long") if $options{verbose};
        my $timezone = get_location_timezone($lat, $long);
        if ($timezone ne 'local') {
            DEBUG("Using timezone: $timezone") if $options{verbose};
            # Fix: Create DateTime object with explicit timezone
            my $dt = DateTime->now;
            $dt->set_time_zone($timezone);
            DEBUG("Time in $timezone: " . $dt->hms) if $options{verbose};
            return $dt;
        }
        DEBUG("Timezone lookup failed, using local time") if $options{verbose};
    }
    
    # Fallback to system time
    DEBUG("Using system local time") if $options{verbose};
    return DateTime->now(time_zone => 'local');
}

sub get_location_timezone {
    my ($lat, $long) = @_;
    return 'local' unless defined $lat && defined $long;
    
    DEBUG("Getting timezone for coordinates: $lat, $long") if $options{verbose};
    
    my $api_key = $config{"weather.timezone_api_key"};
    if (!$api_key) {
        DEBUG("No timezone API key configured") if $options{verbose};
        Log::Log4perl::get_logger()->warn("No timezone API key configured");
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
            return $data->{zoneName};  # Returns like "America/New_York"
        }
        DEBUG("Invalid timezone response status: $data->{status}") if $options{verbose};
    } else {
        DEBUG("Timezone request failed: " . $response->status_line) if $options{verbose};
    }
    if ($options{verbose}) {
        WARN("Failed to get timezone, using system local time");
    }
    return 'local';
}

sub get_location_coordinates {
    my ($location_id) = @_;
    return (undef, undef) unless defined $location_id;
    
    DEBUG("Getting coordinates for location: $location_id") if $options{verbose};
    
    # Try AccuWeather first
    if ($config{"weather.use_accuweather"} eq "YES") {
        my $ua = LWP::UserAgent->new(timeout => 10);
        my $url = "https://rss.accuweather.com/rss/liveweather_rss.asp?locCode=$location_id";
        DEBUG("Fetching AccuWeather URL: $url") if $options{verbose};
        
        my $response = $ua->get($url);
        if ($response->is_success) {
            my $content = $response->decoded_content;
            DEBUG("Got AccuWeather response:\n$content") if $options{verbose};
            
            # Extract location name from title
            if ($content =~ m{<title>([^,]+),\s*([A-Z]{2}) - AccuWeather\.com Forecast</title>}i) {
                my $city = $1;
                my $state = $2;
                DEBUG("Found location: $city, $state") if $options{verbose};
                
                # Clean up the location name for geocoding
                my $location_name = "$city, $state";
                DEBUG("Using cleaned location name for geocoding: $location_name") if $options{verbose};
                
                # Use a geocoding API to get coordinates
                return get_coordinates_from_geocoding_api($location_name);
            } else {
                DEBUG("Could not find location name in AccuWeather response") if $options{verbose};
            }
        } else {
            DEBUG("AccuWeather request failed: " . $response->status_line) if $options{verbose};
            Log::Log4perl::get_logger()->warn("AccuWeather request failed: " . $response->status_line);
        }
    }
    
    DEBUG("Failed to get coordinates for location: $location_id") if $options{verbose};
    Log::Log4perl::get_logger()->warn("Failed to get coordinates for location: $location_id");
    return (undef, undef);
}

sub get_coordinates_from_geocoding_api {
    my ($location_name) = @_;
    
    my $api_key = $config{"weather.geocode_api_key"};
    unless ($api_key) {
        if ($options{verbose}) {
            WARN("Geocoding API key is not set in the configuration.");
        }
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
    
    my $weather_cmd = sprintf("%s %s", WEATHER_SCRIPT, $location_id);
    my $weather_result = system($weather_cmd);
    
    if ($weather_result != 0) {
        my $exit_code = $? >> 8;
        ERROR("Weather script failed:");
        ERROR("  Location: $location_id");
        ERROR("  Command: $weather_cmd");
        ERROR("  Exit code: $exit_code");
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
        if ($options{verbose}) {
            WARN("Temperature file not found: $temp_file");
        }
    }
    
    return $files;
}

sub format_number {
    my ($num, $sound_dir) = @_;
    return "$sound_dir/digits/$num.ulaw " if $num < 20;
    my $tens = int($num / 10) * 10;
    my $ones = $num % 10;
    return "$sound_dir/digits/$tens.ulaw " . ($ones ? "$sound_dir/digits/$ones.ulaw " : "");
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
    my $cat_result = system("cat $input_files > $output_file");
    if ($cat_result != 0) {
        ERROR("cat command failed with exit code: $cat_result");
    }
}

# Subroutine to play the announcement
sub play_announcement {
    my ($node, $asterisk_file) = @_;
    
    # Remove .ulaw extension for Asterisk command
    $asterisk_file =~ s/\.ulaw$//;

    # Check if in test mode and log the command instead of executing
    if ($options{test_mode}) {
        INFO("Test mode - would execute: rpt $options{play_method} $node $asterisk_file");
        return;
    }
    
    # Construct the Asterisk command to play the announcement
    my $asterisk_cmd = sprintf(
        "%s -rx \"rpt %s %s %s\"",
        ASTERISK_BIN,
        $options{play_method},
        $node,
        $asterisk_file
    );

    DEBUG("Executing: $asterisk_cmd") if $options{verbose};

    # Execute the command and check for success
    my $asterisk_result = system($asterisk_cmd);
    if ($asterisk_result != 0) {
        my $exit_code = $? >> 8;
        ERROR("Failed to play announcement:");
        ERROR("  Method: $options{play_method}");
        ERROR("  Command: $asterisk_cmd");
        ERROR("  Exit code: $exit_code");
    }
    sleep PLAY_DELAY;  # Wait for a specified delay after playing
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
    die "Usage: $0 [options] [location_id] node_number\n" .
    "Options:\n" .
    "  -l, --location_id=ID    Location ID for weather (default: none)\n" .
    "  -n, --node_number=NUM   Node number for announcement (required)\n" .
    "  -s, --silent=NUM        Silent mode (default: 0)\n" .
    "                          0=voice, 1=save time+weather, 2=save weather only\n" .
    "  -h, --use_24hour        Use 24-hour clock (default: off)\n" .    
    "  -v, --verbose           Enable verbose output (default: off)\n" .
    "  -d, --dry-run           Don't actually play or save files (default: off)\n" .
    "  -t, --test              Test sound files before playing (default: off)\n" .
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
    "  perl saytime.pl -l 77511 -n 546054 -m\n" .  # Enables playback to all connected nodes
    "  perl saytime.pl -l 77511 -n 546054 -s 1\n" .  # Saves time and weather to a file
    "  perl saytime.pl -l 77511 -n 546054 -h\n" .  # Uses 24-hour format
    "Configuration in /etc/asterisk/local/weather.ini:\n";
    print "  - timezone_api_key: Your TimeZoneDB API key (get from https://timezonedb.com)\n";
    print "  - geocode_api_key: Your Geocoding API key (get from https://opencagedata.com)\n";
    print "  - Temperature_mode: F/C (set to C for Celsius, F for Fahrenheit)\n";
}