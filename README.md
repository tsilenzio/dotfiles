# Dotfiles

Personal dotfiles for macOS with multi-profile support.

## Quick Start

```bash
# Fresh install (interactive profile selection)
curl -fsSL https://raw.githubusercontent.com/tsilenzio/dotfiles/main/bootstrap.sh | bash

# Non-interactive with specific profiles
curl -fsSL https://... | bash -s -- --profile core --profile personal
```

Or manually:

```bash
git clone https://github.com/tsilenzio/dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

## What's Included

- **Zsh** configuration with Starship prompt
- **Git** config with delta diffs and GPG signing
- **Homebrew** packages organized by profile
- **macOS** preferences automation
- **Dock** customization
- **Secrets** management with age encryption

## Profiles

Profiles are modular configurations that can be combined:

| Profile | Description | Notes |
|---------|-------------|-------|
| `core` | Essential tools (zsh, git, CLI utilities) | Always included |
| `personal` | Gaming, entertainment apps | |
| `work` | Office communication, productivity | |
| `test` | Minimal packages for VM testing | Standalone |

**Example combinations:**
- Home machine: `core + personal`
- Work machine: `core + work`
- Development: `core + personal + work`

## Commands

This repo uses [just](https://github.com/casey/just) for common tasks:

```bash
just                  # Show available commands
just install          # Run full installation
just upgrade          # Re-apply profiles (packages + symlinks)
just update           # Pull latest changes (creates rollback point)
just history          # Show available rollback points
just rollback [id]    # Rollback to previous state
just secrets ...      # Secrets management (init, encrypt, decrypt)
```

## Structure

```
~/.dotfiles/
├── config/                    # Base configurations
│   ├── git/
│   ├── starship/
│   ├── wezterm/
│   └── zsh/
├── platforms/
│   └── macos/
│       ├── profiles/          # Profile-specific setup
│       │   ├── core/
│       │   │   ├── Brewfile
│       │   │   ├── profile.conf
│       │   │   └── setup.sh
│       │   ├── personal/
│       │   ├── work/
│       │   └── test/
│       ├── install.sh
│       ├── preferences.sh
│       └── dock.sh
├── scripts/
│   ├── upgrade.sh
│   ├── update.sh
│   ├── rollback.sh
│   └── secrets.sh
├── secrets/                   # Encrypted secrets (age)
├── bootstrap.sh
└── install.sh
```

## Adding a Profile

1. Create a new directory under `platforms/macos/profiles/`:

```bash
mkdir -p platforms/macos/profiles/myprofile
```

2. Add `profile.conf`:

```bash
name="My Profile"
description="Description of this profile"
order=30
```

3. Add `Brewfile` with packages:

```ruby
brew "some-package"
cask "some-app"
```

4. Add `setup.sh`:

```bash
#!/usr/bin/env bash
MODE="${1:-install}"
echo "Running myprofile setup ($MODE)..."

# Install Brewfile
if [[ -f "$PROFILE_DIR/Brewfile" ]]; then
    brew bundle --file="$PROFILE_DIR/Brewfile"
fi

# Add custom setup here
```

5. Make it executable:

```bash
chmod +x platforms/macos/profiles/myprofile/setup.sh
```

The profile will automatically appear in the selection menu.

## Requirements

- macOS 15+ (Sequoia)
- Internet connection (for Homebrew)

## Documentation

- [Secrets Management](docs/secrets-management.md) - SSH/GPG key encryption
- [Custom App Icons](docs/custom-app-icons.md) - Replace app icons
- [GPG Extended Cache](docs/gpg-extended-cache.md) - Workaround for pinentry-touchid
