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
# Interactive (prompts for profile via /dev/tty)
curl -fsSL https://raw.githubusercontent.com/tsilenzio/dotfiles/main/bootstrap.sh | bash

# Non-interactive (argument)
curl -fsSL https://... | bash -s -- --profile work

# Non-interactive (environment variable)
DOTFILES_PROFILE=work curl -fsSL https://... | bash
```

### Testing curl|bash Locally

To test the piped install behavior:

```bash
# Mimics: curl ... | bash
cat bootstrap.sh | bash

# Mimics: curl ... | bash -s -- --profile work
cat bootstrap.sh | bash -s -- --profile work

# Mimics: curl ... | bash -s -- --profile test ~/custom/path
cat bootstrap.sh | bash -s -- --profile test ~/custom/path
```

This triggers the "running from curl pipe" code path rather than the local copy path. Useful for testing that `/dev/tty` prompts work correctly when stdin is a pipe.

**What happens:**
- If git + CLT are installed → clones from GitHub
- If no git (fresh Mac) → downloads tarball from GitHub via curl

**Note:** Both paths require network access to GitHub. The tarball fallback means `curl|bash` works on completely fresh Macs without triggering the CLT install dialog. The tarball has no `.git` directory, so updates require re-running bootstrap.

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
just dev prefetch base         # Brewfile only
just dev prefetch work         # Brewfile + Brewfile.work
just dev prefetch personal     # Brewfile + Brewfile.personal
just dev prefetch work personal # Brewfile + both profiles
just dev prefetch all          # All available Brewfiles
```

The `--test` flag adds a third "Test" profile option (minimal packages) while still allowing you to select Personal or Work profiles for testing.

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

This downloads all packages from `Brewfile.test` to `.cache/homebrew/`.

### 2. Copy to VM

Copy the entire dotfiles directory (including `.cache/`) to your test VM.

### 3. Run Setup (in VM)

```bash
source .dev/init.sh  # Makes 'just' available (extracts from cache)
just dev setup       # Installs CLT and Homebrew from cache (offline)
just dev bootstrap   # Runs bootstrap (needs network for formula metadata, uses cache for bottles)
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

Once metadata is fetched, cached bottles are used for installation, avoiding the bulk of download time. True offline operation would require tapping homebrew/core (~1.2GB), which defeats the purpose of fast testing.

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
  - Versioned names are preferred over non-versioned if both exist.
- **init.sh**: Must be sourced (not executed) so PATH changes persist in your shell. If `just` is already available, it skips extraction. If not cached, it downloads the latest release from GitHub.
- **Sudo handling**: Both `setup.sh` and the install scripts use `preflight.sh` to request permissions upfront and create a temporary passwordless sudo entry. This is automatically cleaned up when each script exits (even on Ctrl+C or errors).
