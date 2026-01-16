# Dotfiles

Personal dotfiles for macOS.

## What's Included

- **Zsh** configuration with Starship prompt
- **Git** config with delta diffs
- **Homebrew** packages and casks (Brewfile)
- **macOS** preferences automation
- **Dock** customization script

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/tsilenzio/dotfiles/main/bootstrap.sh | bash
```

Or manually:

```bash
git clone https://github.com/tsilenzio/dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

## Structure

```
~/.dotfiles/
├── config/
│   ├── git/
│   ├── starship/
│   ├── wezterm/
│   └── zsh/
├── platforms/
│   └── macos/
│       ├── Brewfile
│       ├── Brewfile.personal
│       ├── Brewfile.work
│       ├── install.sh
│       ├── preferences.sh
│       └── dock.sh
├── bootstrap.sh
└── install.sh
```

## Requirements

- macOS 26.x (Tahoe)
- Internet connection (for Homebrew)
