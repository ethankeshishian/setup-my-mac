-- Enter in normal or visual mode labels the matches of what you type next; type a label to jump.
-- Also works after an operator: d<Enter> deletes up to the jump. `s`, f/t and / are unchanged.
local function jump()
  -- Quickfix, help, terminal and other special buffers keep Enter's usual meaning.
  if vim.bo.buftype ~= "" or vim.fn.getcmdwintype() ~= "" then
    vim.api.nvim_feedkeys(vim.keycode "<CR>", "n", false)
    return
  end
  require("flash").jump()
end

return {
  "folke/flash.nvim",
  event = "VeryLazy",
  opts = {
    modes = {
      -- Leave f, F, t and T as plain Vim motions.
      char = { enabled = false },
    },
  },
  keys = {
    { "<CR>", jump, mode = { "n", "x", "o" }, desc = "Flash jump" },
  },
}
