local a = require"plenary.async"
local util = require"lean._util"

-- necessary until neovim/neovim#14661 is merged.
local _by_id = setmetatable({}, {__mode = 'v'})

--- An HTML-style div
---@class Div
---@field tags table
---@field text string
---@field name string
---@field hlgroup string
---@field hlgroup_override string
---@field divs Div[]
---@field div_stack Div[]
---@field bufs table
---@field id number
---@field highlightable boolean
---@field disabled boolean
local Div = {next_id = 1}
Div.__index = Div

function Div:new(tags, text, name, hlgroup, listener)
  local new_div = setmetatable({tags = tags or {}, text = text or "", name = name or "", hlgroup = hlgroup,
    divs = {}, div_stack = {}, listener = listener, bufs = {}, id = self.next_id}, self)
  self.next_id = self.next_id + 1
  _by_id[new_div.id] = new_div
  new_div.tags.event = new_div.tags.event or {}
  return new_div
end

function Div:add_div(div)
  table.insert(self.divs, div)
  return div
end

function Div:add_tooltip(div)
  self.divs["tt"] = div
  return div
end

function Div:insert_new_div(new_div)
  local last_div = self.div_stack[#self.div_stack]
  if last_div then
    return last_div:add_div(new_div)
  else
    return self:add_div(new_div)
  end
end

function Div:insert_new_tooltip(new_div)
  local last_div = self.div_stack[#self.div_stack]
  if last_div then
    return last_div:add_tooltip(new_div)
  else
    return self:add_tooltip(new_div)
  end
end

function Div:start_div(tags, text, name, hlgroup, listener)
  local new_div = Div:new(tags, text, name, hlgroup, listener)
  self:insert_new_div(new_div)
  table.insert(self.div_stack, new_div)
  return new_div
end

function Div:end_div()
  table.remove(self.div_stack)
end

function Div:insert_div(tags, text, name, hlgroup, listener)
  local new_div = self:start_div(tags, text, name, hlgroup, listener)
  self:end_div()
  return new_div
end

function Div:render()
  local text = self.text
  local hls = {}
  for _, div in ipairs(self.divs) do
    local new_text, new_hls = div:render()
    for _, new_hl in ipairs(new_hls) do
      new_hl.start = new_hl.start + #text
      new_hl["end"] = new_hl["end"] + #text
    end
    vim.list_extend(hls, new_hls)
    text = text .. new_text
  end
  local hlgroup = self.disabled and "htmlDivLoading" or self.hlgroup_override or self.hlgroup
  if hlgroup then
    if type(hlgroup) == "function" then
      hlgroup = hlgroup(self)
    end

    if hlgroup then
      table.insert(hls, {start = 1, ["end"] = #text, hlgroup = hlgroup, override = self.hlgroup_override})
    end
  end
  self.hlgroup_override = nil
  return text, hls
end

function Div:_pos_from_path(path)
  if #path == 0 then return 1 end
  path = {unpack(path)}

  local this_branch = table.remove(path)
  local this_name = this_branch.name
  local this_idx = this_branch.idx

  local pos = #self.text
  for idx, child in ipairs(self.divs) do
    if idx ~= this_idx then
      pos = pos + #child:render()
    else
      if child.name ~= this_name then return nil end
      local result = child:_pos_from_path(path)
      return result and pos + result
    end
  end

  return nil
end

function Div:pos_from_path(path)
  path = {unpack(path)}

  -- check that the first name matches
  if self.name ~= table.remove(path).name then return nil end

  return self:_pos_from_path(path)
end

function Div:_div_from_path(path, stack)
  table.insert(stack, self)
  if #path == 0 then return stack, self end
  path = {unpack(path)}

  local this_branch = table.remove(path)
  local this_div = self.divs[this_branch.idx]
  local this_name = this_branch.name

  if not this_div or this_div.name ~= this_name then return nil, nil end

  return this_div:_div_from_path(path, stack)
end

function Div:div_from_path(path)
  path = {unpack(path)}

  -- check that the first name matches
  if self.name ~= table.remove(path).name then return nil, nil end

  return self:_div_from_path(path, setmetatable({}, {__mode = "v"}))
end

function Div:_div_from_pos(pos, stack)
  table.insert(stack, self)

  local text = self.text

  -- base case
  if pos <= #text then return nil, stack, {} end

  local search_pos = pos - #text

  for idx, div in ipairs(self.divs) do
    local div_text, div_stack, div_path = div:_div_from_pos(search_pos, stack)
    if div_stack then
      table.insert(div_path, {idx = idx, name = div.name})
      return nil, div_stack, div_path
    end
    text = text .. div_text
    search_pos = search_pos - #div_text
  end

  table.remove(stack)
  return text, nil
end

function Div:div_from_pos(pos)
  local _, div_stack, div_path = self:_div_from_pos(pos, setmetatable({}, {__mode = "v"}))
  if div_path then table.insert(div_path, {idx = -1, name = self.name}) end
  return div_stack, div_path
end

local function _get_parent_div(div_stack, check)
  div_stack = {unpack(div_stack)}
  for i = #div_stack, 1, -1 do
    local this_div = div_stack[i]
    if check(this_div) then
      return this_div, div_stack
    end
    table.remove(div_stack)
  end
end

local function get_parent_div(div_stack, check)
  if type(check) == "string" then
    return _get_parent_div(div_stack, function(div) return div.name == check end)
  end
  return _get_parent_div(div_stack, check)
end

local function div_stack_to_path(div_stack)
  local path = {}
  for div_i, div in ipairs(div_stack) do
    local idx
    if div_i == 1 then
      idx = -1
    else
      local found = false
      for child_i, child in ipairs(div_stack[div_i-1].divs) do
        if child == div then
          idx = child_i
          found = true
          break
        end
      end
      if not found then return nil end
    end
    table.insert(path, 1, {idx = idx, name = div.name})
  end
  return path
end

local function pos_to_raw_pos(pos, lines)
  local raw_pos = 0
  for i = 1, pos[1] - 1 do
    if not lines[i] then return end
    raw_pos = raw_pos + #(lines[i]) + 1
  end
  if not lines[pos[1]] or (#lines[pos[1]] == 0 and pos[2] ~= 0) or
    (#lines[pos[1]] > 0 and pos[2] + 1 > #lines[pos[1]]) then
    return
  end
  raw_pos = raw_pos + pos[2] + 1
  return raw_pos
end

local function raw_pos_to_pos(raw_pos, lines)
  local line_num = 0
  local rem_chars = raw_pos

  for _, line in ipairs(lines) do
    line_num = line_num + 1
    if rem_chars <= (#line + 1) then break end

    rem_chars = rem_chars - (#line + 1)
  end

  return {line_num - 1, rem_chars - 1}
end

local function is_event_div_check(event_name)
  return function (div)
    if not div.tags.event then return false end
    local event = div.tags.event[event_name]
    if event then return true end
    return false
  end
end

function Div:path_from_pos(pos)
  local _, path = self:div_from_pos(pos)
  return path
end

function Div:event(path, event_name, ...)
  local div_stack, _ = self:div_from_path(path)
  if not div_stack then return end

  local event_div, event_div_stack = get_parent_div(div_stack, is_event_div_check(event_name))
  if not event_div or event_div.disabled then return end

  -- find parent listener
  local listener_div, listener_div_stack = get_parent_div(event_div_stack, function(div)
    if div.listener then return true end
    return false
  end)
  if not listener_div then return end

  -- take subpath from listener to event, inclusive
  local event_path = {}
  for i = #path - (#event_div_stack - 1), #path - (#listener_div_stack - 1) do
    table.insert(event_path, path[i])
  end

  local args = {...}

  a.void(function()
    if listener_div.call_event then
      return listener_div.call_event(event_path, event_name, event_div.tags.event[event_name], args)
    else
      return event_div.tags.event[event_name](unpack(args))
    end
  end)()
end

function Div:find(check)
  if check(self) then return self end

  for _, div in pairs(self.divs) do
    local found = div:find(check)
    if found then return found end
  end
end

function Div:filter(fn)
  fn(self)

  for _, div in pairs(self.divs) do
    div:filter(fn)
  end
end

function Div:buf_register(buf, keymaps, tooltip_data)
  self.bufs[buf] = {keymaps = keymaps, children = {}, temp_decorations = {}, tooltip_data = tooltip_data}
  util.set_augroup("DivPosition", string.format([[
    autocmd CursorMoved <buffer=%d> lua require'lean.html'._by_id[%d]:buf_update_cursor(%d)
    autocmd BufEnter <buffer=%d> lua require'lean.html'._by_id[%d]:buf_update_cursor(%d)
  ]], buf, self.id, buf, buf, self.id, buf), buf)

  local mappings = {n = {}}
  if keymaps then
    for key, event in pairs(keymaps) do
      mappings.n[key] = ([[<Cmd>lua require'lean.html'._by_id[%d]:buf_event(%d, "%s")<CR>]]):format(self.id, buf, event)
    end
    mappings.n["J"] = ([[<Cmd>lua require'lean.html'._by_id[%d]:buf_enter_tooltip(%d)<CR>]]):format(self.id, buf)
  end
  util.load_mappings(mappings, buf)
end

local div_ns = vim.api.nvim_create_namespace("LeanNvimInfo")

vim.api.nvim_command("highlight htmlDivHighlight ctermbg=153 ctermfg=0")
vim.api.nvim_command("highlight htmlDivLoading ctermfg=8")


function Div:buf_get_root(buf)
  local bufdata = self.bufs[buf]
  local root, path
  if bufdata.tooltip_data then
    local _, _root = self:div_from_path(bufdata.tooltip_data.path)
    root = _root
    path = bufdata.tooltip_data.subpath
  else
    root = self
    path = self.bufs[buf].path
  end
  return root, path
end

function Div:buf_render(buf, prevent_restore)
  local bufdata = self.bufs[buf]
  local restore_path = not prevent_restore and not bufdata.tooltip_data and bufdata.path and {unpack(bufdata.path)}

  vim.api.nvim_buf_clear_namespace(buf, div_ns, 0, -1)

  self:buf_reset(buf)

  local root, _ = self:buf_get_root(buf)

  if bufdata.temp_decorations.hovers then
    for _, hover_path in pairs(bufdata.temp_decorations.hovers) do
      local _, hover_div = self:div_from_path(hover_path)
      hover_div.hlgroup_override = "htmlDivHighlight"
    end
  end

  local text, hls = root:render()
  local lines = vim.split(text, "\n")

  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
  -- HACK: This shouldn't really do anything, but I think there's a neovim
  --       display bug. See #27 and neovim/neovim#14663. Specifically,
  --       as of NVIM v0.5.0-dev+e0a01bdf7, without this, updating a long
  --       infoview with shorter contents doesn't properly redraw.
  vim.api.nvim_buf_call(buf, vim.fn.winline)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  table.sort(hls, function(hl1, hl2)
    local range1 = (hl1["end"] - hl1.start)
    local range2 = (hl2["end"] - hl2.start)
    if range1 > range2 then
      return true
    elseif range1 == range2 then
      return hl2.override
    end
    return false
  end)

  for _, hl in ipairs(hls) do
    local start_pos = raw_pos_to_pos(hl.start, lines)
    local end_pos = raw_pos_to_pos(hl["end"], lines)
    vim.highlight.range(
      buf,
      div_ns,
      hl.hlgroup,
      start_pos,
      {end_pos[1], end_pos[2] + 1}
    )
  end

  if bufdata.temp_decorations.tooltips then
    for _, tt_path in pairs(bufdata.temp_decorations.tooltips) do
      local tt_parent_path = {unpack(tt_path)}
      table.remove(tt_parent_path, 1)
      if bufdata.tooltip_data then
        -- make it relative to the root
        for _ = 1, #bufdata.tooltip_data.path - 1 do
          table.remove(tt_parent_path)
        end
      end

      local _, tt_div = self:div_from_path(tt_path)

      local width, height = util.make_floating_popup_size(vim.split(tt_div:render(), "\n"))

      local tooltip_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(tooltip_buf, "bufhidden", "wipe")
      vim.api.nvim_buf_set_option(tooltip_buf, "modifiable", false)

      self:buf_register(tooltip_buf, bufdata.keymaps, {parent = buf, path = tt_path})
      bufdata.children[tooltip_buf] = true
      self:buf_render(tooltip_buf)

      local bufpos = raw_pos_to_pos(root:pos_from_path(tt_parent_path), vim.split(root:render(), "\n"))

      local win_options = {
        relative = "win",
        win = bufdata.last_win,
        style = "minimal",
        width = width,
        height = height,
        border = "none",
        bufpos = bufpos
      }

      local tooltip_win = vim.api.nvim_open_win(tooltip_buf, false, win_options)
      self.bufs[tooltip_buf].tooltip_data.win = tooltip_win
    end
  end

  bufdata.temp_decorations = {}

  if vim.api.nvim_get_current_buf() == buf then
    self:buf_update_position(buf)

    if restore_path then self:buf_goto_path(buf, restore_path) end
  end
end

function Div:buf_enter_tooltip(buf)
  local bufdata = self.bufs[buf]
  -- TODO choose the one with the longest matching path
  local children = {}
  for child_buf, _ in pairs(bufdata.children) do
    table.insert(children, child_buf)
  end

  if #children > 0 then
    vim.api.nvim_set_current_win(self.bufs[children[1]].tooltip_data.win)
    -- workaround for neovim/neovim#13403, as it seems this wasn't entirely resolved by neovim/neovim#14770
    vim.api.nvim_command("redraw")
    return children[1]
  end
end

function Div:buf_update_cursor(buf)
  self:buf_update_position(buf)
  if not self.disable_hover then
    self:buf_hover(buf)
  end
end

function Div:buf_update_position(buf)
  local raw_pos = pos_to_raw_pos(vim.api.nvim_win_get_cursor(0), vim.api.nvim_buf_get_lines(buf, 0, -1, true))
  local bufdata = self.bufs[buf]
  if bufdata.tooltip_data and bufdata.tooltip_data.path then
    local _, tt_div = self:div_from_path(bufdata.tooltip_data.path)

    local this_path = tt_div:path_from_pos(raw_pos)
    self.bufs[buf].tooltip_data.subpath = {unpack(this_path)}

    table.remove(this_path)
    vim.list_extend(this_path, bufdata.tooltip_data.path)
    self.bufs[buf].path = this_path
    self:buf_get_root_buf(buf, function(_, parent_bufdata) parent_bufdata.path = this_path end)
  else
    self.bufs[buf].path = self:path_from_pos(raw_pos)
  end
  bufdata.last_win = vim.api.nvim_get_current_win()
end

function Div:buf_hover(buf)
  local bufdata = self.bufs[buf]
  local root, path = self:buf_get_root(buf)

  -- make sure this path is relative to the true root
  local function to_true_path(root_path)
    if bufdata.tooltip_data then
      table.remove(root_path)
      vim.list_extend(root_path, bufdata.tooltip_data.path)
    end
  end

  local div_stack, _ = root:div_from_path(path)
  local hover_div, hover_div_stack = get_parent_div(div_stack, function (div)
    return div.highlightable
  end)
  if hover_div then
    local hover_div_path = div_stack_to_path(hover_div_stack)
    to_true_path(hover_div_path)
    bufdata.temp_decorations.hovers = {hover_div_path}
  end

  local tt_parent_div, tt_parent_div_stack = get_parent_div(div_stack, function (div) return div.divs.tt end)

  if tt_parent_div then
    local tooltip_parent_path = div_stack_to_path(tt_parent_div_stack)
    local tooltip_path = {unpack(tooltip_parent_path)}
    table.insert(tooltip_path, 1, {idx = "tt", name = tt_parent_div.divs.tt.name})
    to_true_path(tooltip_path)
    bufdata.temp_decorations.tooltips = {tooltip_path}
  end

  self:buf_render(buf, true)
end

function Div:buf_reset(buf)
  local bufdata = self.bufs[buf]
  bufdata.path = nil
  for child_buf, _ in pairs(bufdata.children) do
    local child_bufdata = self.bufs[child_buf]
    child_bufdata.tooltip_data.path = nil
    child_bufdata.tooltip_data.subpath = nil

    self:buf_reset(child_buf)

    self.bufs[child_buf] = nil
    bufdata.children[child_buf] = nil
    if vim.api.nvim_win_is_valid(child_bufdata.tooltip_data.win) then
      if vim.api.nvim_get_current_win() == child_bufdata.tooltip_data.win and
        bufdata.last_win and vim.api.nvim_win_is_valid(bufdata.last_win) then
        self.disable_hover = true
        vim.api.nvim_set_current_win(bufdata.last_win)
        self.disable_hover = false
      end
      vim.api.nvim_win_close(child_bufdata.tooltip_data.win, false)
    end
  end
end

function Div:buf_get_root_buf(buf, fn)
  local bufdata = self.bufs[buf]
  while bufdata.tooltip_data do
    buf = bufdata.tooltip_data.parent
    bufdata = self.bufs[buf]
    if fn then fn(buf, bufdata) end
  end
  return buf
end

function Div:buf_event(buf, event, ...)
  local args = {...}
  local bufdata = self.bufs[buf]
  self:event(bufdata.path, event, unpack(args))
end

function Div:buf_goto_path(buf, path)
  self:buf_reset(buf)
  local orig_window = vim.api.nvim_get_current_win()
  local orig_bufpos = vim.api.nvim_win_get_cursor(0)
  local function restore_orig()
    vim.api.nvim_set_current_win(orig_window)
    vim.api.nvim_win_set_cursor(0, orig_bufpos)
  end

  local root = self
  path = {unpack(path)}
  local inc_path = {table.remove(path)}
  if self.name ~= inc_path[1].name then restore_orig() return false end

  local prev_pos
  local function go_to()
    local bufpos = raw_pos_to_pos(prev_pos, vim.split(root:render(), "\n"))
    bufpos[1] = bufpos[1] + 1
    vim.api.nvim_win_set_cursor(0, bufpos)
    self:buf_update_cursor(buf)
  end
  while #path > 0 do
    local this_branch = table.remove(path)
    table.insert(inc_path, 1, this_branch)
    if this_branch.idx == "tt" then
      go_to()
      buf = self:buf_enter_tooltip(buf)
      if not buf then return false end
      root = self:buf_get_root(buf)
      inc_path = {this_branch}
      prev_pos = nil
    else
      local new_pos = root:pos_from_path(inc_path)
      if not new_pos then restore_orig() return false end
      prev_pos = new_pos
    end
  end
  go_to()

  return true
end

return {Div = Div, util = { get_parent_div = get_parent_div,
pos_to_raw_pos = pos_to_raw_pos, raw_pos_to_pos = raw_pos_to_pos,
is_event_div_check = is_event_div_check }, _by_id = _by_id}
