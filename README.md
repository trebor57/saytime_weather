# Saytime Weather

A comprehensive time and weather announcement system for Asterisk PBX, designed specifically for radio systems, repeater controllers, and amateur radio applications. This system provides automated voice announcements of current time and weather conditions using high-quality synthesized speech.

**Version 2.7.2** - Critical temperature bug fix for Celsius/Canadian users + complete Weather Underground cleanup!

## 🚀 Features

- **Time Announcements**: Support for both 12-hour and 24-hour time formats
- **Location-Aware Timezone**: Time automatically matches weather location timezone
- **Worldwide Weather**: Real-time weather from any postal code globally via Open-Meteo
- **No API Keys Required**: Fully functional out of the box - zero configuration!
- **Global Postal Codes**: US ZIP codes, Canadian postal codes, European codes, and more
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
   wget https://github.com/hardenedpenguin/saytime_weather/releases/download/v2.7.2/saytime-weather_2.7.2_all.deb
   ```

2. **Install the package**:
   ```bash
   sudo apt install ./saytime-weather_2.7.2_all.deb
   ```

   This will automatically:
   - Install all required dependencies
   - Set up the system directories
   - Install sound files
   - Create configuration with sensible defaults
   - **No API keys needed** - works immediately!

### Option 2: Manual Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/hardenedpenguin/saytime_weather.git
   cd saytime_weather
   ```

2. **Install dependencies**:
   ```bash
   sudo apt update
   sudo apt install asterisk perl \
       libdatetime-perl libdatetime-timezone-perl \
       libwww-perl libcache-cache-perl libjson-perl \
       libconfig-simple-perl liblog-log4perl-perl
   ```

3. **Install the scripts**:
   ```bash
   sudo make install
   ```

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

### What Changed in v2.7.2?

**New in 2.7.2:**
- 🐛 **CRITICAL FIX: Temperature bug** - Fixed double-conversion for Celsius/Canadian users
- 🧹 **Removed Weather Underground** - Cleaned all remaining references from codebase
- ⚙️ **Updated configuration** - Removed obsolete API keys, added `weather_provider`
- 📝 **Updated help text** - Now reflects actual configuration options

### What Changed in v2.7.1?

**New in 2.7.1:**
- ✅ **Fixed timezone feature** - Time now correctly matches weather location
- ✅ **Added default_country config** - Set your country for postal code lookups
- ✅ **Antarctic station codes** - SOUTHPOLE, MCMURDO, PALMER, VOSTOK support
- ✅ **Improved US ZIP priority** - Prevents wrong country matches

### What Changed in v2.7.0?

**Removed (No Longer Needed):**
- ❌ `wunderground_api_key` - Weather Underground API removed
- ❌ `timezone_api_key` - TimeZoneDB API removed
- ❌ `geocode_api_key` - OpenCage API removed
- ❌ `aerodatabox_rapidapi_key` - AeroDataBox API removed
- ❌ `use_accuweather` - AccuWeather RSS discontinued by AccuWeather

