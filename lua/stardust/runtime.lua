local api, uv = vim.api, vim.uv
local layout = require('stardust.layout')
local sky = require('stardust.sky')
local palette = require('stardust.palette')
local M = {}

local stars_ns = api.nvim_create_namespace('stardust.stars')
local canvas_ns = api.nvim_create_namespace('stardust.canvas')
local state =
  { active = false, contexts = {}, canvases = {}, attached = {}, spans = {}, request = 0, tick = 0 }
local widths = {}
-- Row positions are rescanned at least this often even when nothing seems to
-- have changed, for the few things the fingerprint cannot see.
local RESCAN_NS = 1e9

local function now()
  return uv.hrtime() / 1e9
end

-- Only single-cell glyphs can be overlaid one per cell. Widths never change
-- for a glyph unless 'ambiwidth' does, which empties this cache.
local function narrow(glyph)
  local width = widths[glyph]
  if width == nil then
    width = vim.fn.strdisplaywidth(glyph) == 1
    widths[glyph] = width
  end
  return width
end

-- Redraws stay as small as possible: line ranges are marked without drawing,
-- then one flush per tick draws them all and writes the terminal once.
-- Nothing clears the screen or touches lines, statuslines, and other
-- plugins' decorations that did not change.
local redraw_api = api.nvim__redraw

local function redraw_lines(win, first, last)
  if redraw_api then
    redraw_api({ win = win, range = { first, last + 1 }, flush = false })
  end
end

local function flush()
  if redraw_api then
    redraw_api({ flush = true })
  else
    vim.cmd('redraw!')
  end
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
    ctx = { buf = buf, shown = {}, sky = sky.new(uv.hrtime() % 2147483646 + win) }
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

