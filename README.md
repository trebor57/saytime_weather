# Saytime Weather

A comprehensive time and weather announcement system for Asterisk PBX, designed specifically for radio systems, repeater controllers, and amateur radio applications. This system provides automated voice announcements of current time and weather conditions using high-quality synthesized speech.

**Version 2.7.4** - Major feature release! ICAO airport support, command line overrides, and day/night detection!

## 🚀 Features

- **Time Announcements**: Support for both 12-hour and 24-hour time formats
- **Location-Aware Timezone**: Time automatically matches weather location timezone
- **Worldwide Weather**: Real-time weather from postal codes OR ICAO airport codes globally
- **ICAO Airport Support**: 6000+ airports worldwide (KJFK, EGLL, CYYZ, LFPG, RJAA, NZSP)
- **No API Keys Required**: Fully functional out of the box - zero configuration!
- **Global Postal Codes**: US ZIP codes, Canadian postal codes, European codes, and more
- **Day/Night Detection**: Intelligent conditions (never says "sunny" at 2 AM)
- **Smart Greetings**: Context-aware greeting messages (morning/afternoon/evening)
- **Flexible Output**: Voice playback or file generation for later use
- **Comprehensive Logging**: Quiet by default, detailed with verbose flag
- **Caching System**: Intelligent caching (30 min default) for fast repeated lookups
- **Free Weather APIs**: Open-Meteo (weather) + Nominatim (geocoding) - both free forever
- **Simplified Code**: 23% code reduction from v2.6.6 for better maintainability

## 📋 Requirements

- **Asterisk PBX** (tested with versions 16+)
- **Perl 5.20+** with the following modules:
  - `LWP::UserAgent` (HTTP requests)
  - `JSON` (JSON parsing)
  - `DateTime` and `DateTime::TimeZone` (Time handling)
  - `Config::Simple` (Configuration)
  - `Log::Log4perl` (Logging)
  - `Cache::FileCache` (Caching)
- **Internet Connection** for weather API access
- **No API Keys Required!** - Works immediately after installation

## 🛠️ Installation

### Option 1: Debian Package (Recommended)

1. **Download the latest release**:
   ```bash
   cd /tmp
   wget https://github.com/hardenedpenguin/saytime_weather/releases/download/v2.7.4/saytime-weather_2.7.4_all.deb
   ```

2. **Install the package**:
   ```bash
   sudo apt install ./saytime-weather_2.7.4_all.deb
   ```

   This will automatically:
   - Install all required dependencies
   - Set up the system directories
   - Install sound files
   - Create configuration with sensible defaults
   - **No API keys needed** - works immediately!

## ⚙️ Configuration

### Weather Configuration (Optional!)

The system works out of the box with sensible defaults. Configuration is **optional**.

Edit `/etc/asterisk/local/weather.ini` (auto-created on first run):

```ini
[weather]
# Temperature display mode (F for Fahrenheit, C for Celsius)
Temperature_mode = F

# Default country for postal code lookups (ISO 3166-1 alpha-2 code)
# Options: us, ca, de, fr, uk, it, es, etc.
default_country = us

# Process weather condition announcements (YES/NO)
process_condition = YES

# Cache settings for faster repeated lookups
cache_enabled = YES
cache_duration = 1800                   ; 30 minutes in seconds
```

**That's it!** No API keys required.

### What Changed in v2.7.4?

**New in 2.7.4 - Major Feature Release! 🎉**
- ✈️ **ICAO Airport Support** - 6000+ airports worldwide (KJFK, EGLL, CYYZ, LFPG, RJAA)
- 🎛️ **Command Line Overrides** - Test any country with `-d fr 75001` or Celsius with `-t C`
- 🌞🌙 **Day/Night Detection** - Never says "sunny" at 2 AM anymore!
- 🗺️ **50+ Special Locations** - DXpedition sites & research stations (HEARD, BOUVET, ALERT, etc.)
- 📝 **Enhanced Config** - Comprehensive documentation in weather.ini template
- 🔧 **METAR Integration** - Aviation-grade weather from NOAA
- 🚀 **Improved API** - Updated to latest Open-Meteo current parameter

