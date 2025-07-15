#!/usr/bin/perl

# Rewrite scrip to perl, rebuild all audio files for asl3
# Copyright 2025, Jory A. Pratt, W5GLE
# Based on original work by D. Crompton, WA3DSP
#

use strict;
use warnings;
use open qw(:std :utf8);
use locale;
$ENV{LC_ALL} = "en_US.UTF-8";
use LWP::UserAgent;
use JSON;
use Encode qw(decode);
use Cache::FileCache;
use File::Spec;
use HTTP::Request;
use HTTP::Response;
use HTTP::Headers;

# Define paths at the top of the script
my @CONFIG_PATHS = (
    "/etc/asterisk/local/weather.ini",
    "/etc/asterisk/weather.ini",
    "/usr/local/etc/weather.ini"
);

my @CACHE_PATHS = (
    "/var/cache/weather",
    "/tmp/weather-cache"
);

my @TEMP_PATHS = (
    "/tmp/temperature",
    "/tmp/condition.ulaw"
);

use constant {
    TMP_DIR => "/tmp",
    TEMP_FILE => "/tmp/temperature",
    COND_FILE => "/tmp/condition.ulaw",
    VERSION => '2.6.6',
    WEATHER_SOUND_DIR => "/usr/share/asterisk/sounds/en/wx",
};

# Add options hash near the top
my %options = (
    verbose => 0,  # Default to non-verbose
);

# Source the allstar variables - try each config path
my %config;
foreach my $config_file (@CONFIG_PATHS) {
    if (-f $config_file) {
        open my $fh, "<", $config_file or next;
        while (my $line = <$fh>) {
            chomp $line;
            $line =~ s/^\s+|\s+$//g; # Trim leading/trailing whitespace
            next if $line eq '' || $line =~ /^;/; # Skip empty lines and comments
            next if $line =~ /^\[.*\]$/; # Skip section headers
            if ($line =~ /^([^=]+?)\s*=\s*"([^"]*)"\s*$/) {
                $config{$1} = $2;
            } elsif ($line =~ /^([^=]+?)\s*=\s*([^\"]\S*)\s*$/) {
                $config{$1} = $2;
            }
        }
        close $fh;
        last;  # Stop after first successful config file
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

; Cache settings
cache_enabled = YES
cache_duration = 1800
EOT
        close $fh;
        
        chmod 0644, $config_file
            or die "Cannot set permissions on $config_file: $!";
    }
}

# Set default values for all configuration options
$config{process_condition} = "YES" unless defined $config{process_condition};
$config{Temperature_mode} = "F" unless defined $config{Temperature_mode};
$config{wunderground_api_key} = "" unless defined $config{wunderground_api_key};
$config{use_accuweather} = "YES" unless defined $config{use_accuweather};
$config{cache_enabled} = "YES" unless defined $config{cache_enabled};
$config{cache_duration} = "1800" unless defined $config{cache_duration};  # 30 minutes default
$config{aerodatabox_rapidapi_key} = "" unless defined $config{aerodatabox_rapidapi_key};

# Initialize cache if enabled
my $cache;
if ($config{cache_enabled} eq "YES") {
    foreach my $cache_path (@CACHE_PATHS) {
        if (-d $cache_path) {
            if (!-w $cache_path) {
                WARN("Cache directory not writable: $cache_path");
                next;
            }
        } elsif (!mkdir $cache_path, 0755) {
            WARN("Failed to create cache directory: $cache_path - $!");
            next;
        }
        $cache = Cache::FileCache->new({
            cache_root => $cache_path,
            default_expires_in => $config{cache_duration},
            auto_purge_interval => 3600,  # 1 hour
            auto_purge_on_set => 1,
        });
        last if defined $cache;
    }
    if (!defined $cache) {
        WARN("Failed to initialize cache - continuing without caching");
        $config{cache_enabled} = "NO";
    } else {
        DEBUG("Cache initialized in: " . $cache->{cache_root}) if $options{verbose};
    }
}

