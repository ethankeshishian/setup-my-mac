-- The command line (`:`, `/`, `?`): suggestions while typing, arrow keys and Tab in the
-- suggestion menu, and the same editing keys as the shell and Telescope.
local M = {}

local function setline(text)
  vim.fn.setcmdline(text, #text + 1)
end

-- Cmd-Z undo. Snapshots are taken at word boundaries and before bigger edits, so undo
-- steps back a word or an edit at a time rather than a character.
local snapshots, restoring = {}, false

local function record()
  if restoring then
    restoring = false
    return
  end
  local text, top = vim.fn.getcmdline(), snapshots[#snapshots]
  local typed_word_char = #text == #top + 1 and text:sub(1, #top) == top and text:sub(-1):match "[%w_]"
  if not typed_word_char then
    table.insert(snapshots, text)
  end
end

local function undo()
  local text = vim.fn.getcmdline()
  if text == snapshots[#snapshots] and #snapshots > 1 then
    table.remove(snapshots)
  end
  local previous = snapshots[#snapshots]
  if previous ~= text then
    restoring = true
    setline(previous)
  end
end

-- Tab takes the highlighted suggestion, or the first one, and adds a space so the next
-- word's suggestions start. Folders keep no space so the path can continue.
local function tab()
  local info = vim.fn.cmdcomplete_info()
  if vim.fn.wildmenumode() == 1 and info.matches and #info.matches > 0 then
    local index, keys = info.selected, ""
    if index < 0 then
      keys, index = "<C-n>", 0
    end
    keys = keys .. "<C-y>"
    if not info.matches[index + 1]:match "[/\\]$" then
      keys = keys .. " "
    end
    return keys
  end
  return "<C-z>"
end

function M.setup()
  vim.o.wildmode = "noselect:lastused,full"
  vim.o.wildoptions = "pum"
  -- Lets mappings open the suggestion menu by sending <C-z>.
  vim.cmd "set wildcharm=<C-z>"

  local group = vim.api.nvim_create_augroup("ethan_cmdline", { clear = true })
  vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = group,
    callback = function()
      snapshots, restoring = { "" }, false
    end,
  })
  vim.api.nvim_create_autocmd("CmdlineChanged", {
    group = group,
    callback = function()
      record()
      local type = vim.fn.getcmdtype()
      if type == ":" or type == "/" or type == "?" then
        vim.fn.wildtrigger()
      end
    end,
  })

  local map = function(lhs, rhs, opts)
    vim.keymap.set("c", lhs, rhs, opts or {})
  end
  -- Up/Down move through the suggestion menu while it's open, and browse history otherwise.
  map("<Down>", function() return vim.fn.wildmenumode() == 1 and "<C-n>" or "<Down>" end, { expr = true })
  map("<Up>", function() return vim.fn.wildmenumode() == 1 and "<C-p>" or "<Up>" end, { expr = true })
  map("<Tab>", tab, { expr = true })
  -- Option-Backspace deletes a word the macOS way.
  map("<M-BS>", function()
    local line, cursor = vim.fn.getcmdline(), vim.fn.getcmdpos() - 1
    local kept = require("ethan.mac_word").strip_last_word(line:sub(1, cursor))
    vim.fn.setcmdline(kept .. line:sub(cursor + 1), #kept + 1)
  end)
  -- Cmd-Backspace (Ghostty sends <C-u>) clears the whole line.
  map("<C-u>", function() setline "" end)
  -- Cmd-Z (Ghostty sends <C-_>) undoes the last edit.
  map("<C-_>", undo)
end

return M
