#!/usr/bin/perl

# saytime.pl - Announces the time and weather information.
# Copyright 2024, Jory A. Pratt, W5GLE
# Based on original work by D. Crompton, WA3DSP
#
# This script retrieves the current time and optionally the weather,
# then generates a concatenated audio file of the time and weather announcement.
# It can either play the audio, or save the sound file.

use strict;
use warnings;
use Time::Piece;
use Time::Zone;
use File::Spec;
use Getopt::Long;
use Log::Log4perl qw(:easy);

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
};

# Command line options
my %options = (
    location_id => undef,
    node_number => undef,
    silent => 0,
    use_24hour => DEFAULT_24HOUR,
    timezone => "UTC",
    verbose => DEFAULT_VERBOSE,
    dry_run => DEFAULT_DRY_RUN,
    test_mode => DEFAULT_TEST_MODE,
    weather_enabled => DEFAULT_WEATHER_ENABLED,
    greeting_enabled => DEFAULT_GREETING,
    custom_sound_dir => undef,
    log_file => undef,
);

# Parse command line options
GetOptions(
    \%options,
    "location_id=s",
    "node_number=s",
    "silent=i",
    "24hour!",
    "timezone=s",
    "verbose!",
    "dry-run!",
    "test!",
    "weather!",
    "greeting!",
    "sound-dir=s",
    "log=s",
) or die "Usage: $0 [options] [location_id] node_number\n" .
    "Options:\n" .
    "  --location_id=ID    Location ID for weather\n" .
    "  --node_number=NUM   Node number for announcement\n" .
    "  --silent=NUM        Silent mode (0=voice, 1=save time+weather, 2=save weather only)\n" .
    "  --24hour           Use 24-hour clock\n" .
    "  --timezone=TZ      Use specified timezone\n" .
    "  --verbose          Enable verbose output\n" .
    "  --dry-run          Don't actually play or save files\n" .
    "  --test             Test sound files before playing\n" .
    "  --weather          Enable weather announcements\n" .
    "  --greeting         Enable greeting messages\n" .
    "  --sound-dir=DIR    Use custom sound directory\n" .
    "  --log=FILE         Log to specified file\n";

# Handle legacy command line arguments
if (@ARGV) {
    $options{location_id} = shift @ARGV if @ARGV > 1;
    $options{node_number} = shift @ARGV;
    if (@ARGV) {
        $options{silent} = shift @ARGV;
        if (@ARGV) {
            $options{use_24hour} = shift @ARGV;
        }
    }
}

# Setup logging
setup_logging();

# Validate options
validate_options();

# Get current time
my $now = Time::Piece->new;
my $hour = $now->hour;
my $minute = $now->minute;

# Create time string for logging
my $time_str = sprintf("%02d:%02d", $hour, $minute);

# Log the announcement
INFO("Announcing time: $time_str");

# Get the current time in the specified timezone
my $time = Time::Piece->new;
if ($options{timezone}) {
    $time = $time->localtime($options{timezone});
}

# Format the time based on 12/24 hour setting
my $hour_str;
if (!$options{use_24hour}) {
    my $hour_12 = $time->hour % 12;
    $hour_12 = 12 if $hour_12 == 0;
    $hour_str = sprintf("%d", $hour_12);
} else {
    $hour_str = sprintf("%02d", $time->hour);
}

# Get the minute sound file
my $minute_sound = get_sound_file("$minute");
if (!$minute_sound) {
    ERROR("Could not find minute sound file for $minute");
    exit 1;
}

# Get the hour sound file
my $hour_sound = get_sound_file($hour_str);
if (!$hour_sound) {
    ERROR("Could not find hour sound file for $hour_str");
    exit 1;
}

# Get AM/PM sound if using 12-hour format
my $ampm_sound = "";
if (!$options{use_24hour}) {
    $ampm_sound = get_sound_file($time->hour < 12 ? "a" : "p");
    if (!$ampm_sound) {
        ERROR("Could not find AM/PM sound file");
        exit 1;
    }
}

# Get the greeting sound file based on time of day
my $greeting_sound = "";
if ($options{greeting_enabled}) {
    my $hour = $time->hour;
    if ($hour >= 5 && $hour < 12) {
        $greeting_sound = get_sound_file("goodmorning");
    } elsif ($hour >= 12 && $hour < 17) {
        $greeting_sound = get_sound_file("goodafternoon");
    } else {
        $greeting_sound = get_sound_file("goodevening");
    }
    if (!$greeting_sound) {
        ERROR("Could not find greeting sound file");
        exit 1;
    }
}

# Get the "the time is" sound file
my $thetimeis_sound = get_sound_file("thetimeis");
if (!$thetimeis_sound) {
    ERROR("Could not find 'the time is' sound file");
    exit 1;
}

