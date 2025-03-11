return {
  "neoclide/coc.nvim",
  branch = "release",
  lazy = false,
  config = function()
    vim.cmd([[
      " Navigation mappings
      nmap <silent><nowait> gd <Plug>(coc-definition)
      nmap <silent><nowait> gy <Plug>(coc-type-definition)
      nmap <silent><nowait> gi <Plug>(coc-implementation)
      nmap <silent><nowait> gr <Plug>(coc-references)
      
      " Code actions
      nmap <leader>cr <Plug>(coc-rename)
      nmap <leader>cf <Plug>(coc-format-selected)
      vmap <leader>cf <Plug>(coc-format-selected)
      nmap <leader>ca <Plug>(coc-codeaction-selected)
      vmap <leader>ca <Plug>(coc-codeaction-selected)
    ]])
  end,
}
