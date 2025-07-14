# Saytime Weather

A time and weather announcement system for Asterisk, designed for use with radio systems and repeater controllers.

## Features

- Time announcements in 12/24-hour format
- Current weather conditions and temperature
- Support for 5-digit location codes and airport codes
- Configurable greeting messages (morning/afternoon/evening)
- Silent mode for saving announcements
- Comprehensive logging options

## Installation

### From Debian Package

1. **Install the Package and Dependencies**:
   Goto the temp folder
   ```bash
   cd /tmp
   ```

   Then we can download the Package:
   ```
   wget https://github.com/hardenedpenguin/saytime_weather/releases/download/v2.6.4/saytime-weather_2.6.4_all.deb
   ```

   Then we can install the dependancies:
   ```
   sudo apt install ./saytime-weather_2.6.4_all.deb
   ```

   This will:
   - Download the package directly from GitHub releases
   - Install the package and automatically handle dependencies using `apt`

## Configuration

1. Create or edit the configuration file at `/etc/asterisk/local/weather.ini`:
   ```ini
   [weather]
   process_condition = YES
   Temperature_mode = F  ; Set to C for Celsius
   use_accuweather = YES
   wunderground_api_key = YOUR_WUNDERGROUND_API_KEY
   timezone_api_key = YOUR_TIMEZONEDB_API_KEY
   geocode_api_key = YOUR_OPENCAGE_API_KEY
   cache_enabled = YES
   cache_duration = 1800
   ```

## Usage

```bash
saytime.pl [options] -l <LOCATION_ID> -n <NODE_NUMBER>
```

### Options

- `-l`, `--location_id=ID`       Location ID for weather (5 digits or airport code)
- `-n`, `--node_number=NUM`      Node number for announcement (required)
- `-s`, `--silent=NUM`           Silent mode (0 = voice, 1 = save time + weather, 2 = save weather only)
- `-h`, `--use_24hour`           Use 24-hour clock (default: off)
- `-m`, `--method=METHOD`        Playback method (`localplay` or `playback`, default: `localplay`)
- `-v`, `--verbose`              Enable verbose output (default: off)
- `-d`, `--dry-run`              Don't play or save files (default: off)
- `-t`, `--test`                 Test sound files before playing (default: off)
- `-w`, `--weather`              Enable weather announcements (default: on)
- `-g`, `--greeting`             Enable greeting messages (default: on)
- `--sound-dir=DIR`             Use custom sound directory
- `--log=FILE`                  Log to specified file

### Examples

Announce time and weather:
```bash
saytime.pl -l LOCATION_ID -n NODE_NUMBER
```

Use 24-hour time format:
```bash
saytime.pl -l LOCATION_ID -n NODE_NUMBER -h
```

Save announcement to file:
```bash
saytime.pl -l LOCATION_ID -n NODE_NUMBER -s 1
```

Using airport code:
```bash
saytime.pl -l AIRPORT_CODE -n NODE_NUMBER
```

## Files

- `/usr/sbin/saytime`               Main announcement script
- `/usr/sbin/weather`               Weather retrieval script
- `/etc/asterisk/local/weather.ini`       Weather configuration
- `/usr/share/asterisk/sounds/en/wx/`     Weather sound files

## Crontab example
```
sudo crontab -e
```
```
00 03-23 * * * /usr/bin/nice -19 /usr/sbin/saytime.pl -l zipecode-n nodenumber > /dev/null 
```
## Support

For issues or feature requests, visit:
[https://github.com/w5gle/saytime-weather](https://github.com/w5gle/saytime-weather)

## License

Copyright 2025, Jory A. Pratt, W5GLE  
Based on original work by D. Crompton, WA3DSP

