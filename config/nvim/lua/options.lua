require "nvchad.options"

-- add yours here!

local o = vim.o
o.cursorlineopt ='both' -- to enable cursorline!


-- Command line: suggestions while typing, menu keys, and shell-style editing keys.
require("ethan.cmdline").setup()
