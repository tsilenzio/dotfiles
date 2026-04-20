#!/usr/bin/env bash
# Claude Code statusline
#
# Renders a multi-line status bar below the Claude Code prompt. Receives JSON
# via stdin describing the current session (model, context window, rate limits,
# workspace path). Outputs ANSI-colored text to stdout.
#
# Requires: jq (https://jqlang.github.io/jq/)
#
# The directory line mimics Starship's default prompt format (directory, git,
# package version, language runtimes) using Nerd Font glyphs for icons.
# Glyph codepoints sourced from:
#   https://github.com/tsilenzio/dotfiles/blob/main/config/starship/starship.toml
#
# Structure:
#   1. DATA        — parse input, detect environment, set variables
#   2. PRIMITIVES  — reusable drawing functions (bars, gradients, colors)
#   3. LAYOUT      — compose the final output (edit this section to restyle)
#
# Environment variables:
#   CLAUDE_STATUSLINE_DEBUG=1   — dump raw JSON and computed values to ~/.claude/statusline-debug.*
#   CLAUDE_STATUSLINE_BLUE      — override gradient stop (R;G;B), default: 70;130;200
#   CLAUDE_STATUSLINE_GREEN     — override gradient stop (R;G;B), default: 60;170;80
#   CLAUDE_STATUSLINE_YELLOW    — override gradient stop (R;G;B), default: 255;160;0
#   CLAUDE_STATUSLINE_ORANGE    — override gradient stop (R;G;B), default: 190;120;40
#   CLAUDE_STATUSLINE_RED       — override gradient stop (R;G;B), default: 255;20;10
#   CLAUDE_STATUSLINE_GRAY      — override burn-rate neutral (R;G;B), default: 130;130;130

input=$(cat)

# Debug: dump raw input JSON to /tmp/claude-statusline/<session_id>/<timestamp>.json
# Enable via env var at launch or touch /tmp/claude-statusline-debug to toggle live
if [ "${CLAUDE_STATUSLINE_DEBUG:-0}" = "1" ] || [ -f /tmp/claude-statusline-debug ]; then
    debug_session=$(echo "$input" | jq -r '.session_id // "unknown"')
    debug_dir="/tmp/claude-statusline/${debug_session}"
    mkdir -p "$debug_dir" 2>/dev/null
    echo "$input" | jq . > "${debug_dir}/$(date +%Y%m%d-%H%M%S).json" 2>/dev/null
fi

# ==========================================================================
# DATA — parse input, detect environment, set variables
# ==========================================================================

# Constants
CTX_LIMIT_1M=1000000
CTX_LIMIT_200K=200000
WINDOW_5H=18000               # 5 hours in seconds
WINDOW_7D=604800              # 7 days in seconds
SECS_PER_DAY=86400
SECS_PER_HOUR=3600
BAR_WIDTH=20

# Nerd font glyphs via ANSI-C escapes.
# BMP private-use area glyphs get stripped by some text pipelines; these survive.
ICON_GIT=$'\uF418'
ICON_PKG=$'\U000F03D7'
ICON_NODEJS=$'\uE718'
ICON_PYTHON=$'\uE235'
ICON_RUST=$'\U000F1617'
ICON_GOLANG=$'\uE627'
ICON_RUBY=$'\uE791'
ICON_ELIXIR=$'\uE62D'
ICON_DENO=$'\uE7C0'
ICON_BUN=$'\uE76F'
ICON_PHP=$'\uE608'
ICON_LUA=$'\uE620'
ICON_JAVA=$'\uE256'
ICON_KOTLIN=$'\uE634'
ICON_SCALA=$'\uE737'
ICON_HASKELL=$'\uE777'
ICON_OCAML=$'\uE67A'
ICON_DART=$'\uE798'
ICON_SWIFT=$'\uE755'
ICON_ZIG=$'\uE6A9'
ICON_CRYSTAL=$'\uE62F'
ICON_PERL=$'\uE67E'
ICON_TF=$'\uE69A'

# ANSI styling
RESET=$'\033[0m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
GREEN=$'\033[32m'
CYAN=$'\033[36m'
PURPLE=$'\033[35m'
ORANGE=$'\033[38;5;208m'
FADED_WHITE=$'\033[38;2;230;230;230m'

