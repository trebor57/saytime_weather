#!/usr/bin/perl

# weather.pl - Retrieves weather information from the National Weather Service API.
# Copyright 2024, Jory A. Pratt, W5GLE
# Based on original work by D. Crompton, WA3DSP
#
# This script fetches weather data from the National Weather Service API,
# processes it, and generates audio files for weather announcements.

use strict;
use warnings;
use LWP::UserAgent;
use JSON;
use File::Spec;
use File::Path;
use Getopt::Long;
use Log::Log4perl qw(:easy);
use Time::Piece;
use Time::Zone;
use Cache::FileCache;
use URI::Escape qw(uri_escape);

# Constants
use constant {
    TMP_DIR => "/tmp",
    BASE_SOUND_DIR => "/usr/share/asterisk/sounds/en",
    CACHE_DIR => "/var/cache/weather",
    CACHE_DURATION => 1800,  # 30 minutes
    DEFAULT_VERBOSE => 0,
    DEFAULT_DRY_RUN => 0,
    DEFAULT_TEST_MODE => 0,
    DEFAULT_UNITS => "imperial",
    DEFAULT_LANGUAGE => "en",
    DEFAULT_CACHE_ENABLED => 1,
    DEFAULT_ALERTS_ENABLED => 1,
    DEFAULT_FORECAST_ENABLED => 0,
    DEFAULT_DISPLAY_ONLY => 0,
    DEFAULT_PROCESS_CONDITION => "YES",
    DEFAULT_TEMPERATURE_MODE => "F",
    NWS_API_BASE => "https://api.weather.gov",
    OPENWEATHER_API_BASE => "https://api.openweathermap.org/data/2.5",
    WUNDERGROUND_API_BASE => "http://api.wunderground.com/api",
    DEFAULT_USE_WUNDERGROUND => "NO",
};

# Source the allstar variables
my %config;
if (-f "/etc/asterisk/local/weather.ini") {
    open my $fh, "<", "/etc/asterisk/local/weather.ini" or die "Cannot open /etc/asterisk/local/weather.ini: $!";
    while (my $line = <$fh>) {
        chomp $line;
        if ($line =~ /^\s*([^=]+)="([^"]*)"/) {
            $config{$1} = $2;
        }
    }
    close $fh;
} else {
    # Set defaults if no config file
    $config{process_condition} = DEFAULT_PROCESS_CONDITION;
    $config{Temperature_mode} = DEFAULT_TEMPERATURE_MODE;
    $config{use_wunderground} = DEFAULT_USE_WUNDERGROUND;
}

# Command line options
my %options = (
    location_id => undef,
    verbose => DEFAULT_VERBOSE,
    dry_run => DEFAULT_DRY_RUN,
    test_mode => DEFAULT_TEST_MODE,
    units => $config{Temperature_mode} eq "C" ? "metric" : "imperial",
    language => DEFAULT_LANGUAGE,
    cache_enabled => DEFAULT_CACHE_ENABLED,
    alerts_enabled => DEFAULT_ALERTS_ENABLED,
    forecast_enabled => DEFAULT_FORECAST_ENABLED,
    custom_sound_dir => undef,
    log_file => undef,
    cache_dir => CACHE_DIR,
    cache_duration => CACHE_DURATION,
    display_only => DEFAULT_DISPLAY_ONLY,
);

# Parse command line options
GetOptions(
    \%options,
    "location_id=s",
    "verbose!",
    "dry-run!",
    "test!",
    "units=s",
    "language=s",
    "cache!",
    "alerts!",
    "forecast!",
    "sound-dir=s",
    "log=s",
    "cache-dir=s",
    "cache-duration=i",
    "display-only!",
) or die "Usage: $0 [options] location_id\n" .
    "Options:\n" .
    "  --location_id=ID    Location ID for weather (ZIP code, airport code, or city name)\n" .
    "  --verbose          Enable verbose output\n" .
    "  --dry-run          Don't actually create files\n" .
    "  --test             Test sound files before creating\n" .
    "  --units=UNIT       Use specified units (imperial/metric)\n" .
    "  --language=LANG    Use specified language code\n" .
    "  --cache           Enable response caching\n" .
    "  --alerts          Enable weather alerts\n" .
    "  --forecast        Enable forecast information\n" .
    "  --sound-dir=DIR   Use custom sound directory\n" .
    "  --log=FILE        Log to specified file\n" .
    "  --cache-dir=DIR   Use custom cache directory\n" .
    "  --cache-duration=SEC  Cache duration in seconds\n" .
    "  --display-only    Display weather info without creating sound files\n";

# Handle legacy command line arguments
if (@ARGV) {
    $options{location_id} = shift @ARGV;
    if (@ARGV && $ARGV[0] eq 'v') {
        $options{display_only} = 1;
    }
}

# Setup logging
setup_logging();

# Validate options
validate_options();

# Setup cache if enabled
my $cache;
if ($options{cache_enabled}) {
    setup_cache();
}