# Create the concatenated sound file
my $output_file = File::Spec->catfile(TMP_DIR, "current-time");
my $sound_files = "";
$sound_files .= "$greeting_sound " if $greeting_sound;
$sound_files .= "$thetimeis_sound ";
$sound_files .= "$hour_sound $minute_sound";
$sound_files .= " $ampm_sound" if $ampm_sound;

# Concatenate the sound files
my $cat_result = system("cat $sound_files > $output_file");
if ($cat_result != 0) {
    ERROR("Failed to create sound file: $output_file");
    exit 1;
}

# Set proper permissions
chmod 0644, $output_file or WARN("Failed to set permissions on $output_file: $!");

# Build and execute the Asterisk command
my $cmd = "/usr/sbin/asterisk -rx \"rpt localplay " . $options{node_number} . " " . $output_file . "\"";
INFO("Executing command: $cmd");
system($cmd);
my $exit_code = $? >> 8;

if ($exit_code != 0) {
    ERROR("Command failed with exit code $exit_code");
    exit $exit_code;
}

INFO("Time announcement completed successfully");
exit 0;

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
    die "Node number is required\n" unless defined $options{node_number};
    die "Invalid node number format: $options{node_number}\n" unless $options{node_number} =~ /^\d{6}$/;
    die "Invalid silent value: $options{silent}\n" if $options{silent} < 0 || $options{silent} > 2;
    
    # Validate timezone
    eval { tz_offset($options{timezone}) };
    die "Invalid timezone: $options{timezone}\n" if $@;
    
    # Validate sound directory if specified
    if ($options{custom_sound_dir}) {
        die "Custom sound directory does not exist: $options{custom_sound_dir}\n" 
            unless -d $options{custom_sound_dir};
        die "Custom sound directory is not readable: $options{custom_sound_dir}\n"
            unless -r $options{custom_sound_dir};
    }
    
    # Validate required sound files
    my $sound_dir = $options{custom_sound_dir} || BASE_SOUND_DIR;
    my @required_files = (
        "$sound_dir/rpt/thetimeis.ulaw",
        "$sound_dir/digits/0.ulaw",
        "$sound_dir/digits/1.ulaw",
        "$sound_dir/digits/2.ulaw",
        "$sound_dir/digits/3.ulaw",
        "$sound_dir/digits/4.ulaw",
        "$sound_dir/digits/5.ulaw",
        "$sound_dir/digits/6.ulaw",
        "$sound_dir/digits/7.ulaw",
        "$sound_dir/digits/8.ulaw",
        "$sound_dir/digits/9.ulaw",
        "$sound_dir/digits/a-m.ulaw",
        "$sound_dir/digits/p-m.ulaw",
        "$sound_dir/rpt/goodmorning.ulaw",
        "$sound_dir/rpt/goodafternoon.ulaw",
        "$sound_dir/rpt/goodevening.ulaw"
    );
    
    foreach my $file (@required_files) {
        die "Required sound file not found: $file\n" unless -f $file;
        die "Required sound file is not readable: $file\n" unless -r $file;
    }
    
    # Validate weather script if weather is enabled
    if ($options{weather_enabled}) {
        die "Weather script not found: " . WEATHER_SCRIPT . "\n" unless -f WEATHER_SCRIPT;
        die "Weather script is not executable: " . WEATHER_SCRIPT . "\n" unless -x WEATHER_SCRIPT;
    }
    
    # Validate temporary directory
    die "Temporary directory does not exist: " . TMP_DIR . "\n" unless -d TMP_DIR;
    die "Temporary directory is not writable: " . TMP_DIR . "\n" unless -w TMP_DIR;
}

sub get_sound_file {
    my ($num) = @_;
    my $sound_dir = $options{custom_sound_dir} || BASE_SOUND_DIR;
    
    # Handle single digits (0-9)
    if ($num =~ /^\d$/) {
        my $file = "$sound_dir/digits/$num.ulaw";
        if (-f $file && -r $file) {
            return $file;
        }
        ERROR("Sound file not found or not readable: $file");
        return undef;
    }
    
    # Handle double digits (10-59)
    if ($num =~ /^[1-5]\d$/) {
        my $tens = int($num / 10) * 10;
        my $ones = $num % 10;
        my $tens_file = "$sound_dir/digits/$tens.ulaw";
        my $ones_file = $ones ? "$sound_dir/digits/$ones.ulaw" : "";
        
        if (-f $tens_file && -r $tens_file) {
            if ($ones == 0 || (-f $ones_file && -r $ones_file)) {
                return $tens_file . ($ones ? " $ones_file" : "");
            }
        }
        ERROR("Sound file not found or not readable: $tens_file" . ($ones ? " or $ones_file" : ""));
        return undef;
    }
    
    ERROR("Invalid number format: $num");
    return undef;
}