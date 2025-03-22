# Installation directories
INSTALL_DIR = /usr/local/sbin
SOUNDS_DIR = /usr/share/asterisk/sounds/en
WX_SOUNDS_DIR = $(SOUNDS_DIR)/wx

# Source files
SCRIPTS = saytime.pl weather.pl
TIME_SOUNDS = a-m.ulaw p-m.ulaw
WX_SOUNDS = $(wildcard sounds/*.ulaw)
WX_SOUNDS := $(filter-out sounds/a-m.ulaw sounds/p-m.ulaw, $(WX_SOUNDS))

# Default target
all: install

# Check dependencies
check-deps:
	@echo "Checking dependencies..."
	@if ! command -v plocate >/dev/null 2>&1; then \
		echo "Error: plocate is not installed. Please install it first."; \
		echo "You can install it with: sudo apt-get install plocate"; \
		exit 1; \
	fi
	@if ! command -v asterisk >/dev/null 2>&1; then \
		echo "Error: asterisk is not installed. Please install it first."; \
		echo "You can install it with: sudo apt-get install asterisk"; \
		exit 1; \
	fi
	@echo "Dependencies check passed."

# Install scripts
install: check-deps $(SCRIPTS)
	@echo "Installing scripts to $(INSTALL_DIR)..."
	@for script in $(SCRIPTS); do \
		install -m 755 $$script $(INSTALL_DIR)/; \
		chown root:asterisk $(INSTALL_DIR)/$$script; \
	done
	@echo "Script installation complete."
	@echo ""
	@echo "=== Post Installation Instructions ==="
	@echo "To setup automatic time announcements, add the following to root's crontab:"
	@echo "Run: sudo crontab -e"
	@echo "Add the line (modify time/zip/node as needed):"
	@echo "00 07-23 * * * (/usr/bin/nice -19 /usr/local/sbin/saytime.pl 77511 546054 > /dev/null)"
	@echo "Update the zip code and node number for your installation
	@echo "This will announce time hourly from 7AM to 11PM"
	@echo "=====================================\n"

# Install sound files
install-sounds: check-deps
	@echo "Installing sound files..."
	@mkdir -p $(WX_SOUNDS_DIR)
	@for sound in $(TIME_SOUNDS); do \
		install -m 644 sounds/$$sound $(SOUNDS_DIR)/; \
		chown asterisk:asterisk $(SOUNDS_DIR)/$$sound; \
	done
	@for sound in $(WX_SOUNDS); do \
		install -m 644 $$sound $(WX_SOUNDS_DIR)/; \
		chown asterisk:asterisk $(WX_SOUNDS_DIR)/$$(basename $$sound); \
	done
	@echo "Sound files installation complete."
	@if [ -x /usr/bin/updatedb ]; then \
		echo "Updating locate database..."; \
		sudo /usr/bin/updatedb; \
		echo "Locate database updated."; \
	fi

# Uninstall scripts
uninstall:
	@echo "Removing scripts from $(INSTALL_DIR)..."
	@for script in $(SCRIPTS); do \
		rm -f $(INSTALL_DIR)/$$script; \
	done
	@echo "Script uninstallation complete."

# Uninstall sound files
uninstall-sounds:
	@echo "Removing sound files..."
	@for sound in $(TIME_SOUNDS); do \
		rm -f $(SOUNDS_DIR)/$$sound; \
	done
	@rm -rf $(WX_SOUNDS_DIR)
	@echo "Sound files uninstallation complete."
	@if [ -x /usr/bin/updatedb ]; then \
		echo "Updating locate database..."; \
		sudo /usr/bin/updatedb; \
		echo "Locate database updated."; \
	fi

# Full installation
install-all: install install-sounds

# Full uninstallation
uninstall-all: uninstall uninstall-sounds

.PHONY: all check-deps install install-sounds uninstall uninstall-sounds install-all uninstall-all 