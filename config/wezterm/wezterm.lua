-- WezTerm Configuration
-- Reference: https://wezfurlong.org/wezterm/config/files.html

local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Font
config.font = wezterm.font("SauceCodePro Nerd Font")
config.font_size = 14.0

-- Color scheme (built-in schemes: https://wezfurlong.org/wezterm/colorschemes/index.html)
config.color_scheme = "Catppuccin Mocha"

-- Window
config.window_decorations = "RESIZE"
config.window_padding = {
	left = 12,
	right = 12,
	top = 12,
	bottom = 12,
}

-- Tab bar
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = true

-- Cursor
config.default_cursor_style = "SteadyBar"

-- Performance
config.front_end = "WebGpu"

-- Disable update check (managed via Homebrew)
config.check_for_updates = false

-- Bell
config.audible_bell = "Disabled"

return config
