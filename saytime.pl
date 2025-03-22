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

# Get command line arguments
my ($zipcode, $node, $silent, $use_24hour) = @ARGV;

# Validate arguments
if (!defined $zipcode || !defined $node) {
    print "Usage: $0 <zipcode> <node> [silent] [24hour]\n";
    print "  zipcode: Required - ZIP code for location\n";
    print "  node: Required - Node number for announcement\n";
    print "  silent: Optional - Silent mode (0=voice, 1=save time+weather, 2=save weather only)\n";
    print "  24hour: Optional - Use 24-hour clock (0=12-hour, 1=24-hour)\n";
    exit 1;
}

# Set default values for optional arguments
$silent = 0 unless defined $silent;
$use_24hour = 0 unless defined $use_24hour;

# Validate silent and 24hour values
if ($silent < 0 || $silent > 2) {
    print "Error: Invalid silent value. Must be 0, 1, or 2.\n";
    exit 1;
}

if ($use_24hour != 0 && $use_24hour != 1) {
    print "Error: Invalid 24hour value. Must be 0 or 1.\n";
    exit 1;
}

# Setup logging
setup_logging();

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
if (!$use_24hour) {
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
if (!$use_24hour) {
    $ampm_sound = get_sound_file($time->hour < 12 ? "a" : "p");
    if (!$ampm_sound) {
        ERROR("Could not find AM/PM sound file");
        exit 1;
    }
}

# Build the command
my $cmd = "asterisk -rx 'dialplan exec saytime $hour_sound $minute_sound";
$cmd .= " $ampm_sound" if $ampm_sound;
$cmd .= " $node'";

# Execute the command
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

sub get_sound_file {
    my ($name) = @_;
    my $sound_dir = $options{custom_sound_dir} || BASE_SOUND_DIR;
    my $file = File::Spec->catfile($sound_dir, "$name.ulaw");
    return -f $file ? $file : undef;
}