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

-- Use rendered positions, so tabs, Unicode, wraps, folds, and dashboard
-- buffers follow the same rules. Only the empty space after text is drawn on.
function M.get(win, buf, cache, canvas_ns)
  if not api.nvim_win_is_valid(win) or not api.nvim_buf_is_valid(buf) then
    return nil, 'closed'
  end
  local wi = vim.fn.getwininfo(win)[1]
  local width, height = wi.width - wi.textoff, wi.height
  if width <= MARGIN * 2 or height < 1 then
    return nil, 'no empty space'
  end
  local count = api.nvim_buf_line_count(buf)
  local top, bottom = wi.topline, math.min(count, wi.botline)
  local tick = api.nvim_buf_get_changedtick(buf)
  if cache.tick ~= tick then
    cache.tick, cache.lines = tick, {}
  end
  local lines, rows, occupied = {}, {}, 0
  local left, screen_top = wi.wincol + wi.textoff, wi.winrow + wi.winbar
  for y = 1, height do
    rows[y] = { first = width, last = width }
  end
  api.nvim_win_call(win, function()
    local line = top
    while line <= bottom do
      local fold = vim.fn.foldclosedend(line)
      local start = vim.fn.screenpos(win, line, 1)
      if fold >= line then
        occupied = math.max(occupied, start.row - screen_top + 1)
        line = fold + 1
      else
        local text = cache.lines[line]
          or api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
          or ''
        lines[line] = text
        if #text <= 16384 then
          -- Padding is empty space, unless listchars makes it visible.
          local content = vim.wo.list and text or text:gsub('[ \t]+$', '')
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
          elseif vim.wo.wrap then
            occupied = height
          end
        else
          occupied = math.max(occupied, vim.wo.wrap and height or start.row - screen_top + 1)
        end
        line = line + 1
      end
    end
  end)
  cache.lines = lines
  occupied = math.min(height, math.max(1, occupied))
  local view = {
    win = win,
    buf = buf,
    width = width,
    height = occupied,
    top = top,
    rows = rows,
    area = 0,
    free = bottom == count and height - occupied or 0,
  }

  -- Stored virtual text takes precedence. Plain syntax highlights do not
  -- consume space or count toward this bounded scan.
  local blocked, budget = {}, 512
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
        if detail.virt_text then
          for row = math.max(top - 1, mark[2]), math.min(bottom - 1, detail.end_row or mark[2]) do
            blocked[row] = true
          end
        end
        if detail.virt_lines and mark[2] == count - 1 then
          view.free = 0
        end
      end
    end
    if budget == 0 then
      break
    end
  end
  for y = 1, occupied do
    local row = rows[y]
    if budget == 0 or blocked[row.line] then
      row.first = row.last
    end
    view.area = view.area + row.last - row.first
  end
  for y = height, occupied + 1, -1 do
    rows[y] = nil
  end
  return view
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
