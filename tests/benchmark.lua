local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local ui = dofile(root .. '/tests/ui.lua').start(root, 180, 56)
local ok, result = pcall(
  ui.lua,
  [[
  local lines = {}
  for i=1,2000 do lines[i] = ('    local value_%d = "celestial mechanics"'):format(i) end
  vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
  vim.cmd('vsplit'); vim.cmd('split'); vim.cmd('wincmd l'); vim.cmd('split')
  local sd, rt = require('stardust'), require('stardust.runtime')
  sd.setup({meteors=0,showers=0,moons=0,planets=0,comets=0,ships=0}); sd.stop()
  -- A tick draws its own changes; a full redraw stands in for the editor
  -- repainting after a keystroke. Both are timed on their own.
  local function measure(fn)
    local samples = {}
    for _=1,240 do
      local start = vim.uv.hrtime()
      fn()
      samples[#samples+1] = (vim.uv.hrtime()-start)/1e6
    end
    table.sort(samples)
    return {median_ms=samples[120],p95_ms=samples[228]}
  end
  local function tick() rt.step(1/60) end
  local function full_redraw() vim.cmd('redraw!') end
  local baseline = measure(full_redraw)
  sd.start()
  for _=1,60 do rt.step(1/15) end
  local active = measure(tick)
  local redraw_with_sky = measure(full_redraw)
  local status = sd.status()
  sd.setup({showers=1,moons=0,planets=0,comets=0})
  rt.step(0)
  for _,win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    vim.api.nvim_set_current_win(win)
    assert(sd.shower() and sd.battle())
  end
  local effects = measure(tick)
  sd.stop()
  return {editor_redraw=baseline,editor_redraw_with_sky=redraw_with_sky,tick_stars_only=active,tick_showers_and_battles=effects,windows=status.windows,stars=status.stars,screen='180x56',samples=240}
]]
)
ui.close()
if not ok then
  error(result)
end
print(vim.inspect(result))
vim.cmd('qa!')
