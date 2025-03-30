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
    verbose => DEFAULT_VERBOSE,
    dry_run => DEFAULT_DRY_RUN,
    test_mode => DEFAULT_TEST_MODE,
    weather_enabled => DEFAULT_WEATHER_ENABLED,
    greeting_enabled => DEFAULT_GREETING,
    custom_sound_dir => undef,
    log_file => undef,
    playback => 'localplay',
);

# Parse command line options
GetOptions(
    \%options,
    "location_id|l=s",
    "node_number|n=s",
    "silent|s=i",
    "use_24hour|h!",
    "verbose|v!",
    "dry-run|d!",
    "test|t!",
    "weather|w!",
    "greeting|g!",
    "sound-dir=s",
    "log=s",
    "playback|p=s",
) or show_usage();

# Setup logging
setup_logging();

# Validate options
validate_options();

# Get current time in specified timezone
my $now = get_current_time();

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
    play_announcement($output_file, $options{node_number});
    cleanup_files($output_file, $options{weather_enabled}, $options{silent});
} elsif ($options{silent} == 1 || $options{silent} == 2) {
    INFO("Saved sound file to $output_file");
    cleanup_files(undef, $options{weather_enabled}, $options{silent});
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
    return localtime;
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
    } else {
        WARN("Temperature file not found: $temp_file");
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
        "/usr/sbin/asterisk -rx \"rpt %s %s %s\"",
        $options{playback}, $node, $asterisk_file
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

sub show_usage {
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
    "  -p, --playback=METHOD   Playback method (default: localplay)\n" .
    "      --sound-dir=DIR     Use custom sound directory\n" .
    "                          (default: /usr/share/asterisk/sounds/en)\n" .
    "      --log=FILE          Log to specified file (default: none)\n\n" .
    "Location ID can be either:\n" .
    "  - 5-digit location code (e.g., 77511)\n" .
    "  - 3-4 letter airport code (e.g., KHOU)\n";
}