-- nvim-treesitter's archived `master` branch registers query handlers (is?, kind-eq?, nth?,
-- downcase!, set-lang-from-info-string!, set-lang-from-mimetype!) that expect one node per
-- capture. Neovim 0.12 always passes a list of nodes, so they crash with "attempt to call
-- method 'range'", e.g. when highlighting a markdown code block. Telescope and nvim-cmp still
-- use master's modules, so instead of moving to the `main` branch this re-registers master's
-- handlers with each capture narrowed to its last node, which is what master received before.
local M = {}

local function single_node(match)
  return setmetatable({}, {
    __index = function(_, id)
      local nodes = match[id]
      if type(nodes) == "table" then
        return nodes[#nodes]
      end
      return nodes
    end,
  })
end

local function adapt(handler)
  return function(match, ...)
    return handler(single_node(match), ...)
  end
end

function M.apply()
  if vim.fn.has "nvim-0.12" == 0 then
    return
  end
  local query = vim.treesitter.query
  local add_directive, add_predicate = query.add_directive, query.add_predicate
  query.add_directive = function(name, handler)
    add_directive(name, adapt(handler), { force = true })
  end
  query.add_predicate = function(name, handler)
    add_predicate(name, adapt(handler), { force = true })
  end
  package.loaded["nvim-treesitter.query_predicates"] = nil
  local ok, err = pcall(require, "nvim-treesitter.query_predicates")
  query.add_directive, query.add_predicate = add_directive, add_predicate
  if not ok then
    vim.notify("treesitter_compat: " .. err, vim.log.levels.WARN)
  end
end

return M