# Ensure location and display_only are defined
my $location = shift @ARGV // '';
my $display_only = shift @ARGV // '';

if (not defined $location || $location eq '') {
    print "\n";
    print "USAGE: $0 <local zip, airport code, or w-<wunderground station code>\n";
    print "\n";
    print "Example: $0 19001, $0 phl, $0 w-WPAGLENB5\n";
    print "        Substitute your local codes\n";
    print "\n";
    print "        Add 'v' as second parameter for just display, no sound\n";
    print "\n";
    print "Edit /etc/asterisk/local/weather.ini to configure:\n";
    print "  - process_condition: YES/NO (default: YES)\n";
    print "  - Temperature_mode: C/F (default: F)\n";
    print "  - wunderground_api_key: Your Weather Underground API key\n";
    print "  - use_accuweather: YES/NO (default: YES)\n";
    print "  - cache_enabled: YES/NO (default: YES)\n";
    print "  - cache_duration: Cache duration in seconds (default: 1800)\n";
    print "\n";
    exit 0;
}

my $destdir = "/tmp";
my $w_type = "";  # Initialize to avoid undefined
my $current = "";  # Initialize to avoid undefined
my $Temperature = "";  # Initialize to avoid undefined
my $Condition = "";  # Initialize to avoid undefined

# Move location validation before cache check
validate_options();  # Add this before cache check

# Move cleanup to start of processing
cleanup_old_files();  # Add this after validating options

# Check cache first if enabled
if ($config{cache_enabled} eq "YES" && defined $cache) {
    my $cached_data = $cache->get($location);
    if ($cached_data) {
        $Temperature = $cached_data->{temperature} // '';
        $Condition = $cached_data->{condition} // '';
        $current = "$Condition: $Temperature";
        $w_type = $cached_data->{type} // '';
    }
}

# If no cached data, fetch from API
if (not defined $current or $current eq "") {
    # AeroDataBox support for airport codes
    if ($location =~ /^[A-Z]{3,4}$/i) {
        my ($lat, $lon, $tz) = get_airport_info_aerodatabox($location);
        if (defined $lat && defined $lon) {
            print "[DEBUG] AeroDataBox: Found lat=$lat, lon=$lon, timezone=$tz\n" if $options{verbose};
            # In the future, you can use $lat/$lon for more accurate weather APIs
        } else {
            print "[WARN] AeroDataBox lookup failed for airport code $location. Falling back to AccuWeather/geocoding.\n";
        }
    }
    if ($location =~ /^w-(.*)/) {
        if (not defined $config{wunderground_api_key} or $config{wunderground_api_key} eq "") {
            print "\nwunderground api key missing\n";
            exit;
        }
        my $wunder_code = uc($1);
        $w_type = "wunder";
        my $ua = LWP::UserAgent->new(connect_timeout => 15);
        my $response = $ua->get("https://api.weather.com/v2/pws/observations/current?stationId=$wunder_code&format=json&units=e&apiKey=$config{wunderground_api_key}");
        if ($response->is_success) {
            my $json = decode_json($response->decoded_content);
            $current = $json->{observations}->[0]->{temp} // '';
            $Temperature = $current;
            $Condition = "";
            
            # Cache the data if enabled
            if ($config{cache_enabled} eq "YES" && defined $cache) {
                $cache->set($location, {
                    temperature => $Temperature,
                    condition => $Condition,
                    type => $w_type
                });
            }
        } else {
            print "Error retrieving wunderground data: " . $response->status_line . "\n";
            exit;
        }
        $config{process_condition} = "NO";
    } else {
        # Try AccuWeather RSS feed first if enabled
        if ($config{use_accuweather} eq "YES") {
            my $ua = LWP::UserAgent->new(connect_timeout => 15);
            my $response = $ua->get("https://rss.accuweather.com/rss/liveweather_rss.asp?metric=0&locCode=$location");
            if ($response->is_success) {
                my $content = $response->decoded_content;
                if ($content =~ /<title>Currently:\s*(.*?):\s*([-\d]+)F<\/title>/) {
                    $Condition = $1;
                    $Temperature = $2;
                    $current = "$Condition: $Temperature";
                } else {
                    $content =~ s/\s+//g;
                    if ($content =~ /<title>Currently:(.*?):([-\d]+)F<\/title>/) {
                        $Condition = $1;
                        $Temperature = $2;
                        $current = "$Condition: $Temperature";
                    } else {
                        my $decoded_content = decode('UTF-8', $content);
                        if ($decoded_content =~ /<title>Currently:\s*(.*?):\s*([-\d]+)F<\/title>/) {
                            $Condition = $1;
                            $Temperature = $2;
                            $current = "$Condition: $Temperature";
                        }
                    }
                }
                
                # Cache the data if enabled
                if ($config{cache_enabled} eq "YES" && defined $cache) {
                    $cache->set($location, {
                        temperature => $Temperature,
                        condition => $Condition,
                        type => "accu"
                    });
                }
            }
        }
        
        $w_type = "accu";
    }
}

