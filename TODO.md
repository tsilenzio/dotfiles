# TODO

Planned improvements and ideas for the dotfiles system.

## High Priority

- [ ] **gum integration** - Add Charmbracelet's gum for nicer TUI in bundle selection. Can download binary directly for curl|bash scenarios without Homebrew.

- [ ] **brew wrapper** - Create a wrapper script that intercepts `brew install` and prompts to add manually installed packages to a bundle's Brewfile. Helps maintain Brewfile hygiene.

- [ ] **Test installation end-to-end** - Run through full install on a fresh VM to verify bundle structure, dependency resolution, and package installation.

## Medium Priority

- [ ] **Decouple scripts from dotfiles** - Extract `just` commands and scripts (like `srun`) into standalone tools that can be invoked from anywhere without being in the dotfiles directory. Currently `srun` is a shell function; extract to a standalone script in PATH.

- [ ] **Linux support** - Add `platforms/linux/` with bundles. The shared library (common.sh) and bundle system are designed to support this.

- [ ] **Bundle-specific config overrides** - Utilize the `config/` directory within bundles for things like work-specific gitconfig (different email), SSH configs, etc.

- [ ] **Shell completions** - Add zsh completions for `just` commands and custom scripts.

- [ ] **Secrets workflow documentation** - Document the full age/sops secrets workflow: init, encrypt, decrypt, and how to add new secrets.

## Low Priority / Ideas

- [ ] **Dotfiles health check** - A `just doctor` command that verifies symlinks, checks for orphaned packages, validates configs.

- [ ] **CI improvements** - Add GitHub Actions to test install.sh in a macOS VM on PRs.

- [x] **Rollback testing** - Verify the update/rollback system works correctly with bundle changes.

- [ ] **Bundle contents documentation** - Auto-generate docs showing what each bundle installs.

- [ ] **Backup/sync integration** - Integrate rclone/restic for automated config backups.

- [ ] **Employer bundle** - Employer-specific bundle if needed (requires: develop). Currently deferred since differences are minimal.

- [ ] **Office bundle** - Generic office tools bundle (Word, Excel, PowerPoint). Currently split between personal (documents) and work (communication).

## Completed

- [x] Add `--reveal` flag for showing hidden bundles in menu
- [x] Add `just dev lint` recipe (shellcheck + zsh syntax)
- [x] Support both `--option value` and `--option=value` formats
- [x] Add bootstrap curl mode to emulate curl|bash behavior
- [x] Move bundle helper functions to shared library (common.sh)
- [x] Create develop bundle for dev tools, IDEs, containers
- [x] Reorganize Brewfiles (core, develop, personal, work)
- [x] Update documentation with new bundle structure
- [x] Add `--select` flag for additive bundle selection
- [x] Add `--remove` flag for removing bundles
- [x] Add `--yes`/`--no` flags for preferences/dock prompts
- [x] Add rollback snapshot on bundle changes
- [x] Fix rollback to find all tag prefixes (pre-update, pre-bundle-change, pre-change)
- [x] Fix GPG signing hang in create_snapshot (--no-sign flag)
- [x] Add upfront sudo prompt for brew rollback
- [x] Add shell restart prompt after brew package changes
- [x] Fix install.sh tee redirect corrupting new shell (restore fd before exec)
- [x] Add `just` and GPG packages to core bundle
- [x] Add zprofile for non-interactive login shells
- [x] Document shell state coverage (zshrc/zshenv/zprofile)
