-- Floating command line, like LazyVim: `:` opens near the top of the screen with
-- suggestions underneath; `/` and `?` search stay at the bottom.
return {
  "folke/noice.nvim",
  event = "VeryLazy",
  dependencies = { "MunifTanjim/nui.nvim" },
  opts = {
    -- coc.nvim handles hover, signatures and progress; noice only restyles the
    -- command line and messages.
    lsp = {
      hover = { enabled = false },
      signature = { enabled = false },
      progress = { enabled = false },
      message = { enabled = false },
    },
    -- The / and ? prompt sits just above the statusline instead of covering it.
    views = {
      cmdline = { position = { row = -1 } },
    },
    routes = {
      -- The search count shows in the statusline (see chadrc.lua), not at the end of the line.
      { filter = { event = "msg_show", kind = "search_count" }, opts = { skip = true } },
      -- Write and undo/redo summaries ("12L, 340B written", "1 change; before #3") go to
      -- the small corner view instead of popups, as in LazyVim.
      {
        filter = {
          event = "msg_show",
          any = {
            { find = "%d+L, %d+B" },
            { find = "; after #%d+" },
            { find = "; before #%d+" },
          },
        },
        view = "mini",
      },
    },
    presets = {
      bottom_search = true,
      command_palette = true,
      long_message_to_split = true,
    },
  },
}