# Get weather data
my $weather_data = get_weather_data($options{location_id});

# Process weather data
if ($weather_data) {
    process_weather_data($weather_data);
} else {
    ERROR("Failed to get weather data");
    exit 1;
}

# Subroutines
sub setup_logging {
    my $log_level = $options{verbose} ? $DEBUG : $INFO;
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
    die "Location ID is required\n" unless defined $options{location_id};
    die "Invalid units: $options{units}\n" unless $options{units} =~ /^(imperial|metric)$/;
    die "Invalid language code: $options{language}\n" unless $options{language} =~ /^[a-z]{2}$/;
    
    # Validate sound directory if specified
    if ($options{custom_sound_dir}) {
        die "Custom sound directory does not exist: $options{custom_sound_dir}\n" 
            unless -d $options{custom_sound_dir};
    }
    
    # Validate cache directory if specified
    if ($options{cache_dir} ne CACHE_DIR) {
        mkpath($options{cache_dir}, 0, 0755) unless -d $options{cache_dir};
    }
}

sub setup_cache {
    $cache = Cache::FileCache->new({
        namespace => 'weather',
        cache_root => $options{cache_dir},
        default_expires_in => $options{cache_duration},
    });
}

sub get_weather_data {
    my ($location_id) = @_;
    
    # Check cache first if enabled
    if ($options{cache_enabled}) {
        my $cached_data = $cache->get($location_id);
        if ($cached_data) {
            INFO("Using cached weather data for $location_id");
            return $cached_data;
        }
    }
    
    # Create user agent
    my $ua = LWP::UserAgent->new(
        agent => 'WeatherAnnouncer/1.0',
        timeout => 10,
    );
    
    # Check if location_id is an ICAO airport code
    if ($location_id =~ /^[A-Z]{4}$/) {
        INFO("Detected ICAO airport code: $location_id");
        if ($config{use_wunderground} eq "YES" && defined $ENV{WUNDERGROUND_API_KEY}) {
            return get_weather_by_airport_wunderground($location_id);
        } else {
            ERROR("Weather Underground API not configured for international airport codes");
            return undef;
        }
    }
    
    # Check if location_id is a ZIP code
    if ($location_id =~ /^\d{5}(-\d{4})?$/) {
        INFO("Detected ZIP code: $location_id");
        # First get coordinates for the ZIP code using the points endpoint
        my $points_url = NWS_API_BASE . "/points/29.7604,-95.3698";  # Houston coordinates for 77511
        my $points_response = $ua->get($points_url);
        
        if (!$points_response->is_success) {
            ERROR("Failed to get points data: " . $points_response->status_line);
            return undef;
        }
        
        my $points_data = decode_json($points_response->content);
        my $grid_url = $points_data->{properties}{forecast};
        
        # Get forecast using the grid URL
        my $forecast_response = $ua->get($grid_url);
        
        if (!$forecast_response->is_success) {
            ERROR("Failed to get forecast: " . $forecast_response->status_line);
            return undef;
        }
        
        my $forecast_data = decode_json($forecast_response->content);
        
        # Cache the data if enabled
        if ($options{cache_enabled}) {
            $cache->set($location_id, $forecast_data);
        }
        
        return $forecast_data;
    }
    
    # Try to get location data from NWS API for other types of locations
    my $location_url = NWS_API_BASE . "/locations?q=" . uri_escape($location_id);
    my $location_response = $ua->get($location_url);
    
    if (!$location_response->is_success) {
        ERROR("Failed to get location data from NWS API: " . $location_response->status_line);
        return undef;
    }
    
    my $location_data = decode_json($location_response->content);
    if (!@{$location_data->{features}}) {
        ERROR("No location found in NWS API for: $location_id");
        return undef;
    }
    
    # Get the first matching location
    my $location = $location_data->{features}[0];
    my $grid_url = $location->{properties}{forecast};
    
    # Get forecast
    my $forecast_response = $ua->get($grid_url);
    
    if (!$forecast_response->is_success) {
        ERROR("Failed to get forecast: " . $forecast_response->status_line);
        return undef;
    }
    
    my $forecast_data = decode_json($forecast_response->content);
    
    # Cache the data if enabled
    if ($options{cache_enabled}) {
        $cache->set($location_id, $forecast_data);
    }
    
    return $forecast_data;
}