# Bar drawing
TICK=$'\u258F'                            # flush-left partial block for position markers
BAR_EMPTY_RGB="40;40;40"                  # empty bar cell background
TICK_FILLED_RGB="255;255;255"             # tick foreground inside filled bar
TICK_EMPTY_RGB="200;200;200"              # tick foreground inside empty bar
HEADER_LINE_RGB="80;80;80"                # section header underline color

# Gradient palette — override with CLAUDE_STATUSLINE_<COLOR>='R;G;B' env vars
SL_BLUE="${CLAUDE_STATUSLINE_BLUE:-70;130;200}"
SL_GREEN="${CLAUDE_STATUSLINE_GREEN:-60;170;80}"
SL_YELLOW="${CLAUDE_STATUSLINE_YELLOW:-255;160;0}"
SL_ORANGE="${CLAUDE_STATUSLINE_ORANGE:-190;120;40}"
SL_RED="${CLAUDE_STATUSLINE_RED:-255;20;10}"
SL_GRAY="${CLAUDE_STATUSLINE_GRAY:-130;130;130}"

IFS=';' read -r SL_BLUE_R SL_BLUE_G SL_BLUE_B <<< "$SL_BLUE"
IFS=';' read -r SL_GREEN_R SL_GREEN_G SL_GREEN_B <<< "$SL_GREEN"
IFS=';' read -r SL_YELLOW_R SL_YELLOW_G SL_YELLOW_B <<< "$SL_YELLOW"
IFS=';' read -r SL_ORANGE_R SL_ORANGE_G SL_ORANGE_B <<< "$SL_ORANGE"
IFS=';' read -r SL_RED_R SL_RED_G SL_RED_B <<< "$SL_RED"
IFS=';' read -r SL_GRAY_R SL_GRAY_G SL_GRAY_B <<< "$SL_GRAY"

