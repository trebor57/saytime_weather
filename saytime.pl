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
use File::Spec;
use constant tmp_dir => "/tmp";
use constant base_sound_dir => "/usr/share/asterisk/sounds/en";
use constant weather_script => "/usr/local/sbin/weather.pl";

# Command-line arguments
my ($location_id, $node_number, $silent, $use_24hour) = @ARGV;

# Validate arguments
if (!defined $node_number || @ARGV > 4) {
    die "Usage: $0 [<location_id>] node_number [silent] [24hour]\n" .
        "    silent: 0=voice, 1=save time+weather, 2=save weather only\n" .
        "    24hour: 1=use 24-hour clock, 0=use 12-hour clock (default)\n";
}

$silent //= 0;
$use_24hour //= 0;
die "Invalid silent value: $silent\n" if $silent < 0 || $silent > 2;
die "Invalid 24hour value: $use_24hour\n" if $use_24hour != 0 && $use_24hour != 1;

# Weather processing
my $weather_enabled = defined $location_id && -x weather_script;
my $local_weather_temp = "";
my $weather_condition_file = File::Spec->catfile(tmp_dir, "condition.ulaw");

if ($weather_enabled) {
    my $weather_cmd = sprintf("%s %s", weather_script, $location_id);
    my $weather_result = system($weather_cmd);
    if ($weather_result != 0) {
        warn "Weather script failed with exit code: $weather_result\n";
    }
    my $temp_file = File::Spec->catfile(tmp_dir, "temperature");
    if (-f $temp_file) {
        open my $temp_fh, '<', $temp_file or die "Cannot open temperature file: $!";
        chomp($local_weather_temp = <$temp_fh>);
        close $temp_fh;
    }
}

# Time processing
my $now = localtime;
my ($hour, $minute) = ($now->hour, $now->minute);

my $time_sound_files = process_time($hour, $minute, $use_24hour);
my $weather_sound_files = $weather_enabled ? process_weather($local_weather_temp) : "";

# Combine and play
my $output_file = File::Spec->catfile(tmp_dir, "current-time.ulaw");
my $final_sound_files = "";

if ($silent == 0 || $silent == 1) { #time + weather
    $final_sound_files = "$time_sound_files $weather_sound_files";
} elsif ($silent == 2 && $weather_enabled) { #weather only
    $final_sound_files = "$weather_sound_files";
}

if ($final_sound_files) {
    my $cat_result = system("cat $final_sound_files > $output_file");
    if ($cat_result != 0) {
        warn "cat command failed with exit code: $cat_result\n";
    }
}

if ($silent == 0) {
    my $asterisk_file = File::Spec->catfile(tmp_dir, "current-time");
    my $asterisk_cmd = sprintf(
        "/usr/sbin/asterisk -rx \"rpt localplay %s %s\"", $node_number, $asterisk_file
    );
    my $asterisk_result = system($asterisk_cmd);
    if ($asterisk_result != 0) {
        warn "Asterisk command failed with exit code: " . "$asterisk_result\n";
    }
    sleep 5;
    cleanup_files($output_file, $weather_enabled, $silent);
} elsif ($silent == 1 || $silent == 2) {
    print "Saved sound file to $output_file\n";
    cleanup_files(undef, $weather_enabled, $silent);
}

# Subroutines
sub process_time {
    my ($hour, $minute, $use_24hour) = @_;
    my $files = "";

    $files .= base_sound_dir . "/rpt/good" . ($hour < 12 ? "morning" : $hour < 18 ? "afternoon" : "evening") . ".ulaw ";
    $files .= base_sound_dir . "/rpt/thetimeis.ulaw ";

    if ($use_24hour) {
        $files .= format_number($hour);
        if ($minute < 10 && $minute > 0) {
            $files .= base_sound_dir . "/digits/0.ulaw ";
            $files .= format_number($minute);
        } else {
            $files .= format_number($minute) if $minute != 0;
        }
    } else {
        my $display_hour =
            ($hour == 0 || $hour == 12) ? 12 : ($hour > 12 ? $hour - 12 : $hour);
        $files .= base_sound_dir . "/digits/$display_hour.ulaw ";
        $files .= format_number($minute) if $minute != 0;
        $files .= base_sound_dir . "/digits/" . ($hour < 12 ? "a-m" : "p-m") . ".ulaw ";
    }

    return $files;
}

sub process_weather {
    my ($temp) = @_;
    return "" unless $temp;
    my $files = base_sound_dir . "/silence/1.ulaw " .
        base_sound_dir . "/wx/weather.ulaw " .
        base_sound_dir . "/wx/conditions.ulaw $weather_condition_file ";

    $files .= base_sound_dir . "/wx/temperature.ulaw ";
    my $temp_int = int($temp);
    $files .= base_sound_dir . "/digits/minus.ulaw " if $temp_int < 0;
    $temp_int = abs($temp_int);

    if ($temp_int >= 100) {
        $files .= base_sound_dir . "/digits/1.ulaw " . base_sound_dir . "/digits/hundred.ulaw ";
        $temp_int %= 100;
    }

    $files .= format_number($temp_int);
    $files .= base_sound_dir . "/wx/degrees.ulaw ";
    return $files;
}

sub format_number {
    my ($num) = @_;
    return base_sound_dir . "/digits/$num.ulaw " if $num < 20;
    my $tens = int($num / 10) * 10;
    my $ones = $num % 10;
    return base_sound_dir . "/digits/$tens.ulaw " . ($ones ? base_sound_dir . "/digits/$ones.ulaw " : "");
}

sub cleanup_files {
    my ($file_to_delete, $weather_enabled, $silent) = @_;
    if (defined $file_to_delete && $silent == 0) {
        unlink $file_to_delete if -e $file_to_delete;
    }
    if ($weather_enabled && ($silent == 1 || $silent == 2 || $silent == 0)) {
        unlink File::Spec->catfile(tmp_dir, "temperature")
            if -e File::Spec->catfile(tmp_dir, "temperature");
        unlink $weather_condition_file if -e $weather_condition_file;
    }
}