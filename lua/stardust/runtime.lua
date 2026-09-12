local api, uv = vim.api, vim.uv
local layout = require('stardust.layout')
local sky = require('stardust.sky')
local palette = require('stardust.palette')
local M = {}

local stars_ns = api.nvim_create_namespace('stardust.stars')
local canvas_ns = api.nvim_create_namespace('stardust.canvas')
local state = { active = false, contexts = {}, canvases = {}, attached = {}, request = 0 }

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
    -- Clearing decorations after an edit must not kill a flight.
    state.canvases[buf].id = nil
  end
end

local function clear_canvases()
  for buf in pairs(state.canvases) do
    clear_canvas(buf)
  end
end

local function any_enabled()
  local cfg = state.cfg
  return cfg.stars > 0 or cfg.meteors > 0 or cfg.showers > 0 or #cfg.objects > 0
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
  if not state.active then
    return false
  end
  local ok, err = pcall(function()
    local ctx = state.contexts[win]
    if not ctx or ctx.buf ~= buf then
      return
    end
    -- Re-evaluate occupancy during every redraw, including edits between ticks.
    local view = layout.get(win, buf, ctx.cache, canvas_ns, state.cfg.floating_windows)
    local canvas = state.canvases[buf]
    local previous = canvas and canvas.views[win]
    if
      canvas
      and (
        not view
        or not previous
        or view.top ~= previous.top
        or view.free ~= previous.free
        or view.width ~= previous.width
      )
    then
      -- WinScrolled is delivered after the command returns. Clear an obsolete
      -- EOF block during this redraw too, before that deferred event/timer.
      clear_canvas(buf)
    end
    if not view then
      return
    end
    for _, cell in ipairs(sky.frame(ctx.scene or ctx.sky, view, state.cfg, state.palette)) do
      if vim.fn.strdisplaywidth(cell.glyph) == 1 then
        api.nvim_buf_set_extmark(buf, stars_ns, view.rows[cell.y].line, view.rows[cell.y].col, {
          ephemeral = true,
          virt_text = { { cell.glyph, cell.hl } },
          virt_text_win_col = cell.x,
          virt_text_pos = 'overlay',
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

local function paint_canvas(buf, canvas, view, offset)
  local rows = {}
  for i = 1, view.height - offset do
    rows[i] = {}
  end
  for _, cell in ipairs(sky.frame(canvas.sky, view, state.cfg, state.palette)) do
    if cell.y > offset and vim.fn.strdisplaywidth(cell.glyph) == 1 then
      local row = rows[cell.y - offset]
      row[#row + 1] = cell
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
  if not any_enabled() then
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
    local group = groups[buf]
      or { width = math.huge, height = math.huge, visible = false, views = {}, contexts = {} }
    groups[buf] = group
    local ctx = context(win, buf)
    ctx.visible = visible[win] or false
    local view, reason = layout.get(win, buf, ctx.cache, canvas_ns, state.cfg.floating_windows)
    ctx.reason, ctx.layout = reason, view
    seen[win] = true
    if view then
      attach(buf)
      group.views[#group.views + 1] = view
      group.contexts[#group.contexts + 1] = ctx
      group.width = math.min(group.width, view.width)
      group.height = math.min(group.height, view.free)
      group.visible = group.visible or visible[win]
      -- A stored EOF canvas cannot have different screen origins in two views.
      if group.top and (group.top ~= view.top or group.rows ~= view.height) then
        group.height = 0
      end
      group.top, group.rows = view.top, view.height
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
    if not groups[buf] or not groups[buf].visible or groups[buf].height <= 0 then
      clear_canvas(buf, true)
    end
  end
  for buf, group in pairs(groups) do
    if group.visible and group.height > 0 then
      local canvas = state.canvases[buf]
      if not canvas then
        local ctx = group.contexts[1]
        canvas = { sky = ctx.scene or ctx.sky }
        state.canvases[buf] = canvas
      end
      local view = layout.scene(group.views, group.height, group.width)
      canvas.views = {}
      for _, visible_view in ipairs(group.views) do
        canvas.views[visible_view.win] = visible_view
      end
      for _, ctx in ipairs(group.contexts) do
        ctx.scene = canvas.sky
      end
      sky.step(canvas.sky, view, state.cfg, dt, #state.palette.stars)
      paint_canvas(buf, canvas, view, group.views[1].height)
    else
      for _, ctx in ipairs(group.contexts) do
        if ctx.scene then
          -- Splits can stop sharing their canvas after scrolling or resizing.
          -- Preserve each flight, but give the resulting views independent time.
          ctx.sky, ctx.scene = vim.deepcopy(ctx.scene), nil
        end
        if ctx.visible then
          sky.step(ctx.sky, ctx.layout, state.cfg, dt, #state.palette.stars)
        end
      end
    end
  end
end

local queue_frame
queue_frame = function(delay)
  state.request = state.request + 1
  local request = state.request
  state.timer:start(delay, 0, function()
    vim.schedule(function()
      if not state.active or request ~= state.request then
        return
      end
      local started = now()
      local dt = math.max(0, started - state.last)
      state.last = started
      local ok, err = pcall(M.step, dt)
      if not ok then
        fail(err)
        return
      end
      redraw()
      -- One pending frame, including after scrolls and restarts. Rendering
      -- time counts toward the budget; a busy editor never builds a backlog.
      if state.active and request == state.request then
        queue_frame(math.max(1, math.ceil(1000 / state.cfg.fps - (now() - started) * 1000)))
      end
    end)
  end)
end

function M.start(cfg)
  if state.active then
    return
  end
  state.cfg, state.palette = cfg, palette.setup(cfg)
  state.active, state.contexts = true, {}
  state.request = state.request + 1
  api.nvim_set_decoration_provider(stars_ns, { on_win = render_window })
  local group = api.nvim_create_augroup('StardustRuntime', { clear = true })
  local function refresh_palette()
    state.palette = palette.setup(state.cfg)
    if any_enabled() then
      queue_frame(0)
    end
  end
  api.nvim_create_autocmd('ColorScheme', { group = group, callback = refresh_palette })
  api.nvim_create_autocmd(
    'OptionSet',
    { group = group, pattern = 'background', callback = refresh_palette }
  )
  api.nvim_create_autocmd(
    { 'WinScrolled', 'WinResized', 'WinNew', 'WinClosed', 'BufWinEnter', 'BufWinLeave', 'TabEnter' },
    {
      group = group,
      callback = function()
        if state.active and any_enabled() then
          queue_frame(0)
        end
      end,
    }
  )
  api.nvim_create_autocmd('VimLeavePre', { group = group, callback = M.stop })
  state.timer = assert(uv.new_timer(), 'stardust: could not create animation timer')
  state.last = now()
  if any_enabled() then
    queue_frame(0)
  end
end

function M.stop()
  state.active = false
  state.request = state.request + 1
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
  local time = now()
  M.step(math.max(0, time - state.last))
  state.last = time
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local canvas, ctx = state.canvases[buf], state.contexts[win]
  local function attempt(scene, view)
    if not view then
      return false
    end
    if kind == 'meteor' or kind == 'shower' or kind == 'battle' then
      return sky[kind](scene, view, state.cfg)
    end
    return sky.object(scene, view, state.cfg, kind)
  end
  local spawned
  if canvas then
    spawned = attempt(canvas.sky, canvas.layout)
  else
    spawned = ctx and attempt(ctx.sky, ctx.layout) or false
  end
  if spawned then
    queue_frame(0)
  end
  return spawned
end

for _, kind in ipairs({ 'meteor', 'shower', 'battle' }) do
  M[kind] = function()
    return spawn(kind)
  end
end

function M.object(kind)
  return spawn(kind)
end

function M.status()
  local result = {
    active = state.active,
    windows = 0,
    stars = 0,
    objects = 0,
    showers = 0,
    battles = 0,
    canvases = 0,
    skipped = {},
    fps = state.active and state.cfg.fps or 0,
  }
  local counted = {}
  for win, ctx in pairs(state.contexts) do
    if ctx.visible then
      if ctx.layout then
        result.windows = result.windows + 1
      else
        result.skipped[win] = ctx.reason
      end
    end
    local scene = ctx.scene or ctx.sky
    if ctx.visible and not counted[scene] then
      result.stars = result.stars + #scene.stars
      result.objects = result.objects + (scene.object and 1 or 0)
      result.showers = result.showers + (scene.shower and 1 or 0)
      result.battles = result.battles + (scene.object and scene.object.battle and 1 or 0)
      counted[scene] = true
    end
  end
  for _, canvas in pairs(state.canvases) do
    result.canvases = result.canvases + (canvas.id and 1 or 0)
  end
  return result
end

return M
