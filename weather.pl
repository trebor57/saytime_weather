#!/usr/bin/perl

# Rewrite scrip to perl, rebuild all audio files for asl3
# Copyright 2024, Jory A. Pratt, W5GLE
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
}

# Set default values for all configuration options
$config{process_condition} = "YES" unless defined $config{process_condition};
$config{Temperature_mode} = "F" unless defined $config{Temperature_mode};
$config{api_Key} = "" unless defined $config{api_Key};
$config{use_accuweather} = "YES" unless defined $config{use_accuweather};
$config{use_hvwx} = "YES" unless defined $config{use_hvwx};
$config{cache_enabled} = "YES" unless defined $config{cache_enabled};
$config{cache_duration} = "1800" unless defined $config{cache_duration};  # 30 minutes default

# Initialize cache if enabled
my $cache;
if ($config{cache_enabled} eq "YES") {
    $cache = Cache::FileCache->new({
        cache_root => '/var/cache/weather',
        default_expires_in => $config{cache_duration},
        auto_purge_interval => 3600,  # 1 hour
        auto_purge_on_set => 1,
    });
}

my $location = shift @ARGV;
my $display_only = shift @ARGV;

if (not defined $location) {
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
    print "  - api_Key: Your Weather Underground API key\n";
    print "  - use_accuweather: YES/NO (default: YES)\n";
    print "  - use_hvwx: YES/NO (default: YES)\n";
    print "  - cache_enabled: YES/NO (default: YES)\n";
    print "  - cache_duration: Cache duration in seconds (default: 1800)\n";
    print "\n";
    exit 0;
}

my $destdir = "/tmp";
my $w_type;
my $current;
my $Temperature = "";
my $Condition = "";

# Check cache first if enabled
if ($config{cache_enabled} eq "YES" && defined $cache) {
    my $cached_data = $cache->get($location);
    if ($cached_data) {
        $Temperature = $cached_data->{temperature};
        $Condition = $cached_data->{condition};
        $current = "$Condition: $Temperature";
        $w_type = $cached_data->{type};
    }
}

# If no cached data, fetch from API
if (not defined $current or $current eq "") {
    if ($location =~ /^w-(.*)/) {
        if (not defined $config{api_Key} or $config{api_Key} eq "") {
            print "\nwunderground api key missing\n";
            exit;
        }
        my $wunder_code = uc($1);
        $w_type = "wunder";
        my $ua = LWP::UserAgent->new(connect_timeout => 15);
        my $response = $ua->get("https://api.weather.com/v2/pws/observations/current?stationId=$wunder_code&format=json&units=e&apiKey=$config{api_Key}");
        if ($response->is_success) {
            my $json = decode_json($response->decoded_content);
            $current = $json->{observations}->[0]->{temp};
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
        
        # Try hvwx as fallback if enabled and AccuWeather failed
        if ((not defined $current or $current eq "") && $config{use_hvwx} eq "YES") {
            eval {
                open my $hvwx, "-|", "hvwx", "-z", $location or die "Cannot run hvwx: $!";
                $current = <$hvwx>;
                chomp $current;
                $Temperature = $current;
                $Condition = "No Report";
                
                # Cache the data if enabled
                if ($config{cache_enabled} eq "YES" && defined $cache) {
                    $cache->set($location, {
                        temperature => $Temperature,
                        condition => $Condition,
                        type => "hvwx"
                    });
                }
            };
            if ($@) {
                warn "hvwx failed: $@\n";
            }
        }
        
        $w_type = "accu";
    }
}

if (not defined $current or $current eq "") {
    print "No Report\n";
    exit;
}

# Convert temperature to Celsius if needed
my $CTEMP = sprintf "%.0f", (5/9) * ($Temperature - 32);
print "$Temperature\N{DEGREE SIGN}F, $CTEMP\N{DEGREE SIGN}C / $Condition\n";

# If v given as second parameter just echo text, no sound
if (defined $display_only and $display_only eq "v") {
    exit;
}

# Clean up old files
unlink "$destdir/temperature";
unlink "$destdir/condition.ulaw";

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
    open my $temp_fh, ">", "$destdir/temperature" or die "Cannot open $destdir/temperature: $!";
    print $temp_fh $Temperature;
    close $temp_fh;
}

# Process weather condition if enabled
if ($config{process_condition} eq "YES") {
    my @conditions = map { lc($_) } split /\s+/, $Condition;
    my @condition_files;
    my $sound_dir = "/usr/share/asterisk/sounds/en/wx";
    
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
        open my $condition_fh, ">:raw", "$destdir/condition.ulaw" or die "Cannot open $destdir/condition.ulaw: $!";
        for my $file (@condition_files) {
            if (-f $file) {
                open my $in_fh, "<:raw", $file or die "Cannot open $file: $!";
                print $condition_fh scalar <$in_fh>;
                close $in_fh;
            }
        }
        close $condition_fh;
    } else {
        warn "No weather condition sound files found for: $Condition\n";
    }
}
