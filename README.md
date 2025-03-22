# SayTime and Weather for AllStar

A collection of Perl scripts for announcing time and weather conditions over AllStar nodes. These scripts are designed to work with Asterisk's sound system to provide automated time and weather announcements.

## Features

- **Time Announcements**
  - Automatic hourly time announcements
  - Support for 12-hour and 24-hour formats
  - Configurable announcement times via crontab
  - Timezone support

- **Weather Announcements**
  - Current weather conditions
  - Support for ZIP codes and airport codes
  - Weather Underground API support for international airport codes
  - Configurable weather data source selection
  - Caching for improved performance
  - Custom sound directory support
  - Comprehensive logging

## Installation

### Debian Package

The easiest way to install is using the Debian package:

```bash
# Add the repository
echo "deb http://w5gle.ddns.net/~anarchy/debian/ ./" | sudo tee /etc/apt/sources.list.d/saytime-weather.list

# Update package list
sudo apt update

# Install the package
sudo apt install saytime-weather
```

You can also download the package directly from:
http://w5gle.ddns.net/~anarchy/debian/saytime-weather/

### Manual Installation

If you prefer to install manually:

1. Clone the repository:
```bash
git clone https://github.com/yourusername/saytime-weather.git
cd saytime-weather
```

2. Install dependencies:
```bash
sudo apt install plocate libwww-perl libjson-perl libtime-piece-perl libtime-local-perl liblog-log4perl-perl libcache-cache-perl liburi-perl
```

3. Run the installation:
```bash
sudo make install-all
```

## Usage

### Time Announcements

To announce time:
```bash
sudo ./saytime.pl <zipcode> <node> [hour] [minute]
```

Example:
```bash
sudo ./saytime.pl 77511 546054 0 1
```

To setup automatic time announcements, add the following to root's crontab:
```bash
sudo crontab -e
```

Add the line (modify time/zip/node as needed):
```
00 07-23 * * * (/usr/bin/nice -19 /usr/local/sbin/saytime.pl 77511 546054 > /dev/null)
```

This will announce time hourly from 7AM to 11PM.

### Weather Announcements

To announce weather:
```bash
sudo ./weather.pl <location_id> <node>
```

Location ID can be:
- ZIP code (e.g., 77511)
- ICAO airport code (e.g., KIAH)
- City name (e.g., "Houston, TX")

Example:
```bash
sudo ./weather.pl 77511 546054
```

### Weather Underground API

For international airport codes, you'll need to set up the Weather Underground API:

1. Get an API key from [Weather Underground](https://www.wunderground.com/weather/api)
2. Set the environment variable:
```bash
export WUNDERGROUND_API_KEY="your_api_key_here"
```

3. Enable Weather Underground in the configuration:
```bash
echo 'use_wunderground="YES"' > /etc/weather.ini
```

## Configuration

### Sound Files

Sound files are installed in:
- Time sounds: `/usr/share/asterisk/sounds/en/`
- Weather sounds: `/usr/share/asterisk/sounds/en/wx/`

### Logging

Logs are written to:
- `/var/log/saytime.log` for time announcements
- `/var/log/weather.log` for weather announcements

Enable verbose logging with the `-v` option:
```bash
sudo ./weather.pl -v 77511 546054
```

## Dependencies

- plocate
- libwww-perl
- libjson-perl
- libtime-piece-perl
- libtime-local-perl
- liblog-log4perl-perl
- libcache-cache-perl
- liburi-perl

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Author

Jory A. Pratt (W5GLE)
- Email: jory@w5gle.org
- Website: http://w5gle.ddns.net/
