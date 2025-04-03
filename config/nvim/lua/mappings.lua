require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

-- map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")
map("i", "fp", "<ESC>")
vim.keymap.set("n", "<C-a>", "<C-i>", { noremap = true, desc = "Jump forward in jumplist" })

map("n", "<leader>fp", "<cmd>Telescope resume<CR>", { desc = "telescope resume" })
map("n", "<leader>fe", "<cmd>Telescope diagnostics<CR>", { desc = "telescope find errors" })
map("n", "<leader>fr", "<cmd>Telescope lsp_references<CR>", { desc = "telescope find references" })
map("n", "<leader>se", "<cmd>lua vim.diagnostic.open_float()<CR>", { desc = "show diagnostic error" })
map("n", "<leader>si", "<cmd>lua vim.lsp.buf.hover()<CR>", { desc = "show information" })
map("n", "gp", "<cmd>lua vim.lsp.buf.type_definition()<CR>", { desc = "LSP Go to type definition" })
map("n", "<leader>gp", "<cmd>Gitsigns nav_hunk prev<CR>", { desc = "Git Go to prev hunk" })
map("n", "<leader>gn", "<cmd>Gitsigns nav_hunk next<CR>", { desc = "Git Go to next hunk" })

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

-- Mappings to navigate out of nvim terminal
vim.keymap.set("t", "<C-left>", "<C-\\><C-n>:wincmd h<CR>")
vim.keymap.set("t", "<C-down>", "<C-\\><C-n>:wincmd j<CR>")
vim.keymap.set("t", "<C-up>", "<C-\\><C-n>:wincmd k<CR>")
vim.keymap.set("t", "<C-right>", "<C-\\><C-n>:wincmd l<CR>")