# Parse all JSON fields in a single jq call (tab-separated to handle spaces in values)
# Use newline-separated output to avoid IFS tab-collapsing empty fields
{
read -r cwd
read -r model_name
read -r model_id
read -r ctx_tokens
read -r ctx_limit
read -r ctx_pct_raw
read -r rate_5h_pct
read -r rate_5h_resets_at
read -r rate_7d_pct
read -r rate_7d_resets_at
} <<< "$(echo "$input" | jq -r '
  (.workspace.current_dir // .cwd // ""),
  (.model.display_name // ""),
  (.model.id // ""),
  (.context_window.current_usage |
    if . == null then ""
    else ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0) | tostring)
    end),
  (.context_window.context_window_size // ""),
  (.context_window.used_percentage // ""),
  (.rate_limits.five_hour.used_percentage // "" | if . != "" then floor else . end),
  (.rate_limits.five_hour.resets_at // ""),
  (.rate_limits.seven_day.used_percentage // "" | if . != "" then floor else . end),
  (.rate_limits.seven_day.resets_at // "")
')"

dir_name=$(basename "$cwd")

# Context window limit from JSON, falling back to model ID heuristic
if [ -z "$ctx_limit" ]; then
    if [[ "$model_id" == *"[1m]"* ]]; then
        ctx_limit=$CTX_LIMIT_1M
    else
        ctx_limit=$CTX_LIMIT_200K
    fi
fi

ctx_pct=""
ctx_used_k=""
ctx_limit_label=""
ctx_tick=-1
has_ctx=false

if [ -n "$ctx_tokens" ] && [ "$ctx_tokens" != "0" ]; then
    ctx_used_k=$(awk "BEGIN { printf \"%.1f\", $ctx_tokens / 1000 }")
    if [ -n "$ctx_pct_raw" ]; then
        ctx_pct=$(printf '%.0f' "$ctx_pct_raw")
    else
        ctx_pct=$(awk "BEGIN { printf \"%.0f\", $ctx_tokens / $ctx_limit * 100 }")
    fi
    has_ctx=true
    if [ "$ctx_limit" -eq "$CTX_LIMIT_1M" ]; then
        ctx_limit_label="1m"
        # Marks where a 200k context window would end on 1M models
        ctx_tick=$((BAR_WIDTH * 20 / 100))
    else
        ctx_limit_label="200k"
    fi
fi

# Rate limits
now=$(date +%s)

compute_elapsed_pct() {
    local resets_at=$1 window_secs=$2
    local remaining=$((resets_at - now))
    [ "$remaining" -lt 0 ] && remaining=0
    local elapsed=$((window_secs - remaining))
    [ "$elapsed" -lt 0 ] && elapsed=0
    awk "BEGIN { printf \"%.0f\", $elapsed / $window_secs * 100 }"
}

format_remaining() {
    local resets_at=$1
    local secs=$((resets_at - now))
    [ "$secs" -lt 0 ] && secs=0
    if [ "$secs" -ge "$SECS_PER_DAY" ]; then
        printf '%dd %dh' $((secs / SECS_PER_DAY)) $(( (secs % SECS_PER_DAY) / SECS_PER_HOUR ))
    elif [ "$secs" -ge "$SECS_PER_HOUR" ]; then
        printf '%dh %02dm' $((secs / SECS_PER_HOUR)) $(( (secs % SECS_PER_HOUR) / 60 ))
    else
        printf '%dm' $((secs / 60))
    fi
}

has_rate_5h=false
rate_5h_elapsed_pct=""
rate_5h_remaining=""
if [ -n "$rate_5h_pct" ] && [ -n "$rate_5h_resets_at" ]; then
    rate_5h_elapsed_pct=$(compute_elapsed_pct "$rate_5h_resets_at" "$WINDOW_5H")
    rate_5h_remaining=$(format_remaining "$rate_5h_resets_at")
    has_rate_5h=true
fi

has_rate_7d=false
rate_7d_elapsed_pct=""
rate_7d_remaining=""
if [ -n "$rate_7d_pct" ] && [ -n "$rate_7d_resets_at" ]; then
    rate_7d_elapsed_pct=$(compute_elapsed_pct "$rate_7d_resets_at" "$WINDOW_7D")
    rate_7d_remaining=$(format_remaining "$rate_7d_resets_at")
    has_rate_7d=true
fi

has_rate_limits=false
($has_rate_5h || $has_rate_7d) && has_rate_limits=true

# Git
git_branch=""
git_status_chars=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree &>/dev/null; then
    git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
                 || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    if [ -n "$git_branch" ]; then
        porcelain=$(git -C "$cwd" status --porcelain 2>/dev/null)
        if [ -n "$porcelain" ]; then
            git_status_chars=$(echo "$porcelain" | awk '
                /^.M/      { m=1 }
                /^[MARCD]/ { s=1 }
                /^\?\?/    { u=1 }
                END { if(m) printf "!"; if(s) printf "+"; if(u) printf "?" }
            ')
        fi
    fi
fi

# Package version
pkg_ver=""
if [ -f "$cwd/Cargo.toml" ]; then
    pkg_ver=$(grep -m1 '^version' "$cwd/Cargo.toml" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/')
elif [ -f "$cwd/package.json" ]; then
    pkg_ver=$(grep -m1 '"version"' "$cwd/package.json" 2>/dev/null | sed -E 's/.*"version"[^"]*"([^"]+)".*/\1/')
elif [ -f "$cwd/pyproject.toml" ]; then
    pkg_ver=$(grep -m1 '^version' "$cwd/pyproject.toml" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/')
elif [ -f "$cwd/composer.json" ]; then
    pkg_ver=$(grep -m1 '"version"' "$cwd/composer.json" 2>/dev/null | sed -E 's/.*"version"[^"]*"([^"]+)".*/\1/')
fi

# Language detection helpers
_pin() {
    local lang="$1" f v
    for f in "$cwd/.tool-versions" "$cwd/mise.toml" "$cwd/.mise.toml"; do
        [ -f "$f" ] || continue
        if [[ "$f" == *".tool-versions" ]]; then
            v=$(grep -m1 "^${lang}[[:space:]]" "$f" 2>/dev/null | awk '{print $2}')
        else
            v=$(grep -m1 "^${lang}[[:space:]]*=" "$f" 2>/dev/null | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/')
        fi
        [ -n "$v" ] && { echo "$v"; return; }
    done
}

# langs array: each entry is "icon;ver;color" for the layout to iterate
langs=()

_detect() {
    local icon="$1" ver="$2" color="$3"
    local v=""
    [ -n "$ver" ] && v=" v${ver}"
    langs+=("${icon};${ver};${color}")
}

# Rust
if [ -f "$cwd/Cargo.toml" ] || [ -f "$cwd/rust-toolchain.toml" ]; then
    ver=$(_pin "rust")
    if [ -z "$ver" ] && [ -f "$cwd/rust-toolchain.toml" ]; then
        ver=$(grep -m1 '^channel' "$cwd/rust-toolchain.toml" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/')
    fi
    [ -z "$ver" ] && command -v rustc &>/dev/null && ver=$(rustc --version 2>/dev/null | awk '{print $2}')
    _detect "$ICON_RUST" "$ver" "$RED"
fi

# Node
if [ -f "$cwd/package.json" ] || [ -f "$cwd/.nvmrc" ]; then
    ver=$(_pin "nodejs")
    [ -z "$ver" ] && [ -f "$cwd/.nvmrc" ] && ver=$(tr -d '[:space:]v' < "$cwd/.nvmrc" 2>/dev/null)
    [ -z "$ver" ] && command -v node &>/dev/null && ver=$(node --version 2>/dev/null | tr -d 'v')
    _detect "$ICON_NODEJS" "$ver" "$GREEN"
fi

# Python
if [ -f "$cwd/pyproject.toml" ] || [ -f "$cwd/requirements.txt" ] || [ -f "$cwd/Pipfile" ] || [ -f "$cwd/.python-version" ]; then
    ver=$(_pin "python")
    [ -z "$ver" ] && [ -f "$cwd/.python-version" ] && ver=$(tr -d '[:space:]' < "$cwd/.python-version" 2>/dev/null)
    [ -z "$ver" ] && command -v python3 &>/dev/null && ver=$(python3 --version 2>/dev/null | awk '{print $2}')
    _detect "$ICON_PYTHON" "$ver" "$YELLOW"
fi

# Go
if [ -f "$cwd/go.mod" ]; then
    ver=$(_pin "golang")
    [ -z "$ver" ] && ver=$(grep -m1 '^go ' "$cwd/go.mod" 2>/dev/null | awk '{print $2}')
    _detect "$ICON_GOLANG" "$ver" "$CYAN"
fi

# Ruby
if [ -f "$cwd/Gemfile" ]; then
    ver=$(_pin "ruby")
    [ -z "$ver" ] && command -v ruby &>/dev/null && ver=$(ruby --version 2>/dev/null | awk '{print $2}')
    _detect "$ICON_RUBY" "$ver" "$RED"
fi

# Elixir
if [ -f "$cwd/mix.exs" ]; then
    ver=$(_pin "elixir")
    _detect "$ICON_ELIXIR" "$ver" "$PURPLE"
fi

# Deno
if [ -f "$cwd/deno.json" ] || [ -f "$cwd/deno.jsonc" ]; then
    ver=$(_pin "deno")
    _detect "$ICON_DENO" "$ver" "$GREEN"
fi

# Bun
if [ -f "$cwd/bun.lockb" ]; then
    ver=$(_pin "bun")
    _detect "$ICON_BUN" "$ver" "$RED"
fi

# PHP
if [ -f "$cwd/composer.json" ]; then
    ver=$(_pin "php")
    _detect "$ICON_PHP" "$ver" "$PURPLE"
fi

# Lua
if [ -f "$cwd/.lua-version" ] || ls "$cwd"/*.lua &>/dev/null; then
    ver=$(_pin "lua")
    [ -z "$ver" ] && command -v lua &>/dev/null && ver=$(lua -v 2>&1 | awk '{print $2}')
    _detect "$ICON_LUA" "$ver" "$CYAN"
fi

# Java
if [ -f "$cwd/pom.xml" ] || [ -f "$cwd/build.gradle.kts" ] || [ -f "$cwd/build.sbt" ] || [ -f "$cwd/.java-version" ]; then
    ver=$(_pin "java")
    _detect "$ICON_JAVA" "$ver" "$RED"
fi

# Kotlin
if ls "$cwd"/*.kt "$cwd"/*.kts &>/dev/null; then
    ver=$(_pin "kotlin")
    _detect "$ICON_KOTLIN" "$ver" "$PURPLE"
fi

# Scala
if [ -f "$cwd/build.sbt" ] || [ -f "$cwd/.scalaenv" ] || [ -f "$cwd/.sbtenv" ]; then
    ver=$(_pin "scala")
    _detect "$ICON_SCALA" "$ver" "$RED"
fi

# Haskell
if [ -f "$cwd/stack.yaml" ] || [ -f "$cwd/cabal.project" ]; then
    ver=$(_pin "haskell")
    [ -z "$ver" ] && command -v ghc &>/dev/null && ver=$(ghc --numeric-version 2>/dev/null)
    _detect "$ICON_HASKELL" "$ver" "$PURPLE"
fi

# OCaml
if [ -f "$cwd/dune" ] || [ -f "$cwd/dune-project" ] || [ -f "$cwd/.merlin" ]; then
    ver=$(_pin "ocaml")
    [ -z "$ver" ] && command -v ocaml &>/dev/null && ver=$(ocaml -vnum 2>/dev/null)
    _detect "$ICON_OCAML" "$ver" "$YELLOW"
fi

# Dart
if [ -f "$cwd/pubspec.yaml" ] || [ -f "$cwd/pubspec.yml" ] || [ -f "$cwd/pubspec.lock" ]; then
    ver=$(_pin "dart")
    [ -z "$ver" ] && command -v dart &>/dev/null && ver=$(dart --version 2>&1 | awk '{print $4}')
    _detect "$ICON_DART" "$ver" "$CYAN"
fi

# Swift
if [ -f "$cwd/Package.swift" ]; then
    ver=$(_pin "swift")
    [ -z "$ver" ] && command -v swift &>/dev/null && ver=$(swift --version 2>/dev/null | awk '{print $4}')
    _detect "$ICON_SWIFT" "$ver" "$ORANGE"
fi

# Zig
if [ -f "$cwd/build.zig" ] || [ -f "$cwd/build.zig.zon" ]; then
    ver=$(_pin "zig")
    [ -z "$ver" ] && command -v zig &>/dev/null && ver=$(zig version 2>/dev/null)
    _detect "$ICON_ZIG" "$ver" "$YELLOW"
fi

# Crystal
if [ -f "$cwd/shard.yml" ]; then
    ver=$(_pin "crystal")
    [ -z "$ver" ] && command -v crystal &>/dev/null && ver=$(crystal --version 2>/dev/null | awk 'NR==1{print $2}')
    _detect "$ICON_CRYSTAL" "$ver" "$PURPLE"
fi

# Perl
if [ -f "$cwd/Makefile.PL" ] || [ -f "$cwd/Build.PL" ] || [ -f "$cwd/cpanfile" ] || [ -f "$cwd/.perl-version" ]; then
    ver=$(_pin "perl")
    [ -z "$ver" ] && command -v perl &>/dev/null && ver=$(perl -e 'printf "%vd",$^V' 2>/dev/null)
    _detect "$ICON_PERL" "$ver" "$CYAN"
fi

# Terraform (icon only, no version)
if ls "$cwd"/*.tf "$cwd"/*.tfvars &>/dev/null; then
    _detect "$ICON_TF" "" "$PURPLE"
fi

# Debug: dump computed values alongside the raw JSON
if [ "${CLAUDE_STATUSLINE_DEBUG:-0}" = "1" ] || [ -f /tmp/claude-statusline-debug ]; then
    {
        echo "=== Computed Values ==="
        echo "cwd=$cwd"
        echo "dir_name=$dir_name"
        echo "model_name=$model_name"
        echo "model_id=$model_id"
        echo "ctx_tokens=$ctx_tokens ctx_pct=$ctx_pct ctx_used_k=$ctx_used_k"
        echo "ctx_limit=$ctx_limit ctx_limit_label=$ctx_limit_label ctx_tick=$ctx_tick"
        echo "has_ctx=$has_ctx has_rate_limits=$has_rate_limits"
        echo "has_rate_5h=$has_rate_5h rate_5h_pct=$rate_5h_pct rate_5h_elapsed_pct=$rate_5h_elapsed_pct rate_5h_remaining=$rate_5h_remaining"
        echo "has_rate_7d=$has_rate_7d rate_7d_pct=$rate_7d_pct rate_7d_elapsed_pct=$rate_7d_elapsed_pct rate_7d_remaining=$rate_7d_remaining"
        echo "git_branch=$git_branch git_status_chars=$git_status_chars"
        echo "pkg_ver=$pkg_ver"
        echo "langs=(${langs[*]})"
    } > "${debug_dir}/$(date +%Y%m%d-%H%M%S)-computed.txt" 2>/dev/null
fi

# ==========================================================================
# PRIMITIVES — reusable drawing functions
# ==========================================================================

# 5-stop usage gradient: blue -> green -> yellow -> orange -> red (0-100%)
# Maps a percentage to an R;G;B string for coloring percentage text and context bars.
usage_gradient_rgb() {
    awk -v pct="$1" \
        -v br="$SL_BLUE_R" -v bg="$SL_BLUE_G" -v bb="$SL_BLUE_B" \
        -v gr="$SL_GREEN_R" -v gg="$SL_GREEN_G" -v gb="$SL_GREEN_B" \
        -v yr="$SL_YELLOW_R" -v yg="$SL_YELLOW_G" -v yb="$SL_YELLOW_B" \
        -v or_="$SL_ORANGE_R" -v og="$SL_ORANGE_G" -v ob="$SL_ORANGE_B" \
        -v rr="$SL_RED_R" -v rg="$SL_RED_G" -v rb="$SL_RED_B" \
    'function interp(a,b,t) { return int(a+(b-a)*t+0.5) }
    BEGIN {
        t = pct / 100; if (t > 1) t = 1; if (t < 0) t = 0
        if (t <= 0.25) {
            s = t / 0.25
            r = interp(br,gr,s); g = interp(bg,gg,s); b = interp(bb,gb,s)
        } else if (t <= 0.5) {
            s = (t-0.25) / 0.25
            r = interp(gr,yr,s); g = interp(gg,yg,s); b = interp(gb,yb,s)
        } else if (t <= 0.75) {
            s = (t-0.5) / 0.25
            r = interp(yr,or_,s); g = interp(yg,og,s); b = interp(yb,ob,s)
        } else {
            s = (t-0.75) / 0.25
            r = interp(or_,rr,s); g = interp(og,rg,s); b = interp(ob,rb,s)
        }
        printf "%d;%d;%d", r, g, b
    }'
}

# 5-stop burn rate gradient: blue -> green -> gray -> orange -> red
# Ratio = usage_pct / elapsed_pct. Gray at 1.0 means on-pace.
# Used for rate limit bar fill and time-remaining label coloring.
burn_rate_rgb() {
    local pct=$1 elapsed_pct=$2
    awk -v pct="$pct" -v ep="$elapsed_pct" \
        -v br="$SL_BLUE_R" -v bg_="$SL_BLUE_G" -v bb="$SL_BLUE_B" \
        -v gr="$SL_GREEN_R" -v gg="$SL_GREEN_G" -v gb="$SL_GREEN_B" \
        -v xr="$SL_GRAY_R" -v xg="$SL_GRAY_G" -v xb="$SL_GRAY_B" \
        -v or_="$SL_ORANGE_R" -v og="$SL_ORANGE_G" -v ob="$SL_ORANGE_B" \
        -v rr="$SL_RED_R" -v rg="$SL_RED_G" -v rb="$SL_RED_B" \
    'function interp(a,b,t) { return int(a+(b-a)*t+0.5) }
    BEGIN {
        if (ep < 1) ep = 1
        ratio = pct / ep
        if (ratio < 0.4) {
            r = br; g = bg_; b = bb
        } else if (ratio < 0.7) {
            t = (ratio - 0.4) / 0.3
            r = interp(br,gr,t); g = interp(bg_,gg,t); b = interp(bb,gb,t)
        } else if (ratio < 1.0) {
            t = (ratio - 0.7) / 0.3
            r = interp(gr,xr,t); g = interp(gg,xg,t); b = interp(gb,xb,t)
        } else if (ratio < 1.3) {
            t = (ratio - 1.0) / 0.3
            r = interp(xr,or_,t); g = interp(xg,og,t); b = interp(xb,ob,t)
        } else if (ratio < 2.0) {
            t = (ratio - 1.3) / 0.7
            r = interp(or_,rr,t); g = interp(og,rg,t); b = interp(ob,rb,t)
        } else {
            r = rr; g = rg; b = rb
        }
        printf "%d;%d;%d", r, g, b
    }'
}

# draw_bar <pct> <width> <fill_r> <fill_g> <fill_b> [tick_pos]
#
# Draws a horizontal bar. Caller computes the fill color and passes RGB in.
# tick_pos is optional: omit or pass -1 to skip the position marker.
draw_bar() {
    local pct=$1 w=$2 fr=$3 fg=$4 fb=$5 tick=${6:--1}
    local fill=$((w * pct / 100))
    [ "$tick" -ge "$w" ] 2>/dev/null && tick=$((w - 1))

    IFS=';' read -r er eg eb <<< "$BAR_EMPTY_RGB"
    IFS=';' read -r tfr tfg tfb <<< "$TICK_FILLED_RGB"
    IFS=';' read -r ter teg teb <<< "$TICK_EMPTY_RGB"

    for ((i=0; i<w; i++)); do
        if ((i < fill)); then
            if ((tick >= 0 && i == tick)); then
                printf '\033[38;2;%d;%d;%dm\033[48;2;%d;%d;%dm%s\033[0m' "$tfr" "$tfg" "$tfb" "$fr" "$fg" "$fb" "$TICK"
            else
                printf '\033[48;2;%d;%d;%dm \033[0m' "$fr" "$fg" "$fb"
            fi
        else
            if ((tick >= 0 && i == tick)); then
                printf '\033[38;2;%d;%d;%dm\033[48;2;%d;%d;%dm%s\033[0m' "$ter" "$teg" "$teb" "$er" "$eg" "$eb" "$TICK"
            else
                printf '\033[48;2;%d;%d;%dm \033[0m' "$er" "$eg" "$eb"
            fi
        fi
    done
}

# rgb_fg "R;G;B" "text" — print text in the given foreground color
rgb_fg() {
    IFS=';' read -r r g b <<< "$1"
    printf '\033[38;2;%d;%d;%dm%s\033[0m' "$r" "$g" "$b" "$2"
}

# pad_to <used_width> <target_width> <content...>
# Pads with spaces so the content starts at the target column.
pad_to() {
    local used=$1 target=$2; shift 2
    local gap=$((target - used))
    [ "$gap" -lt 0 ] && gap=0
    printf '%*s%s' "$gap" "" "$@"
}

# render_rate_bar <label> <pct> <elapsed_pct> <remaining>
# Renders a complete rate limit bar line: "5H:  XX% [bar] Xh XXm left"
render_rate_bar() {
    local name=$1 pct=$2 elapsed=$3 remaining=$4

    local tick=$((BAR_WIDTH * elapsed / 100))
    [ "$tick" -ge "$BAR_WIDTH" ] && tick=$((BAR_WIDTH - 1))

    local prgb brgb
    prgb=$(usage_gradient_rgb "$pct")
    brgb=$(burn_rate_rgb "$pct" "$elapsed")
    IFS=';' read -r br bg bb <<< "$brgb"

    # Leading \033[0m prevents Claude Code from trimming the space before short labels like " 7D"
    printf '\033[0m%3s: ' "$name"
    rgb_fg "$prgb" "$(printf '%3d%%' "$pct")"
    printf ' '
    draw_bar "$pct" "$BAR_WIDTH" "$br" "$bg" "$bb" "$tick"
    printf ' '
    rgb_fg "$brgb" "$(printf '%-6s left' "$remaining")"
}

# ==========================================================================
# LAYOUT — edit this section to rearrange the statusline
# ==========================================================================

# Line 1: directory, git, package, languages (starship-style)
parts=()
[ -n "$dir_name" ] && parts+=("${BOLD}${CYAN}${dir_name}${RESET}")

if [ -n "$git_branch" ]; then
    status_str=""
    [ -n "$git_status_chars" ] && status_str=" ${BOLD}${RED}[${git_status_chars}]${RESET}"
    parts+=("${FADED_WHITE}on${RESET} ${BOLD}${PURPLE}${ICON_GIT} ${git_branch}${RESET}${status_str}")
fi

[ -n "$pkg_ver" ] && parts+=("${FADED_WHITE}is${RESET} ${BOLD}${ORANGE}${ICON_PKG} v${pkg_ver}${RESET}")

for entry in "${langs[@]}"; do
    IFS=';' read -r icon ver color <<< "$entry"
    v=""
    [ -n "$ver" ] && v=" v${ver}"
    parts+=("${FADED_WHITE}via${RESET} ${BOLD}${color}${icon}${v}${RESET}")
done

printf '%s' "${parts[*]}"

# Remaining lines depend on what data is available
if ! $has_ctx && ! $has_rate_limits; then
    # No session or usage data: just model name
    [ -n "$model_name" ] && printf '\n\033[0m\n%s%s%s' "$DIM" "$model_name" "$RESET"
else
    # Pre-render rate bars so we can measure/reuse them
    rate_5h_line=""
    $has_rate_5h && rate_5h_line=$(render_rate_bar "5H" "$rate_5h_pct" "$rate_5h_elapsed_pct" "$rate_5h_remaining")
    rate_7d_line=""
    $has_rate_7d && rate_7d_line=$(render_rate_bar "7D" "$rate_7d_pct" "$rate_7d_elapsed_pct" "$rate_7d_remaining")

    # Compute column widths for alignment
    ctx_pct_w=0
    token_label=""
    line_ctx_vw=0
    if $has_ctx; then
        ctx_pct_w=${#ctx_pct}
        token_label="${ctx_used_k}k/${ctx_limit_label} tokens"
        line_ctx_vw=$((ctx_pct_w + 2 + BAR_WIDTH + 1 + ${#token_label}))
    fi

    line_model_vw=0
    [ -n "$model_name" ] && line_model_vw=${#model_name}

    target_w=$line_ctx_vw
    [ "$line_model_vw" -gt "$target_w" ] && target_w=$line_model_vw
    target_w=$((target_w + 2))

    # Header row
    IFS=';' read -r hlr hlg hlb <<< "$HEADER_LINE_RGB"

    if $has_ctx && $has_rate_limits; then
        # Both columns: Session + Usage
        session_pad=$((target_w - 6))
        session_line_w=$line_ctx_vw
        [ "$session_line_w" -lt "$line_model_vw" ] && session_line_w=$line_model_vw
        usage_gap=$((target_w - session_line_w + 1))

        printf '\n\033[0m\n%sSession' "$DIM"
        printf '%*s' "$session_pad" ""
        printf 'Usage%s' "$RESET"
        printf '\n\033[38;2;%d;%d;%dm' "$hlr" "$hlg" "$hlb"
        for ((i=0; i<session_line_w; i++)); do printf '\u2500'; done
        printf '%*s' "$usage_gap" ""
        for ((i=0; i<41; i++)); do printf '\u2500'; done
        printf '%s' "$RESET"
    elif $has_ctx; then
        # Session only
        session_line_w=$line_ctx_vw
        [ "$session_line_w" -lt "$line_model_vw" ] && session_line_w=$line_model_vw

        printf '\n\n%sSession%s' "$DIM" "$RESET"
        printf '\n\033[38;2;%d;%d;%dm' "$hlr" "$hlg" "$hlb"
        for ((i=0; i<session_line_w; i++)); do printf '\u2500'; done
        printf '%s' "$RESET"
    else
        # Usage only
        printf '\n\033[0m\n%sUsage%s' "$DIM" "$RESET"
        printf '\n\033[38;2;%d;%d;%dm' "$hlr" "$hlg" "$hlb"
        for ((i=0; i<41; i++)); do printf '\u2500'; done
        printf '%s' "$RESET"
    fi

    # Model name row (left) + 5H rate bar (right)
    printf '\n'
    [ -n "$model_name" ] && printf '%s%s%s' "$DIM" "$model_name" "$RESET"
    if [ -n "$rate_5h_line" ] && $has_ctx; then
        pad_to "$line_model_vw" "$target_w" "$rate_5h_line"
    elif [ -n "$rate_5h_line" ]; then
        printf '  %s' "$rate_5h_line"
    fi

    # Context bar row (left) + 7D rate bar (right)
    if $has_ctx; then
        printf '\n'
        local_rgb=$(usage_gradient_rgb "$ctx_pct")
        IFS=';' read -r cr cg cb <<< "$local_rgb"

        printf '\033[0m\033[38;2;%d;%d;%dm%d%%\033[0m ' "$cr" "$cg" "$cb" "$ctx_pct"
        draw_bar "$ctx_pct" "$BAR_WIDTH" "$cr" "$cg" "$cb" "$ctx_tick"
        printf ' '
        rgb_fg "$local_rgb" "$token_label"

        if [ -n "$rate_7d_line" ]; then
            pad_to "$line_ctx_vw" "$target_w" "$rate_7d_line"
        fi
    elif [ -n "$rate_7d_line" ]; then
        printf '\n  %s' "$rate_7d_line"
    fi
fi
