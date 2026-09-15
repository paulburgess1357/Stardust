local api = vim.api
local M = {}
local MARGIN = 2

function M.empty(width, height, margin)
  margin = margin or MARGIN
  local view = { width = width, height = height, area = 0, rows = {} }
  for y = 1, height do
    local first = math.min(margin, width)
    local last = math.max(first, width - margin)
    view.rows[y] = { first = first, last = last }
    view.area = view.area + last - first
  end
  return view
end

-- Everything the row scan depends on that is cheap to read, so a view can
-- be reused across ticks. Folds, conceal, and similar settings are left out:
-- the runtime rescans after any redraw it did not request, and periodically.
local function fingerprint(win, buf, wi)
  local saved = api.nvim_win_call(win, vim.fn.winsaveview)
  return table.concat({
    api.nvim_buf_get_changedtick(buf),
    api.nvim_buf_line_count(buf),
    wi.topline,
    wi.botline,
    wi.width,
    wi.height,
    wi.textoff,
    wi.winrow,
    wi.wincol,
    wi.winbar,
    saved.leftcol,
    saved.skipcol,
    tostring(vim.wo[win].wrap),
    tostring(vim.wo[win].list),
  }, ':')
end

-- True while a scanned view still describes the window.
function M.fresh(win, buf, view)
  if not api.nvim_win_is_valid(win) or not api.nvim_buf_is_valid(buf) then
    return false
  end
  return view.key == fingerprint(win, buf, vim.fn.getwininfo(win)[1])
end

-- Use rendered positions, so tabs, Unicode, wraps, folds, and dashboard
-- buffers follow the same rules. Only the empty space after text is drawn on.
function M.get(win, buf, canvas_ns, floating)
  if not api.nvim_win_is_valid(win) or not api.nvim_buf_is_valid(buf) then
    return nil, 'closed'
  end
  -- Popups, pickers, and hover documentation are opt-in.
  if not floating and api.nvim_win_get_config(win).relative ~= '' then
    return nil, 'floating window'
  end
  local wi = vim.fn.getwininfo(win)[1]
  local width, height = wi.width - wi.textoff, wi.height
  if width <= MARGIN * 2 or height < 1 then
    return nil, 'no empty space'
  end
  local key = fingerprint(win, buf, wi)
  local count = api.nvim_buf_line_count(buf)
  local top, bottom = wi.topline, math.min(count, wi.botline)
  local tick = api.nvim_buf_get_changedtick(buf)
  local texts = api.nvim_buf_get_lines(buf, top - 1, bottom, false)
  local rows, occupied = {}, 0
  local left, screen_top = wi.wincol + wi.textoff, wi.winrow + wi.winbar
  for y = 1, height do
    rows[y] = { first = width, last = width }
  end
  api.nvim_win_call(win, function()
    local wrap, list = vim.wo.wrap, vim.wo.list
    local line = top
    while line <= bottom do
      local fold = vim.fn.foldclosedend(line)
      if fold >= line then
        local start = vim.fn.screenpos(win, line, 1)
        occupied = math.max(occupied, start.row - screen_top + 1)
        line = fold + 1
      else
        local text = texts[line - top + 1] or ''
        if #text <= 16384 then
          -- Padding is empty space, unless listchars makes it visible.
          local content = list and text or text:gsub('[ \t]+$', '')
          local pos = vim.fn.screenpos(win, line, #content + 1)
          local y = pos.row - screen_top + 1
          if y >= 1 and y <= height then
            local last = width - MARGIN
            rows[y] = {
              first = math.min(last, math.max(MARGIN, pos.col - left + MARGIN)),
              last = last,
              line = line - 1,
              col = #content,
            }
            occupied = math.max(occupied, y)
          elseif wrap then
            occupied = height
          end
        elseif wrap then
          occupied = height
        else
          local start = vim.fn.screenpos(win, line, 1)
          occupied = math.max(occupied, start.row - screen_top + 1)
        end
        line = line + 1
      end
    end
  end)
  occupied = math.min(height, math.max(1, occupied))
  for y = 1, occupied do
    rows[y].open = rows[y].first
  end
  for y = height, occupied + 1, -1 do
    rows[y] = nil
  end
  local view = {
    win = win,
    buf = buf,
    key = key,
    scanned = vim.uv.hrtime(),
    width = width,
    height = occupied,
    top = top,
    bottom = bottom,
    count = count,
    tick = tick,
    win_width = wi.width,
    win_height = wi.height,
    rows = rows,
    area = 0,
    room = bottom == count and height - occupied or 0,
  }
  M.occupy(view, buf, canvas_ns)
  return view
end

-- Stored virtual text takes precedence. Plain syntax highlights do not
-- consume space or count toward this bounded scan. This is cheap enough to
-- repeat on every redraw; the stamp tells whether anything changed since the
-- view was scanned.
function M.occupy(view, buf, canvas_ns)
  local top, bottom, count = view.top, view.bottom, view.count
  local blocked, budget, stamp, eof = {}, 512, {}, false
  for _, kind in ipairs({ 'virt_text', 'virt_lines' }) do
    local marks = api.nvim_buf_get_extmarks(buf, -1, { top - 1, 0 }, { bottom, 0 }, {
      details = true,
      overlap = true,
      limit = budget,
      type = kind,
    })
    budget = budget - #marks
    for _, mark in ipairs(marks) do
      local detail = mark[4]
      if detail.ns_id ~= canvas_ns then
        stamp[#stamp + 1] = detail.ns_id .. '/' .. mark[1] .. '@' .. mark[2]
        if detail.virt_text then
          for row = math.max(top - 1, mark[2]), math.min(bottom - 1, detail.end_row or mark[2]) do
            blocked[row] = true
          end
        end
        if detail.virt_lines and mark[2] == count - 1 then
          eof = true
        end
      end
    end
    if budget == 0 then
      break
    end
  end
  view.free = eof and 0 or view.room
  view.area = 0
  for y = 1, view.height do
    local row = view.rows[y]
    row.first = (budget == 0 or blocked[row.line]) and row.last or row.open
    view.area = view.area + row.last - row.first
  end
  view.stamp = table.concat(stamp, ',') .. (budget == 0 and '!' or '')
  return view.stamp
end

-- Buffer-scoped EOF lines are shared by views with the same geometry.
function M.scene(views, free, width)
  local first = views[1]
  local result = M.empty(width, first.height + free)
  result.area = 0
  for y, row in ipairs(result.rows) do
    if y <= first.height then
      for _, view in ipairs(views) do
        row.first = math.max(row.first, view.rows[y].first)
        row.last = math.min(row.last, view.rows[y].last)
      end
      row.first = math.min(row.first, row.last)
      row.line, row.col = first.rows[y].line, first.rows[y].col
    end
    result.area = result.area + row.last - row.first
  end
  return result
end

return M
