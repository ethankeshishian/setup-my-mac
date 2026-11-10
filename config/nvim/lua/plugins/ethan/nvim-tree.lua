return {
  {
    "nvim-tree/nvim-tree.lua",
    opts = {
      disable_netrw = true,  -- Prevents conflicts
      hijack_netrw = true,   -- Clean buffer handoff
      view = {
        number = true,
        relativenumber = true,
        -- adaptive_size was previously removed to prevent window management issues
        -- Re-enabled 2025-11-07 - untested, monitor for issues
        adaptive_size = true,
      },
      actions = {
        open_file = {
          quit_on_open = false,  -- Keep tree open for stability
          window_picker = {
            enable = true,
          },
        },
      },
    },
  },
}
