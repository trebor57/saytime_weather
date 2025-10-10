#!/usr/bin/perl

# Rewrite script to perl, rebuild all audio files for asl3
# Copyright 2025, Jory A. Pratt, W5GLE
# Based on original work by D. Crompton, WA3DSP
#
# Recent improvements (Oct 9, 2025):
# - CRITICAL: Replaced discontinued AccuWeather RSS with Open-Meteo API
# - Added ZIP code to coordinates conversion using Census Geocoding API
# - Fixed config file creation logic to properly handle multiple paths
# - Removed dead code (unused fetch_weather function)
# - Removed duplicate file cleanup calls for better efficiency
# - Improved binary file reading with chunked I/O for memory efficiency
# - Improved weather condition sound file matching with better debugging
# - Added better error handling and verbose logging throughout
# - Open-Meteo provides free weather data with no API key required
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
    "/tmp/condition.ulaw",
    "/tmp/timezone"
);

use constant {
    TMP_DIR => "/tmp",
    TEMP_FILE => "/tmp/temperature",
    COND_FILE => "/tmp/condition.ulaw",
    TIMEZONE_FILE => "/tmp/timezone",
    VERSION => '2.7.1',
    WEATHER_SOUND_DIR => "/usr/share/asterisk/sounds/en/wx",
};

# Add options hash near the top
my %options = (
    verbose => 0,  # Default to non-verbose
);

# Source the allstar variables - try each config path
my %config;
my $config_created = 0;
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
    } elsif (!$config_created) {
        # Try to create config file in the first available location
        eval {
            DEBUG("Creating default configuration file: $config_file") if $options{verbose};
            
            # Create parent directory if needed
            my ($vol, $dir, $file) = File::Spec->splitpath($config_file);
            my $parent_dir = File::Spec->catpath($vol, $dir, '');
            if (!-d $parent_dir) {
                require File::Path;
                File::Path::make_path($parent_dir);
            }
            
            open my $fh, '>', $config_file
                or die "Cannot create config file $config_file: $!";
            
            print $fh <<'EOT';
; Weather configuration
[weather]
; Process weather condition announcements (YES/NO)
process_condition = YES

; Temperature display mode (F for Fahrenheit, C for Celsius)
Temperature_mode = F

; Default country for postal code lookups (helps with 5-digit codes)
; Options: us, ca, de, fr, uk, etc. (ISO 3166-1 alpha-2 codes)
; Leave blank for international search
default_country = us

; Weather data source (openmeteo is free, no API key required)
weather_provider = openmeteo

; Cache settings
cache_enabled = YES
cache_duration = 1800
EOT
            close $fh;
            
            chmod 0644, $config_file
                or die "Cannot set permissions on $config_file: $!";
            
            $config_created = 1;
            last;  # Stop after creating config file
        };
        if ($@) {
            WARN("Could not create config file $config_file: $@");
            # Continue to try next path
        }
    }
}

# Set default values for all configuration options
$config{process_condition} = "YES" unless defined $config{process_condition};
$config{Temperature_mode} = "F" unless defined $config{Temperature_mode};
$config{default_country} = "us" unless defined $config{default_country};  # Default to US
$config{weather_provider} = "openmeteo" unless defined $config{weather_provider};  # Default to Open-Meteo
$config{cache_enabled} = "YES" unless defined $config{cache_enabled};
$config{cache_duration} = "1800" unless defined $config{cache_duration};  # 30 minutes default

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
    print "USAGE: $0 <postal code>\n";
    print "\n";
    print "Example: $0 77511     (US ZIP code)\n";
    print "         $0 SW1A1AA   (UK postal code)\n";
    print "         $0 75001     (Paris postal code)\n";
    print "\n";
    print "        Add 'v' as second parameter for display only, no sound files\n";
    print "\n";
    print "Weather Provider: Open-Meteo (free, no API key, worldwide)\n";
    print "Geocoding: Nominatim/OpenStreetMap (free, no API key)\n";
    print "\n";
    print "Edit /etc/asterisk/local/weather.ini to configure:\n";
    print "  - Temperature_mode: C/F (default: F)\n";
    print "  - default_country: us/ca/de/fr/uk (default: us)\n";
    print "  - process_condition: YES/NO (default: YES)\n";
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
        
        # Write timezone file from cache if available
        my $cached_tz = $cached_data->{timezone} // '';
        if ($cached_tz) {
            eval {
                open my $tz_fh, '>', TIMEZONE_FILE or die "Cannot open timezone file: $!";
                print $tz_fh $cached_tz;
                close $tz_fh;
                DEBUG("  Restored timezone from cache: $cached_tz") if $options{verbose};
            };
            WARN("Failed to write timezone file from cache: $@") if $@;
        }
    }
}

