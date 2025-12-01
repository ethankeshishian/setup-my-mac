vim.g.base46_cache = vim.fn.stdpath "data" .. "/nvchad/base46/"
vim.g.mapleader = " "

-- bootstrap lazy and all plugins
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not vim.loop.fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  vim.fn.system { "git", "clone", "--filter=blob:none", repo, "--branch=stable", lazypath }
end

vim.opt.rtp:prepend(lazypath)

local lazy_config = require "configs.lazy"

-- load plugins
require("lazy").setup({
  {
    "NvChad/NvChad",
    lazy = false,
    branch = "v2.5",
    import = "nvchad.plugins",
    config = function()
      require "options"
    end,
  },

  { import = "plugins" },
  { import = "plugins/ethan"}
}, lazy_config)

-- load theme
dofile(vim.g.base46_cache .. "defaults")
dofile(vim.g.base46_cache .. "statusline")

require "nvchad.autocmds"

vim.schedule(function()
  require "mappings"
end)

-- Buffer initialization safety check to prevent telescope crashes
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    -- Create a minimal buffer if only nvim-tree exists
    local bufs = vim.api.nvim_list_bufs()
    local normal_buf_exists = false
    
    for _, buf in ipairs(bufs) do
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and not name:match("NvimTree") then
        normal_buf_exists = true
        break
      end
    end
    
    if not normal_buf_exists then
      vim.cmd("enew")  -- Create empty buffer to prevent crashes
    end
  end,
})

-- Ethan
require("ethan")
