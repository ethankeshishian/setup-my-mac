require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")
map("i", "fp", "<ESC>")

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

-- Uncomment for Querty tmux navigation
-- vim.keymap.set('n', '<C-h>', ':TmuxNavigateLeft<CR>', { noremap = true, silent = true })
-- vim.keymap.set('n', '<C-j>', ':TmuxNavigateDown<CR>', { noremap = true, silent = true })
-- vim.keymap.set('n', '<C-k>', ':TmuxNavigateUp<CR>', { noremap = true, silent = true })
-- vim.keymap.set('n', '<C-l>', ':TmuxNavigateRight<CR>', { noremap = true, silent = true })
-- vim.keymap.set('n', '<C-\\>', ':TmuxNavigatePrevious<CR>', { noremap = true, silent = true })

-- Colemak nvim and tmux window navigation
vim.keymap.set('n', '<C-left>', ':wincmd h<CR>')
vim.keymap.set('n', '<C-down>', ':wincmd j<CR>')
vim.keymap.set('n', '<C-up>', ':wincmd k<CR>')
vim.keymap.set('n', '<C-right>', ':wincmd l<CR>')

vim.keymap.set('n', '<C-left>', ':TmuxNavigateLeft<CR>', { noremap = true, silent = true })
vim.keymap.set('n', '<C-down>', ':TmuxNavigateDown<CR>', { noremap = true, silent = true })
vim.keymap.set('n', '<C-up>', ':TmuxNavigateUp<CR>', { noremap = true, silent = true })
vim.keymap.set('n', '<C-right>', ':TmuxNavigateRight<CR>', { noremap = true, silent = true })
vim.keymap.set('n', '<C-\\>', ':TmuxNavigatePrevious<CR>', { noremap = true, silent = true })