-- One frame of a window, grouped by buffer line. Each line carries a
-- signature of its cells so a later frame can tell exactly which lines
-- changed. The frame belongs to the tick it was built on: skies only move in
-- step() and spawn(), and both advance the tick.
local function build_frame(ctx, view)
  local lines = {}
  for _, cell in ipairs(sky.frame(ctx.scene or ctx.sky, view, state.cfg, state.palette)) do
    if narrow(cell.glyph) then
      local row = view.rows[cell.y]
      if row and row.line then
        local entry = lines[row.line]
        if not entry then
          entry = { col = row.col, cells = {}, sig = '' }
          lines[row.line] = entry
        end
        entry.cells[#entry.cells + 1] = cell
        entry.sig = entry.sig .. cell.x .. cell.glyph .. cell.hl .. ';'
      end
    end
  end
  ctx.frame =
    { view = view, tick = state.tick, lines = lines, stamp = view.stamp, free = view.free }
  return lines
end

-- Lines whose cells differ from what the window last drew. `shown` is
-- updated in advance; on_line corrects it for every line Neovim actually
-- draws, so a line inside a closed fold or a redraw deferred to a later
-- flush never leaves the two out of step.
local function changed_lines(ctx, lines)
  local view, shown = ctx.layout, ctx.shown
  local first, last
  local function mark(line)
    if not first or line < first then
      first = line
    end
    if not last or line > last then
      last = line
    end
  end
  for line, entry in pairs(lines) do
    if shown[line] ~= entry.sig then
      mark(line)
      shown[line] = entry.sig
    end
  end
  local top, bottom = view.top - 1, view.bottom - 1
  for line in pairs(shown) do
    if line < top or line > bottom then
      -- Scrolled out of view: whatever it showed left the screen with it.
      shown[line] = nil
    elseif not lines[line] then
      mark(line)
      shown[line] = nil
    end
  end
  return first, last
end

local function render_window(_, win, buf, topline)
  if not state.active then
    return false
  end
  local ctx = state.contexts[win]
  if not ctx or ctx.buf ~= buf then
    return false
  end
  local ok, err = pcall(function()
    local frame = ctx.frame
    local view = frame and frame.view
    if
      frame
      and frame.tick == state.tick
      and view.top == topline + 1
      and view.tick == api.nvim_buf_get_changedtick(buf)
      and view.win_width == api.nvim_win_get_width(win)
      and view.win_height == api.nvim_win_get_height(win)
    then
      -- Same text and geometry as the tick. Virtual text from other plugins
      -- can still appear between ticks, so its occupancy is re-checked.
      if layout.occupy(view, buf, canvas_ns) == frame.stamp then
        return
      end
      if state.canvases[buf] and view.free ~= frame.free then
        clear_canvas(buf)
      end
      build_frame(ctx, view)
      return
    end
    -- Re-evaluate everything for a redraw between ticks: an edit, scroll, or
    -- resize since the frame was built.
    view = layout.get(win, buf, canvas_ns, state.cfg.floating_windows)
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
    if view then
      ctx.layout = view
      build_frame(ctx, view)
    else
      ctx.frame = nil
    end
  end)
  if not ok then
    fail(err)
    return false
  end
  return ctx.frame ~= nil
end

local function render_line(_, win, buf, row)
  local ctx = state.contexts[win]
  local frame = ctx and ctx.frame
  if not frame then
    return
  end
  local requested = state.spans[buf]
  if not requested or row < requested[1] or row > requested[2] then
    -- Something other than this plugin redrew the line: a cursorline move, a
    -- fold, a setting. The next tick rescans the window instead of trusting
    -- the cached row positions.
    ctx.rescan = true
  end
  local entry = frame.lines[row]
  if not entry then
    ctx.shown[row] = nil
    return
  end
  local ok, err = pcall(function()
    for _, cell in ipairs(entry.cells) do
      api.nvim_buf_set_extmark(buf, stars_ns, row, entry.col, {
        ephemeral = true,
        virt_text = { { cell.glyph, cell.hl } },
        virt_text_win_col = cell.x,
        virt_text_pos = 'overlay',
        hl_mode = 'combine',
        priority = 1,
      })
    end
  end)
  if ok then
    ctx.shown[row] = entry.sig
  else
    fail(err)
  end
end

local function paint_canvas(buf, canvas, view, offset)
  local rows = {}
  for i = 1, view.height - offset do
    rows[i] = {}
  end
  for _, cell in ipairs(sky.frame(canvas.sky, view, state.cfg, state.palette)) do
    if cell.y > offset and narrow(cell.glyph) then
      local row = rows[cell.y - offset]
      row[#row + 1] = cell
    end
  end
  local lines, sigs = {}, {}
  for i, cells in ipairs(rows) do
    table.sort(cells, function(a, b)
      return a.x < b.x
    end)
    local chunks, column, sig = {}, 0, ''
    for _, cell in ipairs(cells) do
      if cell.x > column then
        chunks[#chunks + 1] = { string.rep(' ', cell.x - column) }
      end
      chunks[#chunks + 1] = { cell.glyph, cell.hl }
      column = cell.x + 1
      sig = sig .. cell.x .. cell.glyph .. cell.hl .. ';'
    end
    lines[i] = #chunks > 0 and chunks or { { '' } }
    sigs[i] = sig
  end
  canvas.layout = view
  local sig = table.concat(sigs, '\n')
  if canvas.id and canvas.sig == sig then
    return false
  end
  canvas.id = api.nvim_buf_set_extmark(buf, canvas_ns, api.nvim_buf_line_count(buf) - 1, 0, {
    id = canvas.id,
    virt_lines = lines,
    priority = 1,
    right_gravity = true,
  })
  canvas.sig = sig
  return true
end

function M.step(dt)
  if not state.active then
    return
  end
  -- Incremental search and substitute previews are drawn with a temporary
  -- pattern that a redraw from anywhere else throws away until the next
  -- keystroke restores it. Ticking at full speed would make every match
  -- flicker, so the sky holds still while a command line is being typed.
  -- Redraws Neovim starts itself still show the current frame.
  if api.nvim_get_mode().mode:sub(1, 1) == 'c' then
    return
  end
  state.tick = state.tick + 1
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
    local view, reason = ctx.layout, nil
    if
      view
      and not ctx.rescan
      and uv.hrtime() - view.scanned < RESCAN_NS
      and layout.fresh(win, buf, view)
    then
      -- Same text and geometry: keep the row positions, re-check virtual text.
      layout.occupy(view, buf, canvas_ns)
    else
      view, reason = layout.get(win, buf, canvas_ns, state.cfg.floating_windows)
    end
    ctx.reason, ctx.layout, ctx.rescan = reason, view, nil
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
  local changed = false
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
      if paint_canvas(buf, canvas, view, group.views[1].height) then
        changed = true
      end
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
  -- Draw the tick: every visible view gets a fresh frame, and only lines
  -- whose cells changed since the last draw are redrawn. Neovim redraws a
  -- range in every window showing the buffer, so every frame is ready
  -- before the flush.
  local pending = {}
  for win, ctx in pairs(state.contexts) do
    if ctx.visible and ctx.layout then
      local first, last = changed_lines(ctx, build_frame(ctx, ctx.layout))
      if first then
        pending[#pending + 1] = { win, first, last }
        local span = state.spans[ctx.buf]
        if span then
          span[1], span[2] = math.min(span[1], first), math.max(span[2], last)
        else
          state.spans[ctx.buf] = { first, last }
        end
      end
    else
      ctx.frame, ctx.shown = nil, {}
    end
  end
  for _, request in ipairs(pending) do
    redraw_lines(request[1], request[2], request[3])
  end
  if changed or #pending > 0 then
    flush()
  end
  -- Anything drawn from here on was not requested by this tick.
  state.spans = {}
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
  api.nvim_set_decoration_provider(stars_ns, { on_win = render_window, on_line = render_line })
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
  api.nvim_create_autocmd('OptionSet', {
    group = group,
    pattern = 'ambiwidth',
    callback = function()
      widths = {}
    end,
  })
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
  state.tick = state.tick + 1
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
  -- Stars are ephemeral decorations: one full redraw is what removes them.
  vim.cmd('redraw!')
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
    -- The sky changed after this tick's frames were built.
    state.tick = state.tick + 1
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
      result.objects = result.objects + #scene.objects
      result.showers = result.showers + (scene.shower and 1 or 0)
      for _, object in ipairs(scene.objects) do
        result.battles = result.battles + (object.battle and 1 or 0)
      end
      counted[scene] = true
    end
  end
  for _, canvas in pairs(state.canvases) do
    result.canvases = result.canvases + (canvas.id and 1 or 0)
  end
  return result
end

return M