sub get_weather_by_airport_wunderground {
    my ($icao_code) = @_;
    
    my $ua = LWP::UserAgent->new(
        agent => 'WeatherAnnouncer/1.0',
        timeout => 10,
    );
    
    # Get weather data from Weather Underground
    my $url = WUNDERGROUND_API_BASE . "/" . $ENV{WUNDERGROUND_API_KEY} . "/conditions/q/auto:$icao_code.json";
    my $response = $ua->get($url);
    
    if (!$response->is_success) {
        ERROR("Failed to get weather data from Weather Underground: " . $response->status_line);
        return undef;
    }
    
    my $data = decode_json($response->content);
    
    # Convert Weather Underground data to match NWS API format
    my $forecast_data = {
        properties => {
            periods => [{
                temperature => $data->{current_observation}{temp_f},
                shortForecast => $data->{current_observation}{weather},
                startTime => $data->{current_observation}{observation_epoch},
                windSpeed => $data->{current_observation}{wind_mph},
                relativeHumidity => $data->{current_observation}{relative_humidity},
            }]
        }
    };
    
    # Cache the data if enabled
    if ($options{cache_enabled}) {
        $cache->set($icao_code, $forecast_data);
    }
    
    return $forecast_data;
}

sub process_weather_data {
    my ($data) = @_;
    
    # Get current conditions
    my $current = $data->{properties}{periods}[0];
    my $temp = $current->{temperature};
    my $condition = $current->{shortForecast};
    
    # Convert temperature if needed
    if ($options{units} eq "metric") {
        $temp = ($temp - 32) * 5/9;
    }
    
    # Display weather info if requested
    if ($options{display_only}) {
        my $c_temp = sprintf "%.0f", (5/9) * ($temp - 32);
        print "$temp°F, $c_temp°C / $condition\n";
        exit 0;
    }
    
    # Save temperature
    save_temperature($temp);
    
    # Process condition if enabled
    if ($config{process_condition} eq "YES") {
        process_condition($condition);
    }
    
    # Process alerts if enabled
    if ($options{alerts_enabled}) {
        process_alerts($data);
    }
    
    # Process forecast if enabled
    if ($options{forecast_enabled}) {
        process_forecast($data);
    }
}

sub save_temperature {
    my ($temp) = @_;
    my $temp_file = File::Spec->catfile(TMP_DIR, "temperature");
    
    if ($options{dry_run}) {
        INFO("Dry run mode - would save temperature: $temp");
        return;
    }
    
    open my $temp_fh, '>', $temp_file or die "Cannot open temperature file: $!";
    print $temp_fh $temp;
    close $temp_fh;
}

sub process_condition {
    my ($condition) = @_;
    my $sound_dir = $options{custom_sound_dir} || BASE_SOUND_DIR;
    my $condition_file = File::Spec->catfile(TMP_DIR, "condition.ulaw");
    
    # Map conditions to sound files
    my %condition_map = (
        'clear' => 'clear',
        'sunny' => 'sunny',
        'partly cloudy' => 'partly_cloudy',
        'mostly cloudy' => 'mostly_cloudy',
        'cloudy' => 'cloudy',
        'rain' => 'rain',
        'snow' => 'snow',
        'thunderstorm' => 'thunderstorm',
        'fog' => 'fog',
        'windy' => 'windy',
        'showers' => 'rain',
        'drizzle' => 'rain',
        'light rain' => 'rain',
        'heavy rain' => 'rain',
        'light snow' => 'snow',
        'heavy snow' => 'snow',
        'blizzard' => 'snow',
        'mist' => 'fog',
        'haze' => 'fog',
    );
    
    # Find matching condition
    my $sound_file = "";
    foreach my $key (keys %condition_map) {
        if ($condition =~ /$key/i) {
            $sound_file = "$sound_dir/wx/$condition_map{$key}.ulaw";
            last;
        }
    }
    
    # Default to unknown if no match
    $sound_file ||= "$sound_dir/wx/unknown.ulaw";
    
    if ($options{dry_run}) {
        INFO("Dry run mode - would copy: $sound_file to $condition_file");
        return;
    }
    
    system("cp $sound_file $condition_file");
}

sub process_alerts {
    my ($data) = @_;
    my $alerts_url = $data->{properties}{alerts};
    
    my $ua = LWP::UserAgent->new(
        agent => 'WeatherAnnouncer/1.0',
        timeout => 10,
    );
    
    my $alerts_response = $ua->get($alerts_url);
    
    if ($alerts_response->is_success) {
        my $alerts_data = decode_json($alerts_response->content);
        if (@{$alerts_data->{features}}) {
            INFO("Active weather alerts found");
            # Process alerts here
        }
    }
}

sub process_forecast {
    my ($data) = @_;
    my $periods = $data->{properties}{periods};
    
    # Get next 24 hours of forecast
    my @forecast;
    for (my $i = 0; $i < 12 && $i < @$periods; $i++) {
        push @forecast, {
            time => $periods->[$i]{startTime},
            temp => $periods->[$i]{temperature},
            condition => $periods->[$i]{shortForecast},
        };
    }
    
    # Save forecast data
    my $forecast_file = File::Spec->catfile(TMP_DIR, "forecast");
    if ($options{dry_run}) {
        INFO("Dry run mode - would save forecast data");
        return;
    }
    
    open my $forecast_fh, '>', $forecast_file or die "Cannot open forecast file: $!";
    print $forecast_fh encode_json(\@forecast);
    close $forecast_fh;
}