### What Changed in v2.7.3?

**New in 2.7.3:**
- 🐛 **CRITICAL FIX: Canadian postal code accuracy** - Ontario postal codes now resolve correctly
- 📍 **Added 50+ detailed FSA mappings** - N7L→Chatham-Kent, N6A→London, N8W→Windsor, etc.
- 🎯 **Improved location accuracy** - 3-character FSA lookup prioritized over generic regions
- 🔧 **Fixed lookup logic** - Canadian postal codes no longer use wrong province center

## 🎯 Usage

### Basic Usage

```bash
saytime.pl -l <POSTAL_CODE> -n <NODE_NUMBER>
```

**Works with any postal code worldwide!**

### Command Line Options

| Option | Long Option | Description | Default |
|--------|-------------|-------------|---------|
| `-l` | `--location_id=ID` | Postal code (US, Canada, Europe, etc.) | Required |
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

**US ZIP codes**:
```bash
saytime.pl -l 77511 -n 1     # Houston, TX
saytime.pl -l 10001 -n 1     # New York, NY
saytime.pl -l 90210 -n 1     # Beverly Hills, CA
```

**Canadian postal codes**:
```bash
saytime.pl -l M5H2N2 -n 1    # Toronto, ON
saytime.pl -l V6B1A1 -n 1    # Vancouver, BC
saytime.pl -l N7L3R5 -n 1    # Ontario
```

**European postal codes**:
```bash
saytime.pl -l 75001 -n 1     # Paris, France
saytime.pl -l 10115 -n 1     # Berlin, Germany
saytime.pl -l SW1A1AA -n 1   # London, UK
```

**24-hour time format**:
```bash
saytime.pl -l 77511 -n 1 -h
```

**Save announcement to file**:
```bash
saytime.pl -l 77511 -n 1 -s 1
```

**Test mode with verbose output**:
```bash
saytime.pl -l 77511 -n 1 -d -v
```

**Weather only (standalone)**:
```bash
weather.pl 77511 v           # Display only
weather.pl 77511             # Generate sound files
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
00 03-23 * * * /usr/bin/nice -19 /usr/sbin/saytime.pl -l 77511 -n 1 > /dev/null 2>&1
```

**Example: Announce every 30 minutes during daylight hours**:
```cron
0,30 06-22 * * * /usr/bin/nice -19 /usr/sbin/saytime.pl -l 77511 -n 1 > /dev/null 2>&1
```

**Example: Different time zones (announcements match location time)**:
```cron
# Announce for Los Angeles (Pacific Time)
00 * * * * /usr/bin/nice -19 /usr/sbin/saytime.pl -l 90210 -n 1 > /dev/null 2>&1

# Announce for New York (Eastern Time)  
00 * * * * /usr/bin/nice -19 /usr/sbin/saytime.pl -l 10001 -n 2 > /dev/null 2>&1
```

### Asterisk Integration

Add to your Asterisk dialplan (`/etc/asterisk/extensions.conf`):

```asterisk
[weather-announcement]
exten => 1234,1,Answer()
exten => 1234,2,Exec(/usr/sbin/saytime.pl -l 77511 -n 1)
exten => 1234,3,Hangup()
```

**Example: Multiple locations**:
```asterisk
[weather-announcement]
; Local weather
exten => 1234,1,Answer()
exten => 1234,2,Exec(/usr/sbin/saytime.pl -l 77511 -n 1)
exten => 1234,3,Hangup()

; Remote weather (different timezone)
exten => 5678,1,Answer()
exten => 5678,2,Exec(/usr/sbin/saytime.pl -l 90210 -n 1)
exten => 5678,3,Hangup()
```

## 🌍 Location Support

### Supported Postal Code Formats