**Now Uses (Free APIs, No Keys):**
- ✅ **Open-Meteo** - Weather data + timezone (https://open-meteo.com)
- ✅ **Nominatim** - Postal code geocoding (https://nominatim.org)

**Zero API keys required!** Just install and use.

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
- **And many more!** - Works with most international postal codes

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

## ✨ What's New in Version 2.7.2

### Critical Bug Fix (HIGH PRIORITY)
- 🐛 **CRITICAL: Fixed temperature conversion bug for Celsius users**
  - Temperature was being double-converted causing wildly incorrect readings
  - **Example**: 5°C actual temperature would incorrectly show as -15°C
  - **Problem**: API was requested in Celsius mode, then incorrectly converted from Fahrenheit
  - **Impact**: All Canadian and Celsius users had wrong temperatures
  - **Solution**: Always request Fahrenheit from API, convert to Celsius only when needed
  - **Status**: Tested and verified with Ottawa, Toronto, Vancouver ✅

### Code Cleanup
- 🧹 **Removed all Weather Underground references**
  - Cleaned remaining reference in help text
  - Removed from postinst installation script
  - Deleted stale build artifacts with old code
- ⚙️ **Updated configuration to match current code**
  - Replaced obsolete `use_accuweather` with `weather_provider=openmeteo`
  - Removed unused `timezone_api_key` (no longer needed)
  - Removed unused `geocode_api_key` (no longer needed)
  - Added `default_country` for postal code disambiguation
- 📝 **Updated help text** - Now accurately reflects actual configuration options

### Why This Update Matters
If you're using Celsius mode (`Temperature_mode = C`) or are in Canada, **you must update immediately**. The previous version was showing completely incorrect temperatures due to a double-conversion bug.

## ✨ What's New in Version 2.7.1

### Bug Fixes & Improvements
- 🐛 **Fixed timezone return bug** - DateTime object now properly returned from function
- 🐛 **Fixed timezone caching** - Timezone now saved/restored from cache correctly
- 🐛 **Fixed execution order** - Weather processed before time to ensure timezone file exists
- ⚙️ **Added default_country config** - Prevents wrong country matches for 5-digit codes
- 🇦🇶 **Added Antarctic stations** - SOUTHPOLE, MCMURDO, PALMER, VOSTOK location codes
- 🇺🇸 **Improved US ZIP priority** - US postal codes checked first, fallback to international

### Timezone Feature Now Fully Working
- Time announcements now correctly use weather location timezone
- Server in Central Time + LA weather = Announces Pacific Time ✅
- Server in Central Time + NY weather = Announces Eastern Time ✅
- Tested and verified with multiple timezone differences

## ✨ What's New in Version 2.7.0

### Major Changes

- 🚨 **CRITICAL**: Replaced discontinued AccuWeather RSS with Open-Meteo API
- ✅ **No API Keys Required**: Removed all 4 API key dependencies
- 🌍 **Worldwide Support**: Works with any postal code globally (US, Canada, Europe, etc.)
- ⏰ **Location-Aware Time**: Time announcements now match weather location timezone
- 🧹 **Simplified**: Reduced code by 319 lines (23% reduction)
- 🔇 **Quiet by Default**: Clean output, verbose mode available with `-v`
- 🇨🇦 **Canadian Support**: Added FSA mapping for Canadian postal codes
- 🚀 **Zero Configuration**: Works out of the box with sensible defaults

### APIs Removed (No Longer Needed)
- ❌ AccuWeather RSS (discontinued by AccuWeather - HTTP 410)
- ❌ Weather Underground API (required API key)
- ❌ TimeZoneDB API (required API key)
- ❌ OpenCage Geocoding API (required API key)
- ❌ AeroDataBox API (required API key)

### APIs Added (Both Free, No Keys)
- ✅ **Open-Meteo** - Weather data + automatic timezone detection
- ✅ **Nominatim/OpenStreetMap** - Worldwide postal code geocoding

### Code Improvements
- Reduced from 1,363 to 1,044 lines (23% reduction)
- saytime.pl: 645 → 460 lines (29% reduction)
- weather.pl: 718 → 685 lines (5% reduction)
- Configuration: 10 → 4 fields (60% reduction)
- Dependencies: Removed 2 unused Perl modules

### Tested Locations
- 🇺🇸 US: 77511 (Houston), 10001 (New York), 90210 (Beverly Hills)
- 🇨🇦 Canada: M5H2N2 (Toronto), V6B1A1 (Vancouver), N7L3R5 (Ontario)
- 🇫🇷 France: 75001 (Paris)
- 🇩🇪 Germany: 10115 (Berlin), 80331 (Munich), 20095 (Hamburg)

## 🙏 Acknowledgments

- Original concept and development by D. Crompton, WA3DSP
- Weather API integrations and improvements by the community
- Sound file contributions from various amateur radio operators
- Open-Meteo for providing free weather API (https://open-meteo.com)
- OpenStreetMap Nominatim for free geocoding (https://nominatim.org)

---

**Made with ❤️ for the amateur radio community**

