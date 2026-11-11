-- Saves the open files and splits per folder and git branch when nvim exits, and restores them
-- when nvim starts in that folder without file arguments. `nvim file` and git's editor are unaffected.
return {
  "folke/persistence.nvim",
  lazy = false,
  opts = {},
  config = function(_, opts)
    local persistence = require "persistence"
    persistence.setup(opts)

    vim.api.nvim_create_autocmd("StdinReadPre", {
      callback = function()
        vim.g.started_with_stdin = true
      end,
    })
    vim.api.nvim_create_autocmd("VimEnter", {
      nested = true, -- let restored buffers run their FileType and BufRead autocmds
      callback = function()
        if vim.fn.argc() == 0 and not vim.g.started_with_stdin then
          persistence.load()
        end
      end,
    })
    -- nvim-tree's window would come back as an empty buffer; it reopens on demand.
    vim.api.nvim_create_autocmd("User", {
      pattern = "PersistenceSavePre",
      callback = function()
        pcall(vim.cmd, "NvimTreeClose")
      end,
    })
  end,
}
