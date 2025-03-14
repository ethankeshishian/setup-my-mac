-- load defaults i.e lua_lsp
require("nvchad.configs.lspconfig").defaults()

local lspconfig = require "lspconfig"

-- EXAMPLE
local servers = { "html", "cssls" }
local nvlsp = require "nvchad.configs.lspconfig"

-- lsps with default config
for _, lsp in ipairs(servers) do
  lspconfig[lsp].setup {
    on_attach = nvlsp.on_attach,
    on_init = nvlsp.on_init,
    capabilities = nvlsp.capabilities,
  }
end

-- configuring single server, example: typescript
lspconfig.ts_ls.setup {
  on_attach = nvlsp.on_attach,
  on_init = nvlsp.on_init,
  capabilities = nvlsp.capabilities,
}

lspconfig.jsonls.setup {
  on_attach = nvlsp.on_attach,
  on_init = nvlsp.on_init,
  capabilities = nvlsp.capabilities,
}

if not configs.static_ls then
  configs.static_ls = {
    default_config = {
      cmd = { "static-ls" },
      filetypes = { "haskell" },
      root_dir = util.root_pattern("*.cabal", "stack.yaml", "cabal.project", "package.yaml", "hie.yaml"),
      single_file_support = false,
      settings = {},
    },
  }
end

lspconfig.static_ls.setup({
  autostart = true,
  capabilities = nvlsp.capabilities,
  on_attach = function(client, bufnr)
    -- Enable inlay hints if supported
    if client.server_capabilities.inlayHintProvider then
      vim.lsp.inlay_hint.enable()
    end
    -- Call the default on_attach function if it exists
    if nvlsp.on_attach then
      nvlsp.on_attach(client, bufnr)
    end
  end
})
