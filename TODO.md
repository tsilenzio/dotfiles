# TODO

Planned improvements and ideas for the dotfiles system.

## High Priority

- [x] **gum integration** - Auto-download and cache Charmbracelet's gum for interactive TUI menus. `ensure_gum` in common.sh with GitHub release helpers in `scripts/lib/github.sh`. Used in spotlight picker with plain fallback.

- [ ] **brew wrapper** - Create a wrapper script that intercepts `brew install` and prompts to add manually installed packages to a bundle's Brewfile. Helps maintain Brewfile hygiene.

- [ ] **Test installation end-to-end** - Run through full install on a fresh VM to verify bundle structure, dependency resolution, and package installation.

- [x] **Global dotfiles command (`rune`)** - Run dotfiles commands from anywhere without `cd ~/.dotfiles` first. Implemented as a shell function wrapping `just`.

- [ ] **`runectl` + shell wrapper architecture** - Split the CLI into `runectl` (backing implementation) and `rune()` (thin shell function wrapper). Enables shell-level operations a binary can't do (source, exec, env export) while keeping the implementation portable across shells and rewrite targets.

  **Architecture:**
  - `runectl` — the actual implementation. Today: shell script wrapping `just`. Later: Rust/Deno binary. Available in all shell states via PATH (set in zshenv). Handles all real work including secrets decryption.
  - `rune()` — permanent thin shell function (~10 lines). Calls `runectl`, then handles shell-level post-actions (source changed configs, exec for full restart, export env vars). Only exists in interactive shells (via zshrc/bashrc/config.fish).

  **Shell reload mechanism:**
  - `runectl` (via update/upgrade) creates `.state/needs-reload` when shell configs change
  - File contains either specific file paths to re-source, or `exec` for a full shell restart
  - `rune()` reads the flag after `runectl` returns, sources listed files or runs `exec $SHELL`
  - Targeted sourcing avoids PATH duplication — only dotfiles-managed files (functions, aliases) are re-evaluated, never the PATH/tool-init lines
  - update detects changed files via `git diff --name-only` against `config/zsh/`; upgrade knows what it re-linked
  - No dependency on `typeset -U path` or full zshrc re-sourcing

  **Conflict detection (auto-naming):**
  - `runectl init <shell>` checks `command -v rune` (finds only binaries, not functions)
  - No conflict → generates `rune()` wrapper
  - Conflict found (e.g., Rune language CLI) → generates `runectl()` wrapper, emits a note
  - Override with `--name <name>`: `runectl init zsh --name rn` for custom name
  - Custom name persisted in `.dotfiles.toml` so subsequent `runectl init` uses it automatically

  **Non-interactive shim:**
  - `runectl shim --name rn --path ~/.local/bin` creates a symlink for non-interactive contexts
  - Interactive: `rn` is the shell function (from init)
  - Non-interactive: `rn` is a symlink to `runectl` on PATH
  - Rust/Deno binary can use argv[0] detection (busybox pattern) for zero-cost aliasing

  **Multi-shell support (like starship/oh-my-posh):**
  ```bash
  eval "$(runectl init zsh)"                    # zsh
  eval "$(runectl init bash)"                   # bash
  runectl init fish | source                    # fish
  eval (runectl init elvish | slurp)            # elvish
  runectl init nu | source                      # nushell
  ```
  - Each shell gets the wrapper function in its native syntax
  - Only Unix shells — no Windows/PowerShell support needed
  - The binary generates shell-specific code; the wrapper stays ~10 lines per shell

  **All four shell states supported:**
  | State | `runectl` (binary) | `rune()` (function) |
  |-------|-------------------|-------------------|
  | Interactive login | via PATH (zshenv) | via zshrc |
  | Interactive non-login | via PATH (zshenv) | via zshrc |
  | Non-interactive login | via PATH (zshenv) | not needed |
  | Non-interactive non-login | via PATH (zshenv) | not needed |

  **Non-interactive secrets (why all states matter):**
  - `runectl` detects its context: `[[ -t 0 ]]` → has terminal → can prompt
  - Interactive: prompt / Touch ID / Keychain
  - Non-interactive (cron, CI, scripts, SSH commands): Keychain with pre-authorized ACL, gpg-agent/ssh-agent cache from prior interactive session
  - No human present → skip Touch ID, skip prompts, fail gracefully (not hang)
  - Critical for: automated secret decryption, scheduled backups, CI pipelines

  **Implementation phases:**
  1. **Now (shell scripts):** Rename backing to `runectl` shell script, thin `rune()` wrapper with reload mechanism, conflict detection as a comment
  2. **Rust rewrite:** `runectl` becomes compiled Rust binary (clap + inquire + ratatui), gains `init`/`shim` subcommands, multi-shell support, context-aware secrets auth.
