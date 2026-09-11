local api, uv = vim.api, vim.uv
local layout = require('stardust.layout')
local sky = require('stardust.sky')
local palette = require('stardust.palette')
local M = {}

local stars_ns = api.nvim_create_namespace('stardust.stars')
local canvas_ns = api.nvim_create_namespace('stardust.canvas')
local state =
  { active = false, focused = true, contexts = {}, canvases = {}, attached = {}, generation = 0 }

local function now()
  return uv.hrtime() / 1e9
end

local function redraw()
  -- Public redraw command, scheduled outside decoration callbacks.
  vim.cmd('redraw!')
end

local function clear_canvas(buf, forget)
  if api.nvim_buf_is_valid(buf) then
    api.nvim_buf_clear_namespace(buf, canvas_ns, 0, -1)
  end
  if forget then
    state.canvases[buf] = nil
  elseif state.canvases[buf] then
    -- Clearing decorations after an edit or mode change must not kill a flight.
    state.canvases[buf].id = nil
  end
end

local function clear_canvases()
  for buf in pairs(state.canvases) do
    clear_canvas(buf)
  end
end

local function paused()
  if not state.focused and state.cfg.pause_on_focus_lost then
    return true
  end
  -- Popups render above extmarks. Avoid decorating the text in select,
  -- visual and command-line modes; terminal input keeps every window animated.
  return api.nvim_get_mode().mode:match('^[vVsS\22\19cR]') ~= nil
end

local function any_enabled()
  for _, enabled in pairs(state.cfg.enabled) do
    if enabled then
      return true
    end
  end
  return false
end

local function attach(buf)
  if state.attached[buf] then
    return
  end
  state.attached[buf] = api.nvim_buf_attach(buf, false, {
    on_lines = function(_, changed)
      if not state.active then
        state.attached[changed] = nil
        return true
      end
      -- Runs with the edit, before redraw: a previous EOF canvas must never
      -- remain in the middle of newly inserted text, even between timer ticks.
      clear_canvas(changed)
    end,
    on_reload = function(_, changed)
      clear_canvas(changed)
    end,
    on_detach = function(_, changed)
      state.attached[changed], state.canvases[changed] = nil, nil
    end,
  })
end

local function context(win, buf)
  local ctx = state.contexts[win]
  if not ctx or ctx.buf ~= buf then
    ctx = { buf = buf, cache = {}, sky = sky.new(uv.hrtime() % 2147483646 + win) }
    state.contexts[win] = ctx
  end
  return ctx
end

local function fail(err)
  if state.failing then
    return
  end
  state.failing = true
  vim.schedule(function()
    M.stop()
    state.failing = false
    vim.notify('Stardust stopped: ' .. tostring(err), vim.log.levels.ERROR)
  end)
end

local function render_window(_, win, buf)
  if not state.active or paused() then
    return false
  end
  local ok, err = pcall(function()
    local ctx = state.contexts[win]
    if not ctx or ctx.buf ~= buf then
      return
    end
    -- Re-evaluate occupancy during every redraw, including edits between ticks.
    local view = layout.get(win, buf, state.cfg, ctx.cache, canvas_ns)
    if not view then
      return
    end
    for _, cell in ipairs(sky.frame(ctx.sky, view, state.cfg, state.palette)) do
      if vim.fn.strdisplaywidth(cell.glyph) == 1 then
        api.nvim_buf_set_extmark(buf, stars_ns, view.rows[cell.y].line, 0, {
          ephemeral = true,
          virt_text = { { cell.glyph, cell.hl } },
          virt_text_win_col = cell.x,
          virt_text_pos = 'overlay',
          virt_text_hide = true,
          hl_mode = 'combine',
          priority = 1,
        })
      end
    end
  end)
  if not ok then
    fail(err)
  end
  return false
end

