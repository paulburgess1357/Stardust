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
  sd.setup({meteor={enabled=false},below_eof=false})
  local function measure(active)
    local samples = {}
    for _=1,240 do
      local start = vim.uv.hrtime()
      if active then rt.step(1/15) end
      vim.cmd('redraw!')
      samples[#samples+1] = (vim.uv.hrtime()-start)/1e6
    end
    table.sort(samples)
    return {median_ms=samples[120],p95_ms=samples[228]}
  end
  local baseline = measure(false)
  sd.start()
  for _=1,60 do rt.step(1/15) end
  local active = measure(true)
  local status = sd.status()
  sd.stop()
  return {baseline=baseline,active=active,windows=status.windows,stars=status.stars,screen='180x56',samples=240}
]]
)
ui.close()
if not ok then
  error(result)
end
print(vim.inspect(result))
vim.cmd('qa!')