- [x] **Spotlight volume management** - UUID-based local config for multi-boot macOS Spotlight indexing control. Each macOS installation independently manages shared volumes via `platforms/macos/daemons/spotlight` with LaunchDaemon (`RunAtLoad` + `WatchPaths` on `/Volumes`), boot volume detection via device ID comparison, gum/plain interactive picker, and automatic boot volume safety net. Managed via `rune daemons` TUI or `rune daemons spotlight` CLI.

- [ ] **Spotlight dependency hygiene** - `mdfind` sweep during `rune upgrade` to drop `.metadata_never_index` into dependency directories (`node_modules`, `.venv`, `target/`, `build/`, `.gradle/`, `__pycache__`). Static `.metadata_never_index` for `/opt/homebrew`. No FSEvents watcher — the sweep during upgrade is sufficient.

- [ ] **Dotfiles health check** - A self-healing `rune doctor` command (like `brew doctor`) that diagnoses AND auto-fixes common issues. Should detect problems, explain what's wrong, and offer to fix them automatically.

  **Checks and auto-fixes:**
  - Broken symlinks → re-link or remove orphans
  - Missing Homebrew packages (in Brewfile but not installed) → offer `brew bundle install`
  - Orphaned packages (installed but not in any Brewfile) → warn, offer removal
  - Stale `.state/loaded/` symlinks for uninstalled bundles → clean up
  - Missing git upstream tracking → set automatically (like the fix from PR #19)
  - Invalid `.bundles` file (references non-existent bundles) → warn, offer correction
  - Secrets health: age key missing, cloud backup stale, Keychain entries missing → offer restore
  - Permissions issues on scripts (not executable) → chmod +x

  **Behavior:**
  - Default: diagnose and prompt `Fix? [Y/n]` per issue (like `brew` auto-fix)
  - `--fix`: auto-fix all without prompting
  - `--dry-run`: diagnose only, no changes
  - Exit code reflects health: 0 = healthy, 1 = issues found (for CI/scripting)

## Medium Priority

- [ ] **Global git hooks with trusted repos** - Set up global git hooks that optionally run repo-specific hooks only for trusted repos.

  **Design:**
  - Set `core.hooksPath = ~/.config/git/hooks` globally
  - Global hooks always run, then check if repo is trusted before running repo hooks
  - Trust is determined by a `.trusted` file in repo root containing a secret UUID
  - The secret is stored in `~/.config/git/trust-secret` (synced via encrypted secrets)
  - `.trusted` is added to global gitignore so it's never committed

  **Security rationale:**
  - Can't just check for `.trusted` existence - malicious repos could include it
  - The file must contain YOUR specific UUID to be trusted
  - UUID is generated once with `uuidgen` (works on macOS + Linux)
  - Stored in encrypted secrets, so `rune secrets restore` gives same trust on any machine/OS

  **Implementation:**
  ```bash
  # ~/.config/git/hooks/pre-commit (and other hooks)
  HOOK_NAME="$(basename "$0")"
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

  TRUST_SECRET="$(cat ~/.config/git/trust-secret 2>/dev/null)"
  REPO_SECRET="$(cat "$REPO_ROOT/.trusted" 2>/dev/null)"

  if [[ -n "$TRUST_SECRET" && "$REPO_SECRET" == "$TRUST_SECRET" ]]; then
      # Check repo's local hooksPath, fallback to .git/hooks
      repo_hooks_path=$(git config --local core.hooksPath 2>/dev/null)
      if [[ -n "$repo_hooks_path" ]]; then
          repo_hook="$REPO_ROOT/$repo_hooks_path/$HOOK_NAME"
      else
          repo_hook="$(git rev-parse --git-dir)/hooks/$HOOK_NAME"
      fi
      [[ -x "$repo_hook" ]] && exec "$repo_hook" "$@"
  fi
  ```

  **Trust file format (single file, multi-key like authorized_keys):**
  - `.trusted` in repo root: one UUID per line, each from a different installation
  - Supports multiple boot targets sharing a Code volume (e.g., macOS multi-boot)
  - Supports nomad/portable macOS on external drives used across machines
  - Each installation generates its own trust secrets during `secrets init`/`restore`
  - When trusting a repo, the current installation's secret is appended (not replaced)
  - Global hook checks if ANY line matches the current installation's secrets
  - Machine IDs are NOT used — they're shared across boot targets and would be exploitable if an attacker learns the format. Per-installation random UUIDs are safer.

  ```
  # .trusted - one UUID per line (like ~/.ssh/authorized_keys)
  # UUIDs are opaque — no visible indicator of trust level
  a1b2c3d4-e5f6-7890-abcd-ef1234567890
  f9e8d7c6-b5a4-3210-fedc-ba0987654321
  ```

  **Trust levels (two-secret approach — tamper-resistant):**
  - Each installation has TWO secrets (both mode 600, outside any repo):
    - `~/.config/git/trust-secret` — regular trust UUID
    - `~/.config/git/always-trust-secret` — always-trust UUID (different value)
  - `git trust` appends `trust-secret` to `.trusted`
  - `git trust --always` appends `always-trust-secret` to `.trusted`
  - The global hook determines trust level by WHICH secret matches, not a label
  - **trusted** (matches `trust-secret`): Repo hooks run, but trust is revoked if hooks change via `git pull`/`fetch`/`merge` (post-merge hook detects changed hook files and removes this installation's line from `.trusted`). User is notified and must re-trust.
  - **always-trust** (matches `always-trust-secret`): For repos you fully control (your own dotfiles, trusted org repos). Hook changes don't revoke trust.

  **Why this is tamper-resistant:**
  - UUIDs in `.trusted` are opaque — an attacker can't tell which is regular vs always-trust
  - A malicious repo script can see UUIDs in `.trusted` but can't escalate: it doesn't know the always-trust UUID
  - There's no label or flag to flip — trust level is implicit in which UUID is present

  **Known attack surface and mitigations:**
  - **Secret file exfiltration**: A malicious hook running at regular trust level could read `~/.config/git/always-trust-secret` (runs as user, so 600 perms don't help). Mitigation: store the always-trust secret in macOS Keychain with ACL restricted to `git-trust` binary — random scripts can't access it without a Keychain prompt. Falls back to file-based on Linux.
  - **Cross-repo trust injection**: Attacker reads regular UUID from repo A's `.trusted` and writes it into repo B's `.trusted`. Requires write access to other repo directories — low risk, bigger problems if they have that.
  - **Implementation priority**: The global hook wrapper must verify trust BEFORE executing any repo hooks — this is the critical correctness requirement.

  **Migration for existing installations:**
  - `secrets init`/`restore` and `rune upgrade` should generate trust secrets if they don't exist
  - Global hook gracefully no-ops when secrets are missing (no secrets = no repo hooks run, same as current behavior)
  - Existing repos must be explicitly trusted — no auto-migration to prevent unintended hook execution

  **Discovery of new/existing repos:**
  - Repos that add hooks later (received via `git pull`) should be detected — the post-merge hook can check if the repo has hook files but no `.trusted` file and notify the user
  - For existing repos on disk, a `git-trust-scan` command could walk known project directories and flag repos with hooks that aren't trusted
  - Trust should be opt-in only (no auto-prompting on `cd`) — user explicitly runs `git trust` or `git trust --always` in the repo

  **Files to add:**
  - `config/git/hooks/pre-commit` (and other hook wrappers)
  - `config/git/hooks/post-merge` (trust revocation + new hook discovery)
  - Add `core.hooksPath` to `config/git/gitconfig`
  - Add `.trusted` to `config/git/gitignore`
  - Add two-secret generation to `secrets init`/`restore`
  - Add `git-trust` command: appends `trust-secret` to `.trusted`
  - Add `git-trust --always` variant: appends `always-trust-secret` to `.trusted`
  - Add `git-trust --revoke` to remove current secrets from `.trusted`
  - Add `git-trust-scan` command to discover repos with untrusted hooks

- [ ] **Decouple scripts from dotfiles** - Extract `just` commands and scripts into standalone tools that can be invoked from anywhere without being in the dotfiles directory. Partially addressed by `rune` shell function; fully solved by the `runectl` binary architecture (see High Priority) and Rust/Deno rewrite.

- [ ] **Linux support** - Add `platforms/linux/` with bundles. The shared library (common.sh) and bundle system are designed to support this.

- [ ] **Bundle-specific config overrides** - Utilize the `config/` directory within bundles for context-specific overrides: gitconfig (different email per bundle), SSH configs, environment variables, additional tooling, etc. Bundles that need specialized configuration beyond their Brewfile and setup.sh can layer overrides without affecting other bundles.

- [ ] **Shell completions** - Add zsh completions for `rune` commands and custom scripts.

- [ ] **Secrets workflow documentation** - Document the full age/sops secrets workflow: init, encrypt, decrypt, and how to add new secrets.

## Development

- [x] **Brew lock for safe testing** - `rune dev lock` / `rune dev unlock` to skip Brewfile installations during upgrades while showing what would change. Respects lock during rollback with `--with-brew`.

- [x] **PR/branch preview** - `rune dev preview` for snapshot-backed preview of PRs, branches, and commits with dirty state preservation. Smart detection, auto brew lock, activity tracking with 24h stale warnings.

- [ ] **Expandable dev locks** - Extend `rune dev lock` to support `--prefs`, `--dock`, `--all` to skip preferences, dock, or everything except symlinks/configs during testing.

- [ ] **APFS snapshot integration** - Full-system rollback for test installations (SIP disabled only). Separate repo for dangerous tooling, gated behind `rune dev init` + SIP check.

  **Design:**
  - `tmutil localsnapshot` before changes, mount + `rsync --itemize-changes` to diff, restore changed files programmatically
  - Covers everything: plists, brew artifacts, Keychain, TCC (with SIP disabled)
  - Dangerous tooling lives in a separate repo, cloned by `rune dev init` into `.dev/tools/` (gitignored)
  - Triple gate: flag file (`.state/dev-enabled`) + SIP check (`csrutil status`) + confirmation prompt
  - Snapshots are deleted after successful rollback to avoid disk accumulation
  - No seal/SSV concerns — all changes are on the data volume

  **Preferences rollback (subset, no SIP required):**
  - Snapshot `~/Library/Preferences/` before running preferences/dock
  - Diff plists before/after to log exactly what changed
  - Restore via `defaults import` + service restart (`cfprefsd`, `Dock`, `Finder`, `SystemUIServer`)
  - Classify changes: `[safe]` restorable, `[sudo]` needs elevation, `[blocked]` SIP-protected

- [ ] **Pre-push git hook for CI checks** - Run the same checks GitHub CI runs locally before pushing, catching errors before they require fix-up commits. On failure, prompt with `[y/N]` to push anyway (defaulting to abort).

  **Checks to run locally (matching CI):**
  - ShellCheck (severity: warning)
  - Zsh syntax (`zsh -n`)
  - Conventional commit messages (commitlint)
  - Branch name convention (`<type>/<description>`)
  - Note: PR body format (## Summary, ## Test plan) can only be checked in CI since the PR doesn't exist yet at push time

  **Implementation:**
  - Add `.dev/hooks/pre-push` hook script
  - Hook runs `rune dev lint` + commit message/branch name validation
  - On failure: show errors, prompt `Push anyway? [y/N]` (default: no)
  - Install via `rune dev setup` or document manual `git config core.hooksPath`
  - Note: If the global git hooks system (above) is implemented first, this hook would be installed automatically via the trust mechanism rather than manual setup

## Long Term

- [ ] **Rust rewrite (`runectl`)** - Rewrite `runectl` in Rust using clap + inquire + ratatui. Starts as a dispatch table (Phase 1: clap routes subcommands to existing bash scripts), adds interactive prompts (Phase 2: inquire replaces gum/bash menus), then full-screen TUI (Phase 3: ratatui for bootmenu zones, daemons TUI), then incremental logic migration (Phase 4). No intermediate language step. The `runectl` + shell wrapper architecture (see High Priority) is designed for this — `runectl` becomes the binary, `rune()` shell function stays unchanged. Gains `runectl init <shell>` for multi-shell support, `runectl shim` for non-interactive aliasing, and context-aware secrets auth.

- [ ] **Dotfiles config file** - Add `.dotfiles.toml` for user preferences and feature toggles. Gate features (secrets, cloud backup, GPG keychain import) via config so users can opt out. Built on the Rust rewrite, design the schema to support extension selection.

- [ ] **Extension architecture** - Extensible extension system built on the Rust rewrite. Extensions are standalone executables (any language) communicating via stdin/stdout JSON protocol — same pattern as git, Docker, and Terraform.

  **Design:**
  - Core defines capabilities (secrets, trust, cloud-backup, etc.) as trait interfaces
  - Built-in extensions ship compiled into the binary for performance
  - External extensions are standalone executables discovered by naming convention or an `extensions/` directory
  - Protocol: JSON over stdin/stdout, stderr for user-facing messages
  - Disabled by default — users opt in via `.dotfiles.toml`, zero overhead if unused

  **Protocol:**
  - Every request/response includes a `protocol` version field
  - Semantic versioning: major = breaking, minor = additive
  - Core refuses incompatible extensions with a clear error
  - `capabilities` action for feature negotiation (not all extensions support all actions)
  - `health` action for self-test (used by `dotfiles doctor`)
  - Configurable timeouts per action

  **Staged rollout:**
  1. Rust rewrite with internal trait-based modularity (age secrets, trust, keychain as internal modules)
  2. Design internal traits with the external protocol in mind
  3. Add external executable protocol when third-party demand exists
  4. Ship built-in extensions for current features, users can swap with third-party alternatives

  **Progressive disclosure for users:**
  - Basic users: clone, run, pick bundles — no config needed
  - Intermediate: `.dotfiles.toml` for toggling features and selecting extensions
  - Power users: custom extensions in any language, multiple backends

## Low Priority / Ideas

- [ ] **Auto-generated bundle docs** - Generate documentation showing what each bundle installs (packages, configs, symlinks) for quick reference.

- [ ] **CI on macOS runners** - Add GitHub Actions to test install.sh in a macOS VM on PRs, not just linting.

- [ ] **Backup/sync integration** - Integrate rclone/restic for automated config backups beyond git + cloud.

- [ ] **Office productivity bundle** - Consolidate office tools (Word, Excel, PowerPoint) into a dedicated bundle. Currently split across personal and work bundles.

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
- [x] Add daemon manager TUI (`scripts/daemons`) with curses interface, orphan detection, and CLI delegation
- [x] Add GitHub release helpers (`scripts/lib/github.sh`) for downloading release tarballs
- [x] Replace `just` → `rune` in all user-facing script messages
- [x] Document shell state coverage (zshrc/zshenv/zprofile)