# If no cached data, fetch from API
if (not defined $current or $current eq "") {
    my $lat;
    my $lon;
    
    # Convert postal code to coordinates using Nominatim
    ($lat, $lon) = postal_to_coordinates($location);
    
    # If we have coordinates, fetch weather from Open-Meteo
    if (defined $lat && defined $lon) {
        my ($temp, $cond, $tz) = fetch_weather_openmeteo($lat, $lon);
        
        if (defined $temp && defined $cond) {
            $Temperature = sprintf("%.0f", $temp);  # Round to nearest degree
            $Condition = $cond;
            $current = "$Condition: $Temperature";
            $w_type = "openmeteo";
            
            DEBUG("Open-Meteo: $Temperature°, $Condition") if $options{verbose};
            
            # Cache the data if enabled (including timezone)
            if ($config{cache_enabled} eq "YES" && defined $cache) {
                $cache->set($location, {
                    temperature => $Temperature,
                    condition => $Condition,
                    type => $w_type,
                    timezone => $tz || ''
                });
            }
        } else {
            WARN("Failed to fetch weather data from Open-Meteo");
        }
    } else {
        WARN("Could not get coordinates for location: $location");
    }
    
    $w_type = "openmeteo" unless $w_type;
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

# Note: Files already cleaned up earlier in cleanup_old_files()

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
        WARN("Error writing temperature file: $@");
    }
}

