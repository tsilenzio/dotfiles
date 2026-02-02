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
# Interactive (prompts for bundle selection via /dev/tty)
curl -fsSL https://raw.githubusercontent.com/tsilenzio/dotfiles/main/bootstrap.sh | bash

# Non-interactive with specific bundles
curl -fsSL https://... | bash -s -- --select core --select personal

# Reveal hidden test bundle in menu
curl -fsSL https://... | bash -s -- --reveal test
```

### Testing curl|bash Locally

To test the piped install behavior:

```bash
# Mimics: curl ... | bash
cat bootstrap.sh | bash

# Mimics: curl ... | bash -s -- --select core --select work
cat bootstrap.sh | bash -s -- --select core --select work

# Mimics: curl ... | bash -s -- --reveal test
cat bootstrap.sh | bash -s -- --reveal test
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
just dev prefetch     # Pre-fetch packages (see bundles below)
just dev bootstrap    # Run bootstrap.sh with --reveal test (shows test bundle)
just dev bootstrap curl  # Emulate curl|bash behavior
just dev install      # Run install.sh with --reveal test (shows test bundle)
just dev lint         # Run shellcheck + zsh syntax checks
```

### Prefetch Bundles

```bash
just dev prefetch              # test only (default, minimal)
just dev prefetch core         # Core bundle packages
just dev prefetch develop      # Core + develop packages
just dev prefetch work         # Core + work packages
just dev prefetch personal     # Core + personal packages
just dev prefetch all          # All bundles
```

The `--reveal test` flag shows the hidden "Test" bundle in the menu for quick VM testing.

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

This downloads packages from the test bundle's Brewfile to `.cache/homebrew/`.

### 2. Copy to VM

Copy the entire dotfiles directory (including `.cache/`) to your test VM.

### 3. Run Setup (in VM)

```bash
source .dev/init.sh  # Makes 'just' available (extracts from cache)
just dev setup       # Installs CLT and Homebrew from cache (offline)
just dev bootstrap   # Runs bootstrap (needs network for formula metadata, uses cache for bottles)
```

## Bundle System

Bundles are located in `platforms/macos/bundles/`:

```
bundles/
├── core/           # Essential tools (no dependencies)
│   ├── Brewfile
│   ├── bundle.conf
│   └── setup.sh
├── develop/        # Development tools, IDEs (requires core)
├── personal/       # Gaming, entertainment (requires core)
├── work/           # Office, communication (requires core)
└── test/           # Minimal VM testing (hidden, no dependencies)
```

Each bundle has:
- `bundle.conf` - Metadata (name, description, order, requires)
- `Brewfile` - Homebrew packages
- `setup.sh` - Setup script (receives `install` or `upgrade` as $1)

### bundle.conf Options

```bash
name="Display Name"
description="What this bundle includes"
order=10              # Lower = earlier in list and execution order
requires="core"       # Comma-separated dependencies (resolved automatically)
hidden=true           # Hide from menu, use --reveal <name> to show (default: false)
enabled=false         # Disable entirely, skip during upgrades (default: true)
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
├── justfile       # Dev-specific recipes (thin wrappers)
└── scripts/
    ├── lib/
    │   └── common.sh  # Shared library (logging, paths)
    ├── setup.sh       # Installs CLT + Homebrew from .cache/
    ├── prefetch.sh    # Pre-fetches Homebrew packages
    ├── test.sh        # Test bootstrap (local or curl mode)
    └── lint.sh        # Run shellcheck + zsh syntax checks

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