if (not defined $current or $current eq "") {
    ERROR("No weather report available");
    exit 1;
}

# Add error handling for temperature conversion
my $CTEMP = eval {
    sprintf "%.0f", (5/9) * ($Temperature - 32);
};
if ($@) {
    ERROR("Failed to convert temperature: $@");
    exit 1;
}
print "$Temperature\N{DEGREE SIGN}F, $CTEMP\N{DEGREE SIGN}C / $Condition\n";

# If v given as second parameter just echo text, no sound
if (defined $display_only and $display_only eq "v") {
    exit;
}

# Clean up old files
unlink TEMP_FILE;
unlink COND_FILE;

# Check if Celsius look for reasonably sane temperature
my $tmin;
my $tmax;
if ($config{Temperature_mode} eq "C") {
    $Temperature = $CTEMP;
    $tmin = -60;
    $tmax = 60;
} else {
    $tmin = -100;
    $tmax = 150;
}

# Write temperature file if within valid range
if ($Temperature >= $tmin and $Temperature <= $tmax) {
    eval {
        open my $temp_fh, '>', TEMP_FILE or die "Cannot open temperature file: $!";
        print $temp_fh $Temperature;
        close $temp_fh;
    };
    if ($@) {
        warn "Error writing temperature file: $@\n";
    }
}

# Process weather condition if enabled
if ($config{process_condition} eq "YES") {
    my @conditions = map { lc($_) } split /\s+/, $Condition;
    my @condition_files;
    my $sound_dir = WEATHER_SOUND_DIR;
    
    # First try exact condition match
    for my $cond (@conditions) {
        my $file = "$sound_dir/$cond.ulaw";
        if (-f $file) {
            push @condition_files, $file;
        }
    }
    
    # If no exact matches, try to find similar conditions
    if (!@condition_files) {
        my $find_cmd = "find $sound_dir -name '*.ulaw' -type f -printf '%f\n'";
        my @available_files = `$find_cmd`;
        chomp @available_files;
        
        for my $cond (@conditions) {
            for my $file (@available_files) {
                if ($file =~ /$cond/ && $file =~ /\.ulaw$/) {
                    push @condition_files, "$sound_dir/$file";
                }
            }
        }
    }
    
    # If still no matches, try to use a default condition
    if (!@condition_files) {
        my @default_conditions = qw(clear sunny fair);
        for my $default (@default_conditions) {
            my $file = "$sound_dir/$default.ulaw";
            if (-f $file) {
                push @condition_files, $file;
                last;
            }
        }
    }
    
    # Write condition sound file if we found any files
    if (@condition_files) {
        eval {
            open my $condition_fh, ">:raw", COND_FILE or die "Cannot open " . COND_FILE . ": $!";
            for my $file (@condition_files) {
                if (-f $file) {
                    open my $in_fh, "<:raw", $file 
                        or die "Cannot open $file: $!";
                    print $condition_fh scalar <$in_fh>;
                    close $in_fh;
                }
            }
            close $condition_fh;
        };
        if ($@) {
            ERROR("Failed to write condition file: $@");
            exit 1;
        }
    } else {
        warn "No weather condition sound files found for: $Condition\n";
    }
}

