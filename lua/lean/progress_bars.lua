local progress_bars = {}
local options = { _DEFAULTS = { priority = 10, character = '┋' } }

local progress_sign = 'leanSignProgress'
local sign_ns = 'leanSignProgress'

---@class LspPosition
---@field line integer
---@field character integer

---@class LspRange
---@field start LspPosition
---@field end LspPosition

---@class LeanFileProgressProcessingInfo
---@field range LspRange

---@class VersionedTextDocumentIdentifier
---@field uri string
---@field version integer

---@class LeanFileProgressParams
---@field textDocument VersionedTextDocumentIdentifier
---@field processing LeanFileProgressProcessingInfo[]

--- Table from bufnr to current processing info.
---@type table<number, LeanFileProgressProcessingInfo[]>
local proc_infos = {}

--- Updates the signs according to the ranges in proc_infos.
---@param bufnr number
local function update(bufnr)
  vim.fn.sign_unplace(sign_ns, { buffer = bufnr })
  for _, proc_info in ipairs(proc_infos[bufnr]) do
    local start_line = proc_info.range.start.line + 1
    local end_line = proc_info.range['end'].line + 1
    for line = start_line, end_line do
      vim.fn.sign_place(0, sign_ns, progress_sign, bufnr, {
        lnum = line,
        priority = options.priority,
      })
    end
  end
end

--- Table from bufnr to timer object.
---@type table<number, any>
local timers = {}

---@param params LeanFileProgressParams
local function on_file_progress(err, _, params, _, _, _)
  if err ~= nil then return end
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  proc_infos[bufnr] = params.processing
  if timers[bufnr] == nil then
    timers[bufnr] = vim.defer_fn(function ()
      timers[bufnr] = nil
      update(bufnr)
    end, 100)
  end
end

function progress_bars.enable(opts)
  options = vim.tbl_extend("force", options._DEFAULTS, opts)
  vim.fn.sign_define(progress_sign, {
    text = options.character,
    texthl = 'leanSignProgress',
  })
  vim.cmd[[ hi def leanSignProgress guifg=orange ctermfg=215 ]]
  vim.lsp.handlers['$/lean/fileProgress'] = on_file_progress
end

return progress_bars
