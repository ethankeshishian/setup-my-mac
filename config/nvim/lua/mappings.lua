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
map("n", "<leader>fk", "<cmd>Telescope keymaps<CR>", { desc = "telescope find keymaps" })
map("n", "<leader>fs", function()
  local p = require("telescope.actions.state")
              .get_current_picker(vim.api.nvim_get_current_buf())
  if p then
    require("telescope.actions").close(p.prompt_bufnr)
  end
  vim.cmd("Telescope pickers")
end, { desc = "telescope find pickers (refresh)" })
map("n", "<leader>se", "<cmd>lua vim.diagnostic.open_float()<CR>", { desc = "show diagnostic error" })
map("n", "<leader>si", function()
  vim.lsp.buf.hover({
    border = "single",
    focus = false,
    silent = true,
    max_height = 7
  })
end, { desc = "show information" })
map("n", "gp", "<cmd>lua vim.lsp.buf.type_definition()<CR>", { desc = "LSP Go to type definition" })
map("n", "<leader>gp", "<cmd>Gitsigns nav_hunk prev<CR>", { desc = "Git Go to prev hunk" })
map("n", "<leader>gn", "<cmd>Gitsigns nav_hunk next<CR>", { desc = "Git Go to next hunk" })
map("n", "<leader>gu", "<cmd>Gitsigns reset_hunk<CR>", { desc = "Git Reset hunk" })

map("n", "<leader>S", "<cmd>vsplit<CR>", { desc = "Vertical split" })
map("n", "<leader>X", "<cmd>close<CR>", { desc = "Close current split" })

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

vim.keymap.set("n", "<C-left>", ":wincmd h<CR>")
vim.keymap.set("n", "<C-down>", ":wincmd j<CR>")
vim.keymap.set("n", "<C-up>", ":wincmd k<CR>")
vim.keymap.set("n", "<C-right>", ":wincmd l<CR>")

vim.keymap.set("n", "<C-left>", ":TmuxNavigateLeft<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<C-down>", ":TmuxNavigateDown<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<C-up>", ":TmuxNavigateUp<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<C-right>", ":TmuxNavigateRight<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<C-\\>", ":TmuxNavigatePrevious<CR>", { noremap = true, silent = true })

-- Mappings to navigate out of nvim terminal
vim.keymap.set("t", "<C-left>", "<C-\\><C-n>:wincmd h<CR>")
vim.keymap.set("t", "<C-down>", "<C-\\><C-n>:wincmd j<CR>")
vim.keymap.set("t", "<C-up>", "<C-\\><C-n>:wincmd k<CR>")
vim.keymap.set("t", "<C-right>", "<C-\\><C-n>:wincmd l<CR>")

-- map("n", "<leader>gm", "<C-w>h", { desc = "switch window left" })
-- map("n", "<leader>gn", "<C-w>j", { desc = "switch window down" })
-- map("n", "<leader>ge", "<C-w>k", { desc = "switch window up" })
-- map("n", "<leader>gi", "<C-w>l", { desc = "switch window right" })

-- Coc keybindings

map("i", "<M-BS>", function() require("ethan.mac_word").backward_kill_word() end, { desc = "delete word before cursor, macOS style" })
map("n", "<leader>cp", ":let @+=expand('%')<CR>", { noremap = true, desc = "Copy current file path to clipboard" })
map("n", "<leader>ca", "<cmd>lua vim.lsp.buf.code_action()<CR>", { desc = "LSP code actions" })