# Add more descriptive error messages
if (!defined $location) {
    ERROR("Location ID not provided");
    exit 1;
}

if (!-d TMP_DIR()) {
    ERROR("Temporary directory not found: " . TMP_DIR());
    exit 1;
}

if (!-w TMP_DIR()) {
    ERROR("Cannot write to temporary directory: " . TMP_DIR());
    exit 1;
}

# Add version to usage
sub show_usage {
    print "weather.pl version " . VERSION . "\n\n";
    print "Usage: $0 location_id\n\n";
    print "Configuration in /etc/asterisk/local/weather.ini:\n";
    print "  - Temperature_mode: F/C (set to C for Celsius, F for Fahrenheit)\n";
    print "  - process_condition: YES/NO (default: YES)\n";
    print "  - use_accuweather: YES/NO (default: YES)\n";
    print "  - wunderground_api_key: Your Weather Underground API key\n";
    print "  - cache_enabled: YES/NO (default: YES)\n";
    print "  - cache_duration: Cache duration in seconds (default: 1800)\n";
    exit 1;
}

sub fetch_weather {
    my ($location_id) = @_;
    
    DEBUG("Fetching weather for location: $location_id") if $options{verbose};
    
    # Try AccuWeather RSS feed first if enabled
    if ($config{use_accuweather} eq "YES") {
        my $ua = LWP::UserAgent->new(connect_timeout => 15);
        my $response = $ua->get("https://rss.accuweather.com/rss/liveweather_rss.asp?metric=0&locCode=$location_id");
        
        if ($response->is_success) {
            my $content = $response->decoded_content;
            if ($content =~ /<title>Currently:\s*(.*?):\s*([-\d]+)F<\/title>/) {
                return {
                    condition => $1,
                    temperature => $2,
                    type => "accu"
                };
            }
        }
        
        DEBUG("AccuWeather fetch failed") if $options{verbose};
    }
    
    # Try Wunderground if it's a station ID
    if ($location_id =~ /^w-(.*)/ && $config{wunderground_api_key}) {
        my $station = uc($1);
        my $ua = LWP::UserAgent->new(connect_timeout => 15);
        my $url = "https://api.weather.com/v2/pws/observations/current?".
                 "stationId=$station&format=json&units=e&apiKey=$config{wunderground_api_key}";
        
        my $response = $ua->get($url);
        if ($response->is_success) {
            my $json = decode_json($response->decoded_content);
            if ($json->{observations}->[0]->{temp}) {
                return {
                    temperature => $json->{observations}->[0]->{temp},
                    condition => "",
                    type => "wunder"
                };
            }
        }
        
        DEBUG("Wunderground fetch failed") if $options{verbose};
    }
    
    # If all methods fail
    ERROR("Failed to fetch weather data for location: $location_id");
    return;
}

sub write_temperature {
    my ($temp) = @_;
    
    DEBUG("Writing temperature: $temp") if $options{verbose};
    
    open my $fh, '>', TEMP_FILE or die "Cannot write temperature file: $!";
    print $fh $temp;
    close $fh;
    
    DEBUG("Temperature file written: " . TEMP_FILE) if $options{verbose};
}

sub cleanup_old_files {
    DEBUG("Cleaning up old weather files:") if $options{verbose};
    
    foreach my $file (TEMP_FILE(), COND_FILE()) {
        if (-e $file) {
            DEBUG("  Removing: $file") if $options{verbose};
            unlink $file or WARN("Could not remove file: $file - $!");
        }
    }
}

