-- Option-Backspace like macOS text fields: skip punctuation and spaces before the cursor,
-- then delete the word before them. "a/b/c" -> "a/b/" -> "a/" -> "", "a b" -> "a " -> "".
local M = {}

-- Returns `before` with its last word, and the punctuation or spaces after it, removed.
function M.strip_last_word(before)
  local kept = before:gsub("[^%w_]*$", "")
  kept = kept:gsub("[%w_]*$", "")
  return kept
end

function M.backward_kill_word()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local kept = M.strip_last_word(vim.api.nvim_get_current_line():sub(1, col))
  vim.api.nvim_buf_set_text(0, row - 1, #kept, row - 1, col, {})
  vim.api.nvim_win_set_cursor(0, { row, #kept })
end

return M
