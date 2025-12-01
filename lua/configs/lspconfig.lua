-- load defaults i.e lua_lsp
require("nvchad.configs.lspconfig").defaults()

local nvlsp = require "nvchad.configs.lspconfig"

-- EXAMPLE
local servers = { "html", "cssls" }

-- lsps with default config (using Neovim 0.11 API)
for _, lsp in ipairs(servers) do
  vim.lsp.config[lsp] = {
    on_attach = nvlsp.on_attach,
    on_init = nvlsp.on_init,
    capabilities = nvlsp.capabilities,
  }
  vim.lsp.enable(lsp)
end

-- configuring single server, example: typescript (using Neovim 0.11 API)
vim.lsp.config.ts_ls = {
  on_attach = nvlsp.on_attach,
  on_init = nvlsp.on_init,
  capabilities = nvlsp.capabilities,
}
vim.lsp.enable("ts_ls")

vim.lsp.config.jsonls = {
  on_attach = nvlsp.on_attach,
  on_init = nvlsp.on_init,
  capabilities = nvlsp.capabilities,
}
vim.lsp.enable("jsonls")

-- Custom LSP server configuration for static_ls (Haskell)
vim.lsp.config.static_ls = {
  cmd = { "static-ls" },
  filetypes = { "haskell" },
  root_markers = { "*.cabal", "stack.yaml", "cabal.project", "package.yaml", "hie.yaml" },
  on_attach = nvlsp.on_attach,
  on_init = nvlsp.on_init,
  capabilities = nvlsp.capabilities,
  settings = {
    haskell = {
      checkProject = false,
      formattingProvider = "none"
    }
  },
}
vim.lsp.enable("static_ls")

