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

sub validate_options {
    die "Node number is required\n" unless defined $options{node_number};
    die "Invalid node number format: $options{node_number}\n" unless $options{node_number} =~ /^\d+$/;
    die "Invalid silent value: $options{silent}\n" if $options{silent} < 0 || $options{silent} > 2;
    
    # Validate timezone
    eval { tz_offset($options{timezone}) };
    die "Invalid timezone: $options{timezone}\n" if $@;
    
    # Validate sound directory if specified
    if ($options{custom_sound_dir}) {
        die "Custom sound directory does not exist: $options{custom_sound_dir}\n" 
            unless -d $options{custom_sound_dir};
    }
}

sub get_current_time {
    my $tz = $options{timezone};
    my $now = localtime;
    if ($tz ne "UTC") {
        my $offset = tz_offset($tz);
        $now += $offset;
    }
    return $now;
}

sub process_time {
    my ($now, $use_24hour) = @_;
    my $files = "";
    my $sound_dir = $options{custom_sound_dir} || BASE_SOUND_DIR;
    
    if ($options{greeting_enabled}) {
        my $hour = $now->hour;
        my $greeting = $hour < 12 ? "morning" : $hour < 18 ? "afternoon" : "evening";
        $files .= "$sound_dir/rpt/good$greeting.ulaw ";
    }
    
    $files .= "$sound_dir/rpt/thetimeis.ulaw ";
    
    my ($hour, $minute) = ($now->hour, $now->minute);
    
    if ($use_24hour) {
        $files .= format_number($hour, $sound_dir);
        if ($minute < 10 && $minute > 0) {
            $files .= "$sound_dir/digits/0.ulaw ";
            $files .= format_number($minute, $sound_dir);
        } else {
            $files .= format_number($minute, $sound_dir) if $minute != 0;
        }
    } else {
        my $display_hour = ($hour == 0 || $hour == 12) ? 12 : ($hour > 12 ? $hour - 12 : $hour);
        $files .= "$sound_dir/digits/$display_hour.ulaw ";
        $files .= format_number($minute, $sound_dir) if $minute != 0;
        $files .= "$sound_dir/digits/" . ($hour < 12 ? "a-m" : "p-m") . ".ulaw ";
    }
    
    return $files;
}

sub process_weather {
    my ($location_id) = @_;
    return "" unless $options{weather_enabled} && defined $location_id;
    
    my $weather_cmd = sprintf("%s %s", WEATHER_SCRIPT, $location_id);
    my $weather_result = system($weather_cmd);
    
    if ($weather_result != 0) {
        WARN("Weather script failed with exit code: $weather_result");
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

sub play_announcement {
    my ($file, $node) = @_;
    my $asterisk_file = File::Spec->catfile(TMP_DIR, "current-time");
    my $asterisk_cmd = sprintf(
        "/usr/sbin/asterisk -rx \"rpt localplay %s %s\"", $node, $asterisk_file
    );
    
    if ($options{test_mode}) {
        INFO("Test mode - would run: $asterisk_cmd");
        return;
    }
    
    my $asterisk_result = system($asterisk_cmd);
    if ($asterisk_result != 0) {
        ERROR("Asterisk command failed with exit code: $asterisk_result");
    }
    sleep 5;
}

sub cleanup_files {
    my ($file_to_delete, $weather_enabled, $silent) = @_;
    if (defined $file_to_delete && $silent == 0) {
        unlink $file_to_delete if -e $file_to_delete;
    }
    if ($weather_enabled && ($silent == 1 || $silent == 2 || $silent == 0)) {
        unlink File::Spec->catfile(TMP_DIR, "temperature")
            if -e File::Spec->catfile(TMP_DIR, "temperature");
        unlink File::Spec->catfile(TMP_DIR, "condition.ulaw")
            if -e File::Spec->catfile(TMP_DIR, "condition.ulaw");
    }
}