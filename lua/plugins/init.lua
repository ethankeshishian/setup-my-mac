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
    
    -- FIX: Buffer crash prevention
    opts.defaults.hl_result_eol = false
    
    -- Add cache_picker configuration to store multiple previous pickers (reduced for stability)
    opts.defaults.cache_picker = {
      num_pickers = 5,
      limit_entries = 500
    }
    
    -- FIX: Use fd instead of ripgrep for find_files (memory leak mitigation)
    opts.pickers = {
      find_files = {
        find_command = { "fd", "--type", "f", "--hidden", "--follow" }
      }
    }
    
    -- Performance optimizations: exclude common build/dependency directories
    opts.defaults.file_ignore_patterns = {
      "%.git/",
      "node_modules/",
      "target/",
      "build/",
      "dist/",
    }
    
    -- Optimize ripgrep arguments for performance
    opts.defaults.vimgrep_arguments = {
      "rg",
      "--color=never",
      "--no-heading",
      "--with-filename",
      "--line-number",
      "--column",
      "--smart-case",
      "--glob=!.git/*",
      "--glob=!node_modules/*",
      "--glob=!target/*",
      "--glob=!build/*",
      "--glob=!dist/*",
    }
    
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


{
  "hrsh7th/nvim-cmp",
  opts = function(_, opts)
    local cmp = require "cmp"

    opts.mapping = vim.tbl_extend("force", opts.mapping or {}, {
      ["<CR>"] = cmp.mapping(function(fallback)
        fallback()  -- insert newline, no completion confirmation
      end, { "i", "s" }),
      ["<Tab>"] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.confirm { behavior = cmp.ConfirmBehavior.Insert, select = true }
        elseif require("luasnip").expand_or_jumpable() then
          require("luasnip").expand_or_jump()
        else
          fallback()
        end
      end, { "i", "s" }),
      ["<S-Tab>"] = cmp.mapping(function(fallback)
        if require("luasnip").jumpable(-1) then
          require("luasnip").jump(-1)
        else
          fallback()
        end
      end, { "i", "s" }),
      ["<Down>"] = cmp.mapping.select_next_item(),
      ["<Up>"]   = cmp.mapping.select_prev_item(),
    })

    return opts
  end,
},


  -- Preserve default opts while adding my own
  -- {
  --   "hrsh7th/nvim-cmp",
  --   opts = function(_, opts)
  --     local cmp = require "cmp"
  --
  --     opts.mapping = vim.tbl_deep_extend("force", opts.mapping or {}, {
  --       ["<Esc>"] = cmp.mapping(function(fallback)
  --         if cmp.visible() then
  --           cmp.close()
  --         else
  --           fallback()
  --         end
  --       end, { "i", "s" }),
  --     })
  --
  --     return opts
  --   end,
  -- },

{
	"nvim-treesitter/nvim-treesitter",
	opts = function(_, opts)
		opts.ensure_installed = vim.list_extend(opts.ensure_installed or {}, {
			"html", "css",
			"typescript", "javascript", "tsx",
			"haskell", "haskell_persistent"
		})
		return opts
	end,
},
}