- **United States**: 5-digit ZIP codes (e.g., `77511`, `10001`, `90210`)
- **Canada**: 6-character postal codes (e.g., `M5H2N2`, `V6B1A1`, `N7L 3R5`)
- **Germany**: 5-digit postal codes (e.g., `10115`, `80331`, `20095`)
- **France**: 5-digit postal codes (e.g., `75001`, `69001`)
- **United Kingdom**: Postal codes (e.g., `SW1A1AA`, `EC1A1BB`)
- **ICAO Codes**: 4-letter airport codes (e.g., `KJFK`, `EGLL`, `CYYZ`, `LFPG`)
- **And many more!** - Works with most international postal codes

### Special Remote Locations (50+)

**NEW in v2.7.4**: Support for remote locations without postal codes!

Perfect for DXpeditions, research stations, and extreme locations:

**Antarctica** (13 stations): `SOUTHPOLE`, `MCMURDO`, `PALMER`, `VOSTOK`, `CASEY`, `MAWSON`, `DAVIS`, `SCOTTBASE`, `SYOWA`, `CONCORDIA`, `HALLEY`, `DUMONT`, `SANAE`

**Arctic** (7 locations): `ALERT` (northernmost!), `EUREKA`, `THULE`, `LONGYEARBYEN`, `BARROW`, `RESOLUTE`, `GRISE`

**DXpedition Islands**: `HEARD` (VK0), `BOUVET` (3Y0), `KERGUELEN` (FT5), `CROZET` (FT4), `AMSTERDAM` (FT5), `MACQUARIE` (VK0)

**South Atlantic**: `TRISTAN` (ZD9), `ASCENSION` (ZD8), `STHELENA` (ZD7), `FALKLANDS` (VP8), `SOUTHGEORGIA` (VP8), `GOUGH` (ZD9)

**Pacific Islands**: `MIDWAY` (KH4), `WAKE` (KH9), `EASTER` (CE0Y), `PITCAIRN` (VP6), `GALAPAGOS` (HC8), `MARQUESAS` (FO), `CLIPPERTON`, and more

**Examples:**
```bash
weather.pl ALERT v        # 26°F, -3°C / Clear (Arctic)
weather.pl HEARD v        # 8°F, -13°C / Light Snow Showers
weather.pl BOUVET v       # 26°F, -3°C / Overcast (3Y0)
weather.pl EASTER v       # 62°F, 17°C / Sunny
weather.pl MIDWAY v       # 80°F, 27°C / Partly Cloudy
```

### Timezone Feature

**New in v2.7.0**: Time announcements automatically use the timezone of the weather location!

- Repeater in Houston announcing LA weather? Says LA's time (Pacific), not Houston's (Central)
- Repeater in New York announcing Paris weather? Says Paris's time (CET), not NY's (EST)
- Same location as repeater? Uses local time as expected

**Automatic and free** - no configuration needed!

## 🔧 Troubleshooting

### Common Issues

1. **"Could not get coordinates" errors**:
   - Verify postal code is valid and correctly formatted
   - Check internet connectivity
   - Try with verbose mode: `weather.pl 12345 v`

2. **No sound output**:
   - Verify Asterisk is running: `sudo systemctl status asterisk`
   - Check sound file permissions: `ls -la /usr/share/asterisk/sounds/en/wx/`
   - Test with verbose mode: `saytime.pl -l 12345 -n 1 -v -t`

3. **Weather data not updating**:
   - Check internet connectivity: `ping api.open-meteo.com`
   - Clear cache: `sudo rm -rf /var/cache/weather/*`
   - Test API directly: `curl https://api.open-meteo.com/v1/forecast?latitude=29.56&longitude=-95.16&current_weather=true`

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
- Open-Meteo for providing free weather API (https://open-meteo.com)
- OpenStreetMap Nominatim for free geocoding (https://nominatim.org)

---

**Made with ❤️ for the amateur radio community**
