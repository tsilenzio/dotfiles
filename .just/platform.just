# Platform setup module (auto-detects OS)
# Usage: just platform <recipe>

set shell := ["bash", "-cu"]

PLATFORM_SCRIPT := justfile_directory() / "scripts/platform.sh"

# Show platform commands
default:
    @just --list platform

# Show detected platform info
info:
    "{{PLATFORM_SCRIPT}}" info

# Run full platform installation
install:
    "{{PLATFORM_SCRIPT}}" install

# Configure platform settings (--prefs, --dock, or both if neither specified)
configure *args:
    "{{PLATFORM_SCRIPT}}" configure {{args}}

# Create symlinks for config files
link:
    "{{PLATFORM_SCRIPT}}" link