sub validate_options {
    if (!defined $location || $location !~ /^[\w-]+$/) {
        ERROR("Invalid location: $location");
        show_usage();
    }
}

sub ERROR {
    my ($msg) = @_;
    print STDERR "ERROR: $msg\n";
}

sub DEBUG {
    my ($msg) = @_;
    print "$msg\n" if $options{verbose};
}

sub WARN {
    my ($msg) = @_;
    print STDERR "WARNING: $msg\n";
}

# Add temperature validation function
sub validate_temperature {
    my ($temp) = @_;
    my ($tmin, $tmax) = $config{Temperature_mode} eq "C" 
        ? (-60, 60) 
        : (-100, 150);
    
    return ($temp >= $tmin && $temp <= $tmax);
}

# Update error messages to be more descriptive
if ($location =~ /^w-(.*)/ && !defined $config{wunderground_api_key}) {
    ERROR("Wunderground API key missing in configuration file");
    show_usage();
}

# Add signal handlers for cleanup
$SIG{INT} = $SIG{TERM} = sub {
    cleanup_old_files();
    exit 1;
};

# Add configuration validation
sub validate_config {
    if ($config{Temperature_mode} !~ /^[CF]$/) {
        ERROR("Invalid Temperature_mode: $config{Temperature_mode}");
        exit 1;
    }
    if ($config{cache_duration} !~ /^\d+$/) {
        WARN("Invalid cache_duration: $config{cache_duration}, using default");
        $config{cache_duration} = 1800;
    }
}

# Call validation after loading config
validate_config();

# AeroDataBox lookup function (copied from saytime.pl)
sub get_airport_info_aerodatabox {
    my ($code) = @_;
    my $api_key = $config{"aerodatabox_rapidapi_key"};
    unless ($api_key && $code) {
        print "[WARN] AeroDataBox RapidAPI key is missing or code is undefined. Skipping AeroDataBox lookup.\n";
        return;
    }
    my $ua = LWP::UserAgent->new(timeout => 10);
    my $host = 'aerodatabox.p.rapidapi.com';
    my $url;
    $code = uc($code);
    if ($code =~ /^[A-Z]{3}$/) {
        $url = "https://$host/airports/iata/$code";
    } elsif ($code =~ /^[A-Z]{4}$/) {
        $url = "https://$host/airports/icao/$code";
    } else {
        print "[WARN] Code $code is not a valid IATA or ICAO code for AeroDataBox lookup.\n";
        return;
    }
    print "[DEBUG] AeroDataBox: Using API key: $api_key\n" if $options{verbose};
    print "[DEBUG] AeroDataBox: Fetching URL: $url\n" if $options{verbose};
    my $req = HTTP::Request->new(GET => $url);
    $req->header('X-RapidAPI-Key' => $api_key);
    $req->header('X-RapidAPI-Host' => $host);
    my $resp = $ua->request($req);
    if ($resp->is_success) {
        print "[DEBUG] AeroDataBox: Response: " . $resp->decoded_content . "\n" if $options{verbose};
        my $data = eval { decode_json($resp->decoded_content) };
        if ($@) {
            print "[WARN] AeroDataBox: Failed to parse JSON response: $@\n";
            return;
        }
        if ($data && $data->{location} && $data->{location}->{lat} && $data->{location}->{lon} && $data->{timeZone}) {
            print "[DEBUG] AeroDataBox: Parsed lat=$data->{location}->{lat}, lon=$data->{location}->{lon}, timezone=$data->{timeZone}\n" if $options{verbose};
            return ($data->{location}->{lat}, $data->{location}->{lon}, $data->{timeZone});
        } else {
            print "[WARN] AeroDataBox: Incomplete data in response for code $code\n";
        }
    } else {
        print "[WARN] AeroDataBox: API request failed for $code: " . $resp->status_line . "\n";
    }
    return;
}
