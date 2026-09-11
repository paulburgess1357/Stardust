local api = vim.api
local M = {}

-- strdisplaywidth uses the current buffer's tab settings. Expand tabs ourselves
-- so a non-current split with different tabstop/vartabstop has correct geometry.
function M.width(text, tabstop, vartabstop)
  local stops = {}
  for value in (vartabstop or ''):gmatch('%d+') do
    stops[#stops + 1] = tonumber(value)
  end
  local column, offset = 0, 1
  while true do
    local tab = text:find('\t', offset, true)
    column = column + vim.fn.strdisplaywidth(text:sub(offset, tab and tab - 1 or #text), column)
    if not tab then
      return column
    end
    if #stops == 0 then
      column = column + tabstop - column % tabstop
    else
      local boundary = 0
      for _, size in ipairs(stops) do
        boundary = boundary + size
        if boundary > column then
          break
        end
      end
      if boundary <= column then
        local size = stops[#stops]
        boundary = boundary + (math.floor((column - boundary) / size) + 1) * size
      end
      column = boundary
    end
    offset = tab + 1
  end
end

function M.get(win, buf, cfg, cache, canvas_ns)
  if not api.nvim_win_is_valid(win) or not api.nvim_buf_is_valid(buf) then
    return nil, 'closed'
  end
  local terminal = vim.bo[buf].buftype == 'terminal'
  if
    api.nvim_win_get_config(win).relative ~= '' or (vim.bo[buf].buftype ~= '' and not terminal)
  then
    return nil, 'special window'
  end
  if terminal and not cfg.terminals then
    return nil, 'terminals disabled'
  end
  if vim.b[buf].stardust_disable or vim.w[win].stardust_disable then
    return nil, 'disabled for this view'
  end
  if vim.tbl_contains(cfg.excluded_filetypes, vim.bo[buf].filetype) then
    return nil, 'excluded filetype'
  end
  -- Terminal buffers already contain the emulator's screen rows, even with wrap set.
  if (vim.wo[win].wrap and not terminal) or vim.wo[win].diff or vim.wo[win].conceallevel > 0 then
    return nil, 'wrap, diff, or conceal enabled'
  end
  local count = api.nvim_buf_line_count(buf)
  if count > cfg.max_lines or api.nvim_buf_get_offset(buf, count) > cfg.max_bytes then
    return nil, 'large buffer'
  end
  local wi = vim.fn.getwininfo(win)[1]
  if not wi then
    return nil, 'closed'
  end
  local top, bottom = wi.topline, math.min(count, wi.botline)
  local height, width = wi.height, wi.width - wi.textoff
  if width <= cfg.margin * 2 or bottom < top or bottom - top + 1 > height then
    return nil, 'no simple visible area'
  end
  local occupied = api.nvim_win_text_height(win, { start_row = top - 1, end_row = bottom - 1 })
  if occupied.fill > 0 or occupied.all ~= bottom - top + 1 then
    return nil, 'folds or virtual lines'
  end

  local tick, ts, vts =
    api.nvim_buf_get_changedtick(buf), vim.bo[buf].tabstop, vim.bo[buf].vartabstop
  local key = table.concat({ tick, top, bottom, ts, vts, vim.o.ambiwidth, vim.o.display }, ':')
  if cache.key ~= key then
    local lines = api.nvim_buf_get_lines(buf, top - 1, bottom, false)
    local widths, indent = {}, 0
    for i, line in ipairs(lines) do
      if #line > 16000 then
        return nil, 'very long visible line'
      end
      local leading = line:match('^[ \t]*')
      indent = math.max(indent, M.width(leading, ts, vts))
      local text = terminal and line:gsub('%s+$', '') or line
      widths[i] = text:find('%S') and M.width(text, ts, vts) or false
    end
    cache.key, cache.widths, cache.indent = key, widths, indent
  end

  -- Scan each redraw, independently of changedtick: extmarks can change without
  -- text changing. Bound the scan and skip ambiguous views instead of guessing.
  local marks = api.nvim_buf_get_extmarks(
    buf,
    -1,
    { top - 1, 0 },
    { bottom, 0 },
    { details = true, overlap = true, limit = 512 }
  )
  if #marks == 512 then
    return nil, 'too many decorations'
  end
  local blocked = {}
  for _, mark in ipairs(marks) do
    local detail = mark[4]
    if detail.ns_id ~= canvas_ns then
      if detail.virt_lines then
        return nil, 'other virtual lines'
      end
      if detail.virt_text or detail.conceal or detail.conceal_lines then
        for row = math.max(top - 1, mark[2]), math.min(bottom - 1, detail.end_row or mark[2]) do
          blocked[row] = true
        end
      end
    end
  end
  local cursor = (cfg.cursor_row or terminal) and api.nvim_win_get_cursor(win)[1] or -1
  local result = {
    rows = {},
    width = width,
    height = bottom - top + 1,
    area = 0,
    win = win,
    buf = buf,
    top = top,
    screen_height = height,
    eof = bottom == count,
    count = count,
    -- Never insert virtual lines into a terminal's screen or scrollback.
    free = not terminal and bottom == count and math.max(0, height - occupied.all) or 0,
  }
  for i, line_width in ipairs(cache.widths) do
    local line = top + i - 2
    local content = line_width or cache.indent
    local first = math.max(cfg.margin, content - wi.leftcol + cfg.margin)
    local last = width - cfg.margin
    if
      blocked[line]
      or line + 1 == cursor
      or (line_width == false and not cfg.blank_lines and not terminal)
    then
      first = last
    end
    first = math.min(first, last)
    result.rows[i] = { first = first, last = last, line = line }
    result.area = result.area + last - first
  end
  return result
end

function M.empty(width, height, margin)
  local layout = { width = width, height = height, area = 0, rows = {} }
  for i = 1, height do
    local first, last = math.min(margin, width), math.max(math.min(margin, width), width - margin)
    layout.rows[i] = { first = first, last = last }
    layout.area = layout.area + last - first
  end
  return layout
end

return M
