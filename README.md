# Saytime Weather

A comprehensive time and weather announcement system for Asterisk PBX, designed specifically for radio systems, repeater controllers, and amateur radio applications. This system provides automated voice announcements of current time and weather conditions using high-quality synthesized speech.

## 🚀 Features

- **Time Announcements**: Support for both 12-hour and 24-hour time formats
- **Weather Integration**: Real-time weather conditions and temperature from multiple providers
- **Location Support**: 5-digit ZIP codes and airport codes (ICAO/IATA)
- **Smart Greetings**: Context-aware greeting messages (morning/afternoon/evening)
- **Flexible Output**: Voice playback or file generation for later use
- **Comprehensive Logging**: Detailed logging for troubleshooting and monitoring
- **Caching System**: Intelligent caching to reduce API calls and improve performance
- **Multiple Weather Providers**: Support for Weather Underground and AccuWeather APIs
- **Timezone Support**: Automatic timezone detection and handling

## 📋 Requirements

- **Asterisk PBX** (tested with versions 16+)
- **Perl 5.20+** with the following modules:
  - `LWP::UserAgent`
  - `JSON`
  - `Config::IniFiles`
  - `Time::Piece`
  - `File::Path`
  - `Getopt::Long`
- **Internet Connection** for weather API access
- **API Keys** for weather services (see Configuration section)

## 🛠️ Installation

### Option 1: Debian Package (Recommended)

1. **Download the latest release**:
   ```bash
   cd /tmp
   wget https://github.com/hardenedpenguin/saytime_weather/releases/download/v2.6.6/saytime-weather_2.6.6_all.deb
   ```

2. **Install the package**:
   ```bash
   sudo apt install ./saytime-weather_2.6.6_all.deb
   ```

   This will automatically:
   - Install all required dependencies
   - Set up the system directories
   - Configure the sound files
   - Create necessary configuration files

### Option 2: Manual Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/hardenedpenguin/saytime_weather.git
   cd saytime_weather
   ```

2. **Install dependencies**:
   ```bash
   sudo apt update
   sudo apt install asterisk perl liblwp-useragent-perl libjson-perl libconfig-inifiles-perl
   ```

3. **Install the scripts**:
   ```bash
   sudo make install
   ```

## ⚙️ Configuration

### Weather Configuration

Create or edit `/etc/asterisk/local/weather.ini`:

```ini
[weather]
# Weather processing settings
process_condition = YES
Temperature_mode = F                    ; F for Fahrenheit, C for Celsius
use_accuweather = YES                   ; Use AccuWeather API
cache_enabled = YES                     ; Enable caching
cache_duration = 1800                   ; Cache duration in seconds (30 minutes)

# API Keys (get these from respective services)
wunderground_api_key = YOUR_WUNDERGROUND_API_KEY
timezone_api_key = YOUR_TIMEZONEDB_API_KEY
geocode_api_key = YOUR_OPENCAGE_API_KEY

# Optional: Custom sound directory
# sound_directory = /path/to/custom/sounds
```

### API Keys Setup

1. **Weather Underground** (optional if using AccuWeather):
   - Visit [Weather Underground API](https://www.wunderground.com/weather/api/)
   - Sign up for a free API key

2. **AccuWeather** (recommended):
   - Visit [AccuWeather API](https://developer.accuweather.com/)
   - Create a free account and get your API key

3. **TimezoneDB** (for timezone detection):
   - Visit [TimezoneDB](https://timezonedb.com/api)
   - Get a free API key

4. **OpenCage** (for geocoding):
   - Visit [OpenCage Geocoding](https://opencagedata.com/)
   - Sign up for a free API key

## 🎯 Usage

### Basic Usage

```bash
saytime.pl -l <LOCATION_ID> -n <NODE_NUMBER>
```

### Command Line Options

| Option | Long Option | Description | Default |
|--------|-------------|-------------|---------|
| `-l` | `--location_id=ID` | Location ID (ZIP code or airport code) | Required |
| `-n` | `--node_number=NUM` | Node number for announcement | Required |
| `-s` | `--silent=NUM` | Silent mode: 0=voice, 1=save both, 2=save weather only | 0 |
| `-h` | `--use_24hour` | Use 24-hour time format | 12-hour |
| `-m` | `--method=METHOD` | Playback method: `localplay` or `playback` | `localplay` |
| `-v` | `--verbose` | Enable verbose output | Off |
| `-d` | `--dry-run` | Don't play or save files (test mode) | Off |
| `-t` | `--test` | Test sound files before playing | Off |
| `-w` | `--weather` | Enable weather announcements | On |
| `-g` | `--greeting` | Enable greeting messages | On |
| | `--sound-dir=DIR` | Custom sound directory | Default |
| | `--log=FILE` | Log to specified file | Stdout |

### Usage Examples

**Basic time and weather announcement**:
```bash
saytime.pl -l 12345 -n 1
```

**24-hour time format**:
```bash
saytime.pl -l 12345 -n 1 -h
```

**Save announcement to file**:
```bash
saytime.pl -l 12345 -n 1 -s 1
```

**Using airport code**:
```bash
saytime.pl -l KDFW -n 1
```

**Test mode (no actual playback)**:
```bash
saytime.pl -l 12345 -n 1 -d -v
```

**Custom sound directory**:
```bash
saytime.pl -l 12345 -n 1 --sound-dir=/custom/sounds
```

## 📁 File Structure

```
/usr/sbin/
├── saytime.pl          # Main announcement script
└── weather.pl          # Weather retrieval script

