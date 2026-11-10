return {
  "axkirillov/easypick.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "lewis6991/gitsigns.nvim",
    "nvim-lua/plenary.nvim",
  },
  lazy = false,
  config = function()
    local easypick = require("easypick")
    local previewers = require("telescope.previewers")
    local Job = require("plenary.job")
    local from_entry = require("telescope.from_entry")

    -- Get the Git Town parent branch, fallback to "main"
    local function get_parent_branch()
      local output = vim.fn.system("git town config get-parent")
      local parent = vim.trim(output)
      if parent == "" then
        parent = "main"
      end
      return parent
    end

    -- Custom clean previewer (no [Process exited 0])
    local function diff_against_merge_base(parent_branch)
      return previewers.new_buffer_previewer({
        define_preview = function(self, entry)
          local merge_base = vim.fn.system("git merge-base HEAD " .. parent_branch):gsub("%s+", "")
          local filename = from_entry.path(entry, false)

          Job:new({
            command = "git",
            args = { "diff", merge_base, "--", filename },
            on_exit = function(j)
              local result = j:result()
              vim.schedule(function()
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, result)
                vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "diff") -- optional: syntax highlighting
              end)
            end,
          }):start()
        end,
      })
    end

    -- Init once to capture value at startup
    local parent_branch = get_parent_branch()

    easypick.setup({
      pickers = {
        {
          name = "git_diff_parent",
          command = "git diff --name-only $(git merge-base HEAD " .. parent_branch .. " )",
          previewer = diff_against_merge_base(parent_branch),
        },
      },
    })

    -- Keymap: update Gitsigns base and open Easypick diff
    vim.keymap.set("n", "<leader>gd", function()
      local parent = get_parent_branch()
      local merge_base = vim.fn.system("git merge-base HEAD " .. parent):gsub("%s+", "")

      -- Override the Gitsigns config to persist the base across all buffers
      local ok, gs = pcall(require, "gitsigns")
      if ok then
        gs.setup({ base = merge_base })  -- this updates the global config

        -- Reattach Gitsigns to all relevant buffers
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_option(bufnr, "buflisted") then
            gs.attach(bufnr)
          end
        end
      end

      -- Launch Easypick diff
      vim.cmd("Easypick git_diff_parent")
    end, { desc = "Diff Git Town Parent" })


    vim.keymap.set("n", "<leader>gr", function()
      local ok, gs = pcall(require, "gitsigns")
      if not ok then return end

      -- Set base back to HEAD (or origin/main, your preference)
      gs.setup({ base = "HEAD" })

      -- Detach and reattach to fully refresh signs
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_option(bufnr, "buflisted") then
          gs.detach(bufnr)  -- detach first
          gs.attach(bufnr)  -- then reattach
        end
      end

      print("Gitsigns reset to HEAD")
    end, { desc = "Reset Gitsigns Base" })
  end,
}