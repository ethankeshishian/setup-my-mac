-- ethanpuccin: base46 catppuccin with the greys lifted so comments,
-- line numbers, and other dim text are actually readable.
-- Grey values borrowed from upstream Catppuccin Mocha
-- (surface2 / overlay0 / overlay1 / overlay2).

local M = {}

M.base_30 = {
  white = "#D9E0EE",
  darker_black = "#191828",
  black = "#1E1D2D", --  nvim bg
  black2 = "#252434",
  one_bg = "#2d2c3c",
  one_bg2 = "#363545",
  one_bg3 = "#3e3d4d",
  grey = "#585b70", -- was #474656 (surface2)
  grey_fg = "#6c7086", -- was #4e4d5d (overlay0)
  grey_fg2 = "#7f849c", -- was #555464 (overlay1)
  light_grey = "#9399b2", -- was #605f6f (overlay2)
  red = "#F38BA8",
  baby_pink = "#ffa5c3",
  pink = "#F5C2E7",
  line = "#383747", -- for lines like vertsplit
  green = "#ABE9B3",
  vibrant_green = "#b6f4be",
  nord_blue = "#8bc2f0",
  blue = "#89B4FA",
  yellow = "#FAE3B0",
  sun = "#ffe9b6",
  purple = "#d0a9e5",
  dark_purple = "#c7a0dc",
  teal = "#B5E8E0",
  orange = "#F8BD96",
  cyan = "#89DCEB",
  statusline_bg = "#232232",
  lightbg = "#2f2e3e",
  pmenu_bg = "#ABE9B3",
  folder_bg = "#89B4FA",
  lavender = "#c7d1ff",
}

M.base_16 = {
  base00 = "#1E1D2D",
  base01 = "#282737",
  base02 = "#2f2e3e",
  base03 = "#7f849c", -- comments; was #383747 (overlay1)
  base04 = "#9399b2", -- dark fg; was #414050 (overlay2)
  base05 = "#bfc6d4",
  base06 = "#ccd3e1",
  base07 = "#D9E0EE",
  base08 = "#F38BA8",
  base09 = "#F8BD96",
  base0A = "#FAE3B0",
  base0B = "#ABE9B3",
  base0C = "#89DCEB",
  base0D = "#89B4FA",
  base0E = "#CBA6F7",
  base0F = "#F38BA8",
}

M.polish_hl = {
  treesitter = {
    ["@variable"] = { fg = M.base_30.lavender },
    ["@property"] = { fg = M.base_30.teal },
    ["@variable.builtin"] = { fg = M.base_30.red },
  },
}

M.type = "dark"

M = require("base46").override_theme(M, "ethanpuccin")

return M
