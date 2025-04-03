return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre", -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  -- Preserve default opts while adding my own
  {
    "nvim-telescope/telescope.nvim",
    opts = function(_, opts)
      opts.defaults.wrap_results = true
      vim.api.nvim_create_autocmd("User", {
        pattern = "TelescopePreviewerLoaded",
        callback = function()
          vim.wo.number = true
          vim.wo.wrap = true
        end,
      })
      return opts
    end,
  },

  -- Preserve default opts while adding my own
  {
    "hrsh7th/nvim-cmp",
    opts = function(_, opts)
      local cmp = require "cmp"

      opts.mapping = vim.tbl_deep_extend("force", opts.mapping or {}, {
        ["<Esc>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.close()
          else
            fallback()
          end
        end, { "i", "s" }),
      })

      return opts
    end,
  },
}

-- {
-- 	"nvim-treesitter/nvim-treesitter",
-- 	opts = {
-- 		ensure_installed = {
-- 			"vim", "lua", "vimdoc",
--      "html", "css"
-- 		},
-- 	},
-- },