local function paint_canvas(buf, canvas, view, dt)
  sky.step(canvas.sky, view, state.cfg, dt, #state.palette.stars)
  local rows = {}
  for i = 1, view.height do
    rows[i] = {}
  end
  for _, cell in ipairs(sky.frame(canvas.sky, view, state.cfg, state.palette)) do
    if vim.fn.strdisplaywidth(cell.glyph) == 1 then
      rows[cell.y][#rows[cell.y] + 1] = cell
    end
  end
  local lines = {}
  for i, cells in ipairs(rows) do
    table.sort(cells, function(a, b)
      return a.x < b.x
    end)
    local chunks, column = {}, 0
    for _, cell in ipairs(cells) do
      if cell.x > column then
        chunks[#chunks + 1] = { string.rep(' ', cell.x - column) }
      end
      chunks[#chunks + 1] = { cell.glyph, cell.hl }
      column = cell.x + 1
    end
    lines[i] = #chunks > 0 and chunks or { { '' } }
  end
  canvas.id = api.nvim_buf_set_extmark(buf, canvas_ns, api.nvim_buf_line_count(buf) - 1, 0, {
    id = canvas.id,
    virt_lines = lines,
    priority = 1,
    right_gravity = true,
  })
  canvas.layout = view
end

function M.step(dt)
  if not state.active then
    return
  end
  if paused() or not any_enabled() then
    clear_canvases()
    return
  end
  local seen, groups = {}, {}
  local current_tab = api.nvim_get_current_tabpage()
  local visible = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(current_tab)) do
    visible[win] = true
  end
  -- Persistent EOF lines are buffer-scoped. Account for every view, including
  -- other tabs: only create a canvas when all views can safely accommodate it.
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf = api.nvim_win_get_buf(win)
    local group = groups[buf] or { width = math.huge, height = math.huge, visible = false }
    groups[buf] = group
    local ctx = context(win, buf)
    ctx.visible = visible[win] or false
    local view, reason = layout.get(win, buf, state.cfg, ctx.cache, canvas_ns)
    ctx.reason, ctx.layout = reason, view
    seen[win] = true
    if view then
      attach(buf)
      group.width = math.min(group.width, view.width)
      group.height = math.min(group.height, view.free)
      group.visible = group.visible or visible[win]
      if visible[win] then
        sky.step(ctx.sky, view, state.cfg, dt, #state.palette.stars)
      end
    else
      group.height = 0
    end
  end
  for win in pairs(state.contexts) do
    if not seen[win] then
      state.contexts[win] = nil
    end
  end
  for buf in pairs(state.canvases) do
    if
      not groups[buf]
      or not groups[buf].visible
      or groups[buf].height <= 0
      or not state.cfg.below_eof
    then
      clear_canvas(buf, true)
    end
  end
  if state.cfg.below_eof then
    for buf, group in pairs(groups) do
      if group.visible and group.height > 0 then
        local canvas = state.canvases[buf]
        if not canvas then
          canvas = { sky = sky.new(uv.hrtime() % 2147483646 + buf * 97) }
          state.canvases[buf] = canvas
        end
        paint_canvas(buf, canvas, layout.empty(group.width, group.height, state.cfg.margin), dt)
      end
    end
  end
end

local function pulse(generation)
  if not state.active or generation ~= state.generation then
    return
  end
  local time = now()
  local dt = math.min(0.25, time - state.last)
  state.last = time
  local ok, err = pcall(M.step, dt)
  if not ok then
    fail(err)
    return
  end
  if not paused() then
    redraw()
  end
end

local function timer_start()
  if not state.timer or not state.active or not any_enabled() then
    return
  end
  state.last = now()
  local generation = state.generation
  state.timer:start(0, math.floor(1000 / state.cfg.fps), function()
    -- At most one pending callback: a busy editor must not accumulate frames.
    if state.pending == generation then
      return
    end
    state.pending = generation
    vim.schedule(function()
      if state.pending == generation then
        state.pending = nil
      end
      pulse(generation)
    end)
  end)
end

function M.start(cfg)
  if state.active then
    return
  end
  state.cfg, state.palette = cfg, palette.setup(cfg)
  state.active, state.focused, state.contexts = true, true, {}
  state.generation = state.generation + 1
  state.pending = nil
  api.nvim_set_decoration_provider(stars_ns, { on_win = render_window })
  local group = api.nvim_create_augroup('StardustRuntime', { clear = true })
  api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      state.palette = palette.setup(state.cfg)
      clear_canvases()
    end,
  })
  api.nvim_create_autocmd('FocusLost', {
    group = group,
    callback = function()
      state.focused = false
      if cfg.pause_on_focus_lost then
        state.timer:stop()
        clear_canvases()
        redraw()
      end
    end,
  })
  api.nvim_create_autocmd('FocusGained', {
    group = group,
    callback = function()
      state.focused = true
      timer_start()
    end,
  })
  api.nvim_create_autocmd(
    { 'ModeChanged', 'WinResized', 'WinNew', 'WinClosed', 'BufWinEnter', 'BufWinLeave', 'TabEnter' },
    {
      group = group,
      callback = clear_canvases,
    }
  )
  api.nvim_create_autocmd('VimLeavePre', { group = group, callback = M.stop })
  state.timer = assert(uv.new_timer(), 'stardust: could not create animation timer')
  timer_start()
end

function M.stop()
  state.active = false
  state.generation = state.generation + 1
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  api.nvim_set_decoration_provider(stars_ns, {})
  clear_canvases()
  state.canvases = {}
  state.contexts = {}
  pcall(api.nvim_del_augroup_by_name, 'StardustRuntime')
  redraw()
end

local function spawn(kind)
  if not state.active then
    return false
  end
  M.step(0)
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local canvas, ctx = state.canvases[buf], state.contexts[win]
  local function attempt(scene, view)
    if not view then
      return false
    end
    if kind == 'meteor' then
      return sky.meteor(scene, view, state.cfg)
    end
    return sky.object(scene, view, state.cfg, kind)
  end
  if canvas and attempt(canvas.sky, canvas.layout) then
    return true
  end
  return ctx and attempt(ctx.sky, ctx.layout) or false
end

function M.meteor()
  return spawn('meteor')
end

function M.object(kind)
  return spawn(kind)
end

function M.status()
  local result = {
    active = state.active,
    paused = state.active and paused() or false,
    windows = 0,
    stars = 0,
    objects = 0,
    canvases = 0,
    skipped = {},
  }
  for win, ctx in pairs(state.contexts) do
    if ctx.visible then
      if ctx.layout then
        result.windows = result.windows + 1
      else
        result.skipped[win] = ctx.reason
      end
    end
    result.stars = result.stars + #ctx.sky.stars
    result.objects = result.objects + (ctx.sky.object and 1 or 0)
  end
  for _, canvas in pairs(state.canvases) do
    result.canvases = result.canvases + (canvas.id and 1 or 0)
    result.stars = result.stars + #canvas.sky.stars
    result.objects = result.objects + (canvas.sky.object and 1 or 0)
  end
  return result
end

return M
