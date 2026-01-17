# Development Utilities

Internal tools for testing the dotfiles installation in VMs or fresh systems.

These utilities are hidden from `just --list` to avoid cluttering the normal user experience.

## Quick Start (Fresh System)

On a fresh system without `just` installed:

```bash
source .dev/init.sh   # Extracts just binary, adds to PATH
just dev setup        # Install CLT + Homebrew from cache
just dev bootstrap    # Run bootstrap in test mode
```

## Remote Installation

```bash
# Interactive (prompts for profile selection via /dev/tty)
curl -fsSL https://raw.githubusercontent.com/tsilenzio/dotfiles/main/bootstrap.sh | bash

# Non-interactive with specific profiles
curl -fsSL https://... | bash -s -- --profile core --profile personal

# Test mode (shows test profile option)
curl -fsSL https://... | bash -s -- --test
```

### Testing curl|bash Locally

To test the piped install behavior:

```bash
# Mimics: curl ... | bash
cat bootstrap.sh | bash

# Mimics: curl ... | bash -s -- --profile core --profile work
cat bootstrap.sh | bash -s -- --profile core --profile work

# Mimics: curl ... | bash -s -- --test
cat bootstrap.sh | bash -s -- --test
```

This triggers the "running from curl pipe" code path rather than the local copy path. Useful for testing that `/dev/tty` prompts work correctly when stdin is a pipe.

**What happens:**
- If git + CLT are installed → clones from GitHub
- If no git (fresh Mac) → downloads tarball from GitHub via curl

**Note:** Both paths require network access to GitHub. The tarball fallback means `curl|bash` works on completely fresh Macs without triggering the CLT install dialog.

## Usage

```bash
just dev              # Show available dev commands
just dev setup        # Install CLT + Homebrew from cached installers
just dev prefetch     # Pre-fetch packages (see profiles below)
just dev bootstrap    # Run bootstrap.sh with --test (unlocks test profile)
just dev install      # Run install.sh with --test (unlocks test profile)
```

### Prefetch Profiles

```bash
just dev prefetch              # test only (default, minimal)
just dev prefetch core         # Core profile packages
just dev prefetch work         # Core + work packages
just dev prefetch personal     # Core + personal packages
just dev prefetch all          # All profiles
```

The `--test` flag adds a "Test" profile option (minimal packages, standalone) for quick VM testing.

## Testing Workflow

### 1. Prepare Cache (on your main machine)

Download offline installers to `.cache/`:
- **just binary** (optional) from [just Releases](https://github.com/casey/just/releases) (`just-*-aarch64-apple-darwin.tar.gz`) - auto-downloads if not cached
- **Command Line Tools DMG** from [Apple Developer](https://developer.apple.com/download/more/)
- **Homebrew PKG** from [Homebrew Releases](https://github.com/Homebrew/brew/releases)

Then pre-fetch Homebrew packages:
```bash
just dev prefetch
```

This downloads packages from the test profile's Brewfile to `.cache/homebrew/`.

### 2. Copy to VM

Copy the entire dotfiles directory (including `.cache/`) to your test VM.

### 3. Run Setup (in VM)

```bash
source .dev/init.sh  # Makes 'just' available (extracts from cache)
just dev setup       # Installs CLT and Homebrew from cache (offline)
just dev bootstrap   # Runs bootstrap (needs network for formula metadata, uses cache for bottles)
```

## Profile System

Profiles are located in `platforms/macos/profiles/`:

```
profiles/
├── core/           # Essential tools (required)
│   ├── Brewfile
│   ├── profile.conf
│   └── setup.sh
├── personal/       # Gaming, entertainment
├── work/           # Office, communication
└── test/           # Minimal VM testing (standalone)
```

Each profile has:
- `profile.conf` - Metadata (name, description, order, required, standalone)
- `Brewfile` - Homebrew packages
- `setup.sh` - Setup script (receives `install` or `upgrade` as $1)

### profile.conf Options

```bash
name="Display Name"
description="What this profile includes"
order=10              # Lower = earlier in list and execution order
required=true         # Always included (only for core)
standalone=true       # Runs alone, skips other profiles (only for test)
enabled=false         # Hide from menu and skip during upgrades (default: true)
```

## Why This Exists

Testing dotfiles on fresh macOS installs is slow because:
- Xcode Command Line Tools download takes 10-20 minutes
- Homebrew package downloads add more time
- Each VM snapshot reset means re-downloading everything

With cached installers and pre-fetched packages, a full test run takes under 2 minutes.

## Network Requirements

The cache contains **bottles** (pre-compiled binary packages), not formula metadata. Homebrew still needs network access to:
- Fetch formula definitions from the JSON API (lightweight, ~seconds)
- Verify package availability and dependencies

Once metadata is fetched, cached bottles are used for installation, avoiding the bulk of download time.

## File Structure

```
.dev/
├── README.md      # This file
├── init.sh        # Initialize dev environment (source this first)
├── justfile       # Dev-specific recipes
├── setup.sh       # Installs CLT + Homebrew from .cache/
└── prefetch.sh    # Pre-fetches Homebrew packages

.cache/
├── .gitkeep                            # Documents what goes here
├── just-*-aarch64-apple-darwin.tar.gz  # just binary (not committed)
├── Command_Line_Tools_for_Xcode_*.dmg  # CLT installer (not committed)
├── Homebrew-*.pkg                      # Homebrew installer (not committed)
└── homebrew/                           # Pre-fetched packages (not committed)
```

## Notes

- **Version selection**: If multiple versions exist, the latest is used automatically (sorted by version number).
- **Supported file names**:
  - just: `just-*-aarch64-apple-darwin.tar.gz` or `just-aarch64-apple-darwin.tar.gz`
  - CLT: `Command_Line_Tools_for_Xcode_*.dmg` or `Command_Line_Tools.dmg`
  - Homebrew: `Homebrew-*.pkg` or `Homebrew.pkg`
- **init.sh**: Must be sourced (not executed) so PATH changes persist in your shell. If `just` is already available, it skips extraction. If not cached, it downloads the latest release from GitHub.
- **Sudo handling**: Both `setup.sh` and the install scripts use `preflight.sh` to request permissions upfront and create a temporary passwordless sudo entry. This is automatically cleaned up when each script exits.
