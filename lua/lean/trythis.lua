local DiagnosticSeverity = require('vim.lsp.protocol').DiagnosticSeverity
local trythis = {}

local function suggestions_from(diagnostic)
  local trimmed = diagnostic.message:gsub('^.-Try this:%s*', '')
  return vim.gsplit(trimmed, 'Try this:')
end

--- Swap the first suggestion from Lean with the word under the cursor.
--
--  Doesn't do any robust error checking, or allow rotating for later results
--  yet.
function trythis.swap()
  local diagnostics = vim.lsp.diagnostic.get_line_diagnostics(
    0, nil, { severity = DiagnosticSeverity.Information }
  )
  for _, diagnostic in ipairs(diagnostics) do
    -- luacheck: ignore
    for each in suggestions_from(diagnostic) do
      local command = "normal! ciw" .. vim.trim(each)
      vim.api.nvim_command(command)
      return
    end
  end
end

return trythis