# Process weather condition if enabled
if ($config{process_condition} eq "YES" && $Condition) {
    my @conditions = map { lc($_) } split /\s+/, $Condition;
    my @condition_files;
    my $sound_dir = WEATHER_SOUND_DIR;
    
    DEBUG("Processing weather condition: $Condition") if $options{verbose};
    DEBUG("Looking for sound files in: $sound_dir") if $options{verbose};
    
    # First try exact condition match
    for my $cond (@conditions) {
        next unless $cond;  # Skip empty strings
        my $file = "$sound_dir/$cond.ulaw";
        if (-f $file) {
            DEBUG("  Found exact match: $file") if $options{verbose};
            push @condition_files, $file;
        }
    }
    
    # If no exact matches, try to find similar conditions using pattern matching
    if (!@condition_files && -d $sound_dir) {
        opendir(my $dh, $sound_dir) or WARN("Cannot open sound directory: $sound_dir - $!");
        if ($dh) {
            my @available_files = grep { /\.ulaw$/ && -f "$sound_dir/$_" } readdir($dh);
            closedir($dh);
            
            DEBUG("  No exact matches, trying pattern matching") if $options{verbose};
            for my $cond (@conditions) {
                next unless $cond;  # Skip empty strings
                for my $file (@available_files) {
                    if ($file =~ /\Q$cond\E/i) {
                        my $full_path = "$sound_dir/$file";
                        if (!grep { $_ eq $full_path } @condition_files) {  # Avoid duplicates
                            DEBUG("  Found pattern match: $full_path") if $options{verbose};
                            push @condition_files, $full_path;
                        }
                    }
                }
            }
        }
    }
    
    # If still no matches, try to use a default condition
    if (!@condition_files) {
        DEBUG("  No matches found, trying defaults") if $options{verbose};
        my @default_conditions = qw(clear sunny fair);
        for my $default (@default_conditions) {
            my $file = "$sound_dir/$default.ulaw";
            if (-f $file) {
                DEBUG("  Using default condition: $file") if $options{verbose};
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
                    # Read and write in chunks for better memory efficiency
                    my $buffer;
                    while (read($in_fh, $buffer, 8192)) {
                        print $condition_fh $buffer;
                    }
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
        WARN("No weather condition sound files found for: $Condition");
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

# Note: fetch_weather function removed as it was unused dead code
# Weather fetching is done inline in the main code flow

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
    
    foreach my $file (TEMP_FILE(), COND_FILE(), TIMEZONE_FILE()) {
        if (-e $file) {
            DEBUG("  Removing: $file") if $options{verbose};
            unlink $file or WARN("Could not remove file: $file - $!");
        }
    }
}

sub validate_options {
    if (!defined $location || $location eq '') {
        ERROR("Postal code not provided");
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
    # Only show warnings in verbose mode
    print STDERR "WARNING: $msg\n" if $options{verbose};
}

# Convert postal code to coordinates using Nominatim/OpenStreetMap API (free, no key, worldwide)
sub postal_to_coordinates {
    my ($postal) = @_;
    
    DEBUG("Converting postal code $postal to coordinates...") if $options{verbose};
    
    # Special locations without postal codes (Antarctica, remote areas)
    my %special_locations = (
        'SOUTHPOLE' => [-90.0, 0.0, 'South Pole Station, Antarctica'],
        'MCMURDO'   => [-77.85, 166.67, 'McMurdo Station, Antarctica'],
        'PALMER'    => [-64.77, -64.05, 'Palmer Station, Antarctica'],
        'VOSTOK'    => [-78.46, 106.84, 'Vostok Station, Antarctica'],
    );
    
    my $postal_uc = uc($postal);
    $postal_uc =~ s/[^A-Z0-9]//g;  # Remove spaces/special chars
    
    if (exists $special_locations{$postal_uc}) {
        my ($lat, $lon, $name) = @{$special_locations{$postal_uc}};
        DEBUG("  Special location: $name") if $options{verbose};
        DEBUG("  Coordinates: $lat, $lon") if $options{verbose};
        return ($lat, $lon);
    }
    
    my $ua = LWP::UserAgent->new(timeout => 10);
    $ua->agent('Mozilla/5.0 (compatible; WeatherBot/1.0; +https://github.com/w5gle/saytime-weather)');
    
    # Basic Canadian FSA to city mapping (Nominatim has poor Canadian postal code coverage)
    # FSA = Forward Sortation Area (first 3 characters of Canadian postal code)
    my %canadian_fsa_cities = (
        'M' => 'Toronto, Ontario',          # Toronto (all M codes)
        'V' => 'Vancouver, British Columbia', # Vancouver (all V codes)
        'H' => 'Montreal, Quebec',          # Montreal (all H codes)  
        'T' => 'Calgary, Alberta',          # Calgary/Edmonton area
        'R' => 'Winnipeg, Manitoba',        # Winnipeg area
        'K' => 'Ottawa, Ontario',           # Ottawa area
        'N' => 'Ontario',                   # Southwestern/Central Ontario
        'L' => 'Ontario',                   # Southern Ontario (GTA suburbs)
        'P' => 'Ontario',                   # Northern Ontario
        'S' => 'Saskatchewan',              # Saskatchewan
        'E' => 'New Brunswick',             # New Brunswick
        'B' => 'Nova Scotia',               # Nova Scotia
        'C' => 'Prince Edward Island',      # PEI
        'A' => 'Newfoundland',              # Newfoundland
        'G' => 'Quebec',                    # Eastern Quebec
        'J' => 'Quebec',                    # Western Quebec
        'X' => 'Nunavut',                   # Territories
        'Y' => 'Yukon',                     # Yukon
    );
    
    # Use Nominatim (OpenStreetMap) geocoding service - free, no API key, worldwide
    my $url;
    my $country = '';
    my $canadian_fsa = '';
    
    # Detect postal code format and set country
    if ($postal =~ /^\d{5}$/) {
        # 5 digits: Could be US, Germany, France, or other countries
        # Use configured default_country, fallback to US if not set
        $country = lc($config{default_country}) || 'us';
        if ($country && $country ne '') {
            $url = "https://nominatim.openstreetmap.org/search?postalcode=$postal&country=$country&format=json&limit=1";
            DEBUG("  Using default country: $country") if $options{verbose};
        } else {
            $url = "https://nominatim.openstreetmap.org/search?postalcode=$postal&format=json&limit=1";
        }
    } elsif ($postal =~ /^([A-Z])\d[A-Z]\s?\d[A-Z]\d$/i) {
        # Canadian: A1A 1A1 or A1A1A1
        $country = 'ca';
        $canadian_fsa = uc($1);
        # Try with space normalized
        my $normalized = uc($postal);
        $normalized =~ s/\s+//g;  # Remove any spaces
        $normalized =~ s/^([A-Z]\d[A-Z])(\d[A-Z]\d)$/$1 $2/;  # Add space in middle
        $url = "https://nominatim.openstreetmap.org/search?postalcode=$normalized&country=$country&format=json&limit=1";
    } else {
        # Other international codes
        $url = "https://nominatim.openstreetmap.org/search?postalcode=$postal&format=json&limit=1";
    }
    
    DEBUG("  Trying URL: $url") if $options{verbose};
    
    my $response = $ua->get($url);
    if ($response->is_success) {
        my $data = eval { decode_json($response->decoded_content) };
        if ($@ || !$data) {
            DEBUG("Failed to parse Nominatim response: $@") if $options{verbose};
            return;
        }
        
        if ($data && ref($data) eq 'ARRAY' && @$data > 0) {
            my $lat = $data->[0]->{lat};
            my $lon = $data->[0]->{lon};
            my $display = $data->[0]->{display_name} || $postal;
            DEBUG("  Found: $display") if $options{verbose};
            DEBUG("  Coordinates: $lat, $lon") if $options{verbose};
            return ($lat, $lon);
        } else {
            DEBUG("  No coordinates found for postal code $postal") if $options{verbose};
            
            # If country-specific search failed for 5-digit code, try international
            if ($country && $postal =~ /^\d{5}$/) {
                DEBUG("  $country search failed, trying international for $postal") if $options{verbose};
                my $intl_url = "https://nominatim.openstreetmap.org/search?postalcode=$postal&format=json&limit=1";
                sleep 1;  # Rate limit
                $response = $ua->get($intl_url);
                if ($response->is_success) {
                    $data = eval { decode_json($response->decoded_content) };
                    if ($data && ref($data) eq 'ARRAY' && @$data > 0) {
                        my $lat = $data->[0]->{lat};
                        my $lon = $data->[0]->{lon};
                        my $display = $data->[0]->{display_name} || $postal;
                        DEBUG("  Found internationally: $display") if $options{verbose};
                        return ($lat, $lon);
                    }
                }
            }
            
            # For Canadian postal codes, Nominatim often lacks detailed data
            # Use FSA-to-city mapping as fallback
            if ($country eq 'ca' && $canadian_fsa && exists $canadian_fsa_cities{$canadian_fsa}) {
                my $city_name = $canadian_fsa_cities{$canadian_fsa};
                DEBUG("  Trying Canadian city lookup: $city_name (FSA: $canadian_fsa)") if $options{verbose};
                
                my $city_url = "https://nominatim.openstreetmap.org/search?q=$city_name&format=json&limit=1";
                sleep 1;  # Rate limit
                $response = $ua->get($city_url);
                if ($response->is_success) {
                    $data = eval { decode_json($response->decoded_content) };
                    if ($data && ref($data) eq 'ARRAY' && @$data > 0) {
                        my $lat = $data->[0]->{lat};
                        my $lon = $data->[0]->{lon};
                        my $display = $data->[0]->{display_name} || $city_name;
                        DEBUG("  Found via city lookup: $display") if $options{verbose};
                        return ($lat, $lon);
                    }
                }
            }
        }
    } else {
        DEBUG("Nominatim API request failed: " . $response->status_line) if $options{verbose};
    }
    
    # Add a small delay to respect Nominatim usage policy (max 1 request/second)
    sleep 1;
    
    return;
}

# Convert Open-Meteo WMO weather code to text description
sub weather_code_to_text {
    my ($code) = @_;
    
    my %codes = (
        0  => 'Clear',
        1  => 'Mainly Clear',
        2  => 'Partly Cloudy',
        3  => 'Overcast',
        45 => 'Foggy',
        48 => 'Foggy',
        51 => 'Light Drizzle',
        53 => 'Drizzle',
        55 => 'Heavy Drizzle',
        56 => 'Light Freezing Drizzle',
        57 => 'Freezing Drizzle',
        61 => 'Light Rain',
        63 => 'Rain',
        65 => 'Heavy Rain',
        66 => 'Light Freezing Rain',
        67 => 'Freezing Rain',
        71 => 'Light Snow',
        73 => 'Snow',
        75 => 'Heavy Snow',
        77 => 'Snow Grains',
        80 => 'Light Showers',
        81 => 'Showers',
        82 => 'Heavy Showers',
        85 => 'Light Snow Showers',
        86 => 'Snow Showers',
        95 => 'Thunderstorm',
        96 => 'Thunderstorm with Light Hail',
        99 => 'Thunderstorm with Hail',
    );
    
    return $codes{$code} || 'Unknown';
}

# Fetch weather from Open-Meteo API (free, no API key required)
sub fetch_weather_openmeteo {
    my ($lat, $lon) = @_;
    
    DEBUG("Fetching weather from Open-Meteo: lat=$lat, lon=$lon") if $options{verbose};
    
    my $ua = LWP::UserAgent->new(timeout => 15);
    $ua->agent('Mozilla/5.0 (compatible; WeatherBot/1.0)');
    
    my $temp_unit = $config{Temperature_mode} eq "C" ? "celsius" : "fahrenheit";
    my $url = "https://api.open-meteo.com/v1/forecast?" .
              "latitude=$lat&longitude=$lon&current_weather=true&" .
              "temperature_unit=$temp_unit&timezone=auto";
    
    my $response = $ua->get($url);
    if ($response->is_success) {
        my $data = eval { decode_json($response->decoded_content) };
        if ($@ || !$data) {
            DEBUG("Failed to parse Open-Meteo response: $@") if $options{verbose};
            return;
        }
        
        if ($data->{current_weather}) {
            my $temp = $data->{current_weather}->{temperature};
            my $code = $data->{current_weather}->{weathercode};
            my $condition = weather_code_to_text($code);
            my $timezone = $data->{timezone} || '';
            
            DEBUG("  Temperature: $temp") if $options{verbose};
            DEBUG("  Weather code: $code ($condition)") if $options{verbose};
            DEBUG("  Timezone: $timezone") if $options{verbose};
            
            # Save timezone to file so saytime.pl can use it
            if ($timezone) {
                eval {
                    open my $tz_fh, '>', TIMEZONE_FILE or die "Cannot open timezone file: $!";
                    print $tz_fh $timezone;
                    close $tz_fh;
                    DEBUG("  Saved timezone to " . TIMEZONE_FILE) if $options{verbose};
                };
                WARN("Failed to write timezone file: $@") if $@;
            }
            
            return ($temp, $condition, $timezone);
        }
    } else {
        DEBUG("Open-Meteo request failed: " . $response->status_line) if $options{verbose};
    }
    return;
}

# Add temperature validation function
sub validate_temperature {
    my ($temp) = @_;
    my ($tmin, $tmax) = $config{Temperature_mode} eq "C" 
        ? (-60, 60) 
        : (-100, 150);
    
    return ($temp >= $tmin && $temp <= $tmax);
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
