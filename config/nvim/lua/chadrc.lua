-- This file needs to have same structure as nvconfig.lua 
-- https://github.com/NvChad/ui/blob/v2.5/lua/nvconfig.lua

---@type ChadrcConfig
local M = {}

M.base46 = {
	theme = "ethanpuccin",

	hl_override = {
		Comment = { italic = true },
		["@comment"] = { italic = true },
	},
}

M.ui = {
	colorify = {
		enabled = true,
	},
	tabufline = {
		enabled = true,
	},
	statusline = {
		-- NvChad's default order, plus the search count before diagnostics.
		order = { "mode", "file", "git", "%=", "lsp_msg", "%=", "search", "diagnostics", "lsp", "cwd", "cursor" },
		modules = {
			-- "/foo [2/5]" (or "?foo" after a backward search) while search matches are highlighted; gone after :noh. noice hides
			-- Neovim's message line, so the count lives here instead.
			search = function()
				if vim.v.hlsearch == 0 then
					return ""
				end
				local ok, count = pcall(vim.fn.searchcount, { maxcount = 999, timeout = 50 })
				if not ok or (count.total or 0) == 0 then
					return ""
				end
				local total = count.incomplete == 2 and ">" .. count.maxcount or count.total
				local pattern = vim.fn.getreg("/"):gsub("%%", "%%%%")
				-- While typing, the prompt's own type; afterwards, the last search's direction.
				local prefix = vim.fn.getcmdtype()
				if prefix ~= "/" and prefix ~= "?" then
					prefix = vim.v.searchforward == 1 and "/" or "?"
				end
				return "%#St_LspMsg#" .. prefix .. pattern .. " [" .. count.current .. "/" .. total .. "] "
			end,
			file = function()
				local stbufnr = vim.api.nvim_win_get_buf(vim.g.statusline_winid or 0)
				local icon = "󰈚"
				local path = vim.api.nvim_buf_get_name(stbufnr)
				local name = (path == "" and "Empty") or vim.fn.fnamemodify(path, ":~:.")

				if name ~= "Empty" then
					local parts = vim.split(name, "/")
					-- keep last 3 dirs + filename intact, abbreviate the rest
					local cutoff = #parts - 4
					if cutoff > 0 then
						for i = 1, cutoff do
							if #parts[i] > 3 then
								parts[i] = parts[i]:sub(1, 3) .. "..."
							end
						end
					end
					name = table.concat(parts, "/")
				end

				if name ~= "Empty" then
					local devicons_present, devicons = pcall(require, "nvim-web-devicons")
					if devicons_present then
						local ft_icon = devicons.get_icon(path:match("([^/\\]+)[/\\]*$"))
						icon = ft_icon or icon
					end
				end

				return "%#St_file# " .. icon .. " " .. name .. " %#St_file_sep#"
			end,
		},
	},
}
-- M.nvdash = { load_on_startup = true }
-- M.ui = {
--       tabufline = {
--          lazyload = false
--      }
-- }

return M
