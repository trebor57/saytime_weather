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
    # weather.ini file does not exist set defaults
    $config{process_condition} = "YES";
    $config{Temperature_mode} = "F";
    $config{api_Key} = "";
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
    print "Edit /etc/asterisk/local/weather.ini to turn on/off condition reporting, C or F temperature, or to add an api key for wunderground\n";
    print "\n";
    exit 0;
}

my $destdir = "/tmp";
my $w_type;
my $current;

my $Temperature = "";
my $Condition = "";

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
    } else {
        print "Error retrieving wunderground data: " . $response->status_line . "\n";
        exit;
    }
    $config{process_condition} = "NO";
} else {
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
    }
    if (not defined $current or $current eq "") {
        open my $hvwx, "-|", "hvwx", "-z", $location or die "Cannot run hvwx: $!";
        $current = <$hvwx>;
        chomp $current;
        $Temperature = $current;
        $Condition = "No Report";
    }
    $w_type = "accu";
}

if (not defined $current or $current eq "") {
    print "No Report\n";
    exit;
}

my $CTEMP = sprintf "%.0f", (5/9) * ($Temperature - 32);
print "$Temperature\N{DEGREE SIGN}F, $CTEMP\N{DEGREE SIGN}C / $Condition\n";

# If v given as second parameter just echo text, no sound
if (defined $display_only and $display_only eq "v") {
    exit;
}

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

if ($Temperature >= $tmin and $Temperature <= $tmax) {
    open my $temp_fh, ">", "$destdir/temperature" or die "Cannot open $destdir/temperature: $!";
    print $temp_fh $Temperature;
    close $temp_fh;
}

if ($config{process_condition} eq "YES") {
    my @conditions = map { lc($_) } split /\s+/, $Condition;
    my @condition_files;
    my $sound_dir = "/usr/share/asterisk/sounds/en/wx";
    for my $cond (@conditions) {
        my $files_string = `locate $sound_dir/$cond.ulaw 2>/dev/null`;
        my @files = split /\n/, $files_string;
        chomp @files;
        push @condition_files, @files;
    }
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
    }
}