/etc/asterisk/local/
└── weather.ini         # Weather configuration file

/usr/share/asterisk/sounds/en/wx/
├── clear.ulaw          # Weather condition sounds
├── cloudy.ulaw
├── rain.ulaw
├── sunny.ulaw
├── temperature.ulaw    # Temperature announcements
├── degrees.ulaw
└── ...                 # Additional weather sounds
```

## ⏰ Automation

### Crontab Setup

Add to your system crontab for automated announcements:

```bash
sudo crontab -e
```

**Example: Announce every hour from 3 AM to 11 PM**:
```cron
00 03-23 * * * /usr/bin/nice -19 /usr/sbin/saytime.pl -l 12345 -n 1 > /dev/null 2>&1
```

**Example: Announce every 30 minutes during daylight hours**:
```cron
0,30 06-22 * * * /usr/bin/nice -19 /usr/sbin/saytime.pl -l 12345 -n 1 > /dev/null 2>&1
```

### Asterisk Integration

Add to your Asterisk dialplan (`/etc/asterisk/extensions.conf`):

```asterisk
[weather-announcement]
exten => 1234,1,Answer()
exten => 1234,2,Exec(/usr/sbin/saytime.pl -l 12345 -n 1)
exten => 1234,3,Hangup()
```

## 🔧 Troubleshooting

### Common Issues

1. **"API key not found" errors**:
   - Verify your API keys in `/etc/asterisk/local/weather.ini`
   - Check that the keys are valid and have sufficient quota

2. **No sound output**:
   - Verify Asterisk is running: `sudo systemctl status asterisk`
   - Check sound file permissions: `ls -la /usr/share/asterisk/sounds/en/wx/`
   - Test with verbose mode: `saytime.pl -l 12345 -n 1 -v -t`

3. **Weather data not updating**:
   - Check internet connectivity
   - Verify API service status
   - Clear cache: Delete files in `/tmp/weather_cache/`

### Debug Mode

Run with verbose output for detailed debugging:

```bash
saytime.pl -l 12345 -n 1 -v -d
```

### Log Files

Check system logs for errors:
```bash
sudo journalctl -u asterisk -f
tail -f /var/log/asterisk/full
```

## 🤝 Contributing

We welcome contributions! Please feel free to:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

### Development Setup

```bash
git clone https://github.com/hardenedpenguin/saytime_weather.git
cd saytime_weather
# Make your changes
make test
make install
```

## 📄 License

**Copyright 2025, Jory A. Pratt, W5GLE**

Based on original work by D. Crompton, WA3DSP

This project is licensed under the terms specified in the LICENSE file.

## 🆘 Support

- **GitHub Issues**: [Report bugs or request features](https://github.com/w5gle/saytime-weather/issues)
- **Documentation**: Check the [Wiki](https://github.com/w5gle/saytime-weather/wiki) for detailed guides
- **Community**: Join our [Discussions](https://github.com/w5gle/saytime-weather/discussions)

## 🙏 Acknowledgments

- Original concept and development by D. Crompton, WA3DSP
- Weather API integrations and improvements by the community
- Sound file contributions from various amateur radio operators

---

**Made with ❤️ for the amateur radio community**

