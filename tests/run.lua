local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local ui = dofile(root .. '/tests/ui.lua').start(root, 100, 32)
local passed, failed = 0, 0
local function test(name, code)
  local ok, err = pcall(ui.lua, code)
  if ok then
    passed = passed + 1
    print('PASS ' .. name)
  else
    failed = failed + 1
    print('FAIL ' .. name .. '\n' .. tostring(err))
  end
end

ui.lua([[
  local api = vim.api
  _G.sd = require('stardust')
  _G.rt = require('stardust.runtime')
  _G.layout = require('stardust.layout')
  _G.canvas_ns = api.nvim_get_namespaces()['stardust.canvas']
  _G.star_ns = api.nvim_get_namespaces()['stardust.stars']
  _G.notices = {}
  vim.notify = function(message, level) notices[#notices + 1] = {message, level} end
  _G.reset = function(lines, opts)
    sd.stop()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')
    vim.o.wrap = false
    vim.o.conceallevel = 0
    vim.o.diff = false
    vim.o.foldenable = false
    vim.o.number = false
    vim.o.relativenumber = false
    vim.o.signcolumn = 'no'
    vim.o.scrolloff = 0
    vim.o.winbar = ''
    vim.o.list = false
    vim.o.virtualedit = ''
    vim.o.selection = 'inclusive'
    api.nvim_buf_set_lines(0, 0, -1, false, lines or {'hello'})
    api.nvim_win_set_cursor(0, {1, 0})
    sd.setup(vim.tbl_deep_extend('force', {meteor={enabled=false}}, opts or {}))
    _G.notices = {}
    vim.cmd('redraw!')
  end
  _G.advance = function(n)
    for _ = 1, n or 90 do rt.step(1/15) end
    vim.cmd('redraw!')
  end
  _G.screen = function()
    local rows = {}
    for row = 1, vim.o.lines do
      rows[row] = {}
      for col = 1, vim.o.columns do rows[row][col] = vim.fn.screenstring(row, col) end
    end
    return rows
  end
  _G.same_text = function(before, after, count)
    for row = 1, count do
      for col, char in ipairs(before[row]) do
        if char ~= ' ' and char ~= '' then
          assert(after[row][col] == char, ('Text covered at screen %d:%d: %q -> %q'):format(row,col,char,after[row][col]))
        end
      end
    end
  end
]])

test(
  'configuration rejects malformed and unbounded values',
  [[
  local resolve = require('stardust.config').resolve
  for _, opts in ipairs({{fps=0},{fps=0/0},{stars=math.huge},{margin=-1},{meteor={trail=-1}},
    {meteor={interval={9,2}}},{palette={'oops'}},{twinkle={'xx','*'}},{twinkle={}},
    {meteor=false},{wat=true},{autostart=1}}) do
    assert(not pcall(resolve, opts), vim.inspect(opts))
  end
  local input = {meteor={trail=4}, palette={'#abcdef'}}
  local output = resolve(input)
  output.palette[1] = '#000000'
  assert(input.palette[1] == '#abcdef')
]]
)

test(
  'tab and Unicode widths use the target buffer settings',
  [[
  assert(layout.width('\tX', 2, '') == 3)
  assert(layout.width('\tX', 8, '') == 9)
  assert(layout.width('a\tX\tY', 8, '3,5') == 9)
  assert(layout.width('界\té', 4, '') == 5)
  assert(layout.width('123456789\tX', 8, '3,5') == 14)
]]
)

test(
  'setup and rendering preserve Lua global random state',
  [[
  math.randomseed(814)
  local expected = math.random()
  math.randomseed(814)
  reset({'hello'})
  sd.start(); advance(60); sd.stop()
  assert(math.random() == expected)
]]
)

test(
  'foreground-only highlights preserve transparent Normal',
  [[
  reset()
  vim.api.nvim_set_hl(0, 'Normal', {fg='#dcdfe4'})
  sd.start(); advance(30)
  assert(vim.api.nvim_get_hl(0,{name='Normal'}).bg == nil)
  for name in pairs(vim.api.nvim_get_hl(0,{})) do
    if name:match('^Stardust') then assert(vim.api.nvim_get_hl(0,{name=name}).bg == nil, name) end
  end
]]
)

test(
  'draws visible stars without changing text, modified flag, or undo history',
  [[
  local lines = {}
  for i=1,80 do lines[i] = i % 4 == 0 and '' or '    local message = "a little night sky"' end
  reset(lines)
  vim.bo.modified = false
  local tick, undo = vim.api.nvim_buf_get_changedtick(0), vim.fn.undotree().seq_cur
  local before = screen()
  sd.start(); advance(100)
  local after, decorated = screen(), 0
  same_text(before, after, 25)
  for row=2,25 do for col=45,96 do if after[row][col] ~= ' ' then decorated = decorated + 1 end end end
  assert(decorated > 0, 'no visible stars')
  assert(vim.deep_equal(lines, vim.api.nvim_buf_get_lines(0,0,-1,false)))
  assert(vim.api.nvim_buf_get_changedtick(0) == tick and not vim.bo.modified)
  assert(vim.fn.undotree().seq_cur == undo)
  assert(#vim.api.nvim_buf_get_extmarks(0,star_ns,0,-1,{}) == 0, 'persistent twinkle marks')
  assert(#notices == 0, vim.inspect(notices))
]]
)

test(
  'new text displaces twinkles on redraw before the next animation step',
  [[
  local lines = {}; for i=1,70 do lines[i] = 'x' end
  reset(lines, {below_eof=false})
  sd.start(); advance(100)
  local before, found = screen(), false
  for row=2,25 do
    for col=5,96 do
      if before[row][col] ~= ' ' then
        vim.api.nvim_buf_set_lines(0,row-1,row,false,{string.rep('Z',96)})
        vim.cmd('redraw!')
        assert(vim.fn.screenstring(row,col) == 'Z', 'stale star covered inserted text')
        found = true; break
      end
    end
    if found then break end
  end
  assert(found, 'test needs a visible twinkle')
]]
)

test(
  'edits synchronously clear the EOF canvas; appending text stays visible',
  [[
  reset({'short'})
  sd.start(); advance(100)
  assert(#vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{}) == 1)
  vim.api.nvim_buf_set_lines(0,1,1,false,{'NEW SECOND LINE','NEW THIRD LINE'})
  assert(#vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{}) == 0)
  vim.cmd('redraw!')
  assert(vim.fn.screenstring(2,1) == 'N' and vim.fn.screenstring(3,1) == 'N')
  advance(30)
  assert(vim.fn.screenstring(2,1) == 'N' and vim.fn.screenstring(3,1) == 'N')
]]
)

test(
  'same-buffer splits share one EOF block and preserve their views',
  [[
  reset({'one','two','three'})
  vim.cmd('vsplit')
  vim.cmd('vertical resize 32')
  local windows, views = vim.api.nvim_tabpage_list_wins(0), {}
  for _, win in ipairs(windows) do views[win] = vim.api.nvim_win_call(win, vim.fn.winsaveview) end
  sd.start(); advance(80)
  local marks = vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{details=true})
  assert(#marks == 1, 'duplicate EOF blocks')
  assert(#marks[1][4].virt_lines == vim.fn.getwininfo(windows[1])[1].height - 3)
  for _, win in ipairs(windows) do
    assert(vim.deep_equal(views[win],vim.api.nvim_win_call(win,vim.fn.winsaveview)))
  end
  vim.api.nvim_win_close(windows[2],true)
  advance(20)
  assert(#vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{}) == 1)
  sd.stop()
  assert(#vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{}) == 0)
]]
)

test(
  'unequal horizontal splits size the EOF canvas to the smaller view',
  [[
  reset({'one','two'})
  vim.cmd('split'); vim.cmd('resize 7')
  sd.start(); advance(30)
  local marks = vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{details=true})
  assert(#marks == 1 and #marks[1][4].virt_lines == 5, vim.inspect(marks))
  assert(#notices == 0, vim.inspect(notices))
]]
)

test(
  'different tab widths and horizontal scrolling cannot cover code',
  [[
  local lines = {}; for i=1,70 do lines[i] = '\t界\tlocal ' .. string.rep('abc',12) end
  reset(lines, {below_eof=false})
  vim.bo.tabstop = 8
  vim.cmd('vsplit'); vim.cmd('enew!')
  vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
  vim.bo.tabstop = 3
  vim.cmd('normal! 35zl')
  vim.cmd('redraw!')
  local before = screen()
  sd.start(); advance(90)
  same_text(before,screen(),25)
  assert(#notices == 0, vim.inspect(notices))
]]
)

test(
  'stored inlay and diagnostic text win even when added between ticks',
  [[
  local lines = {}; for i=1,70 do lines[i] = 'x' end
  reset(lines,{below_eof=false})
  sd.start(); advance(90)
  local ns = vim.api.nvim_create_namespace('test.decoration')
  for row=1,24 do
    vim.api.nvim_buf_set_extmark(0,ns,row,0,{virt_text={{string.rep('D',95),'Normal'}},virt_text_win_col=2,priority=0})
  end
  vim.cmd('redraw!')
  for row=2,25 do for col=3,97 do assert(vim.fn.screenstring(row,col) == 'D') end end
]]
)

test(
  'unsupported layouts and large buffers are skipped safely',
  [[
  for _, command in ipairs({'setlocal wrap','setlocal conceallevel=2','setlocal diff','setlocal buftype=nofile'}) do
    reset({'one','two'}); vim.cmd(command); sd.start(); advance(3)
    assert(sd.status().windows == 0 and sd.status().canvases == 0, command)
  end
  reset({'one','two','three','four'})
  vim.wo.foldenable = true
  vim.cmd('2,4fold')
  sd.start(); advance(3)
  assert(sd.status().windows == 0)
  reset({'too many bytes'},{max_bytes=3}); sd.start(); advance(3)
  assert(sd.status().windows == 0)
  reset({'one','two'},{max_lines=1}); sd.start(); advance(3)
  assert(sd.status().windows == 0)
]]
)

test(
  'selection and focus loss clear decorations and restore on resume',
  [[
  reset({'one','two'})
  sd.start(); advance(80)
  vim.cmd('normal! Vj'); vim.cmd('redraw!')
  assert(sd.status().paused)
  assert(#vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{}) == 0)
  vim.api.nvim_input(vim.api.nvim_replace_termcodes('<Esc>',true,false,true))
]]
)

test(
  'focus pause and resume release and restart the timer',
  [[
  vim.cmd('stopinsert')
  reset({'one'})
  sd.start(); advance(20)
  vim.api.nvim_exec_autocmds('FocusLost',{})
  assert(sd.status().paused)
  assert(#vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{}) == 0)
  vim.api.nvim_exec_autocmds('FocusGained',{})
  assert(not sd.status().paused)
  assert(vim.wait(500,function() return sd.status().canvases > 0 end,10))
]]
)

test(
  'meteors honor every intermediate path cell and clip their entire trail',
  [[
  local simulation = require('stardust.sky')
  local cfg = require('stardust.config').resolve({stars=0,meteor={speed=60}})
  local view = layout.empty(80,24,3)
  local scene = simulation.new(17)
  assert(simulation.meteor(scene,view,cfg))
  local head = scene.meteor
  view.rows[head.y].first, view.rows[head.y].last = 0, 0
  simulation.step(scene,view,cfg,0.25,3)
  assert(not scene.meteor or not scene.meteor.head, 'meteor jumped across occupied cells')
  local colors = require('stardust.palette').setup(cfg)
  for _, cell in ipairs(simulation.frame(scene,view,cfg,colors)) do assert(cell.y ~= head.y) end
  for _=1,60 do simulation.step(scene,view,cfg,1/15,3) end
  assert(scene.meteor == nil)
]]
)

test(
  'repeated setup, invalid reconfiguration, and stop clean up all resources',
  [[
  reset({'one'})
  for _=1,12 do sd.setup({autostart=true}); advance(4); sd.stop() end
  sd.setup({autostart=true})
  assert(not pcall(sd.setup,{fps=-1}))
  assert(sd.status().active, 'invalid config stopped valid running session')
  advance(15)
  vim.api.nvim_exec_autocmds('ColorScheme',{})
  advance(4)
  sd.stop(); sd.stop()
  vim.wait(150,function() return false end,10)
  assert(not sd.status().active and sd.status().canvases == 0)
  assert(#vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{}) == 0)
  for _, entry in ipairs(vim.api.nvim_get_autocmds({})) do assert(entry.group_name ~= 'StardustRuntime') end
]]
)

test(
  'real timer animates and no callbacks survive stopping',
  [[
  reset({'one','two'})
  sd.start()
  assert(vim.wait(750,function() return sd.status().stars >= 3 end,10))
  sd.stop()
  vim.wait(150,function() return false end,10)
  assert(not sd.status().active)
  assert(#vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{}) == 0)
  assert(#notices == 0, vim.inspect(notices))
]]
)

test(
  'short-file canvas produces visible stars without adding buffer lines',
  [[
  reset({'a small beginning'})
  sd.start(); advance(90)
  local pixels = screen()
  local found = 0
  for row=3,25 do
    for col=5,95 do
      if pixels[row][col] ~= ' ' and pixels[row][col] ~= '~' then found = found + 1 end
    end
  end
  assert(found > 0, 'EOF canvas is not visible')
  assert(vim.api.nvim_buf_line_count(0) == 1)
  assert(sd.meteor(), 'empty EOF region should have a clear meteor path')
  advance(3)
  local gold = false
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{details=true})) do
    for _, row in ipairs(mark[4].virt_lines) do
      for _, cell in ipairs(row) do
        if type(cell[2]) == 'string' and cell[2]:match('StardustMeteor') then gold = true end
      end
    end
  end
  assert(gold, 'meteor did not render')
]]
)

test(
  'blank buffer rows remain available for ephemeral indentation guides',
  [[
  local lines = {}; for i=1,70 do lines[i] = i%2 == 0 and '' or '    call()' end
  reset(lines,{below_eof=false})
  local ns = vim.api.nvim_create_namespace('test.indent')
  vim.api.nvim_set_decoration_provider(ns,{on_win=function(_,win,buf,top,bottom)
    for row=top,math.min(bottom,69) do
      if row%2 == 1 then
        vim.api.nvim_buf_set_extmark(buf,ns,row,0,{ephemeral=true,virt_text={{'│','Normal'}},virt_text_win_col=5,priority=0})
      end
    end
    return false
  end})
  sd.start(); advance(90)
  for row=2,24,2 do
    assert(vim.fn.screenstring(row,6) == '│')
    for col=7,95 do assert(vim.fn.screenstring(row,col) == ' ') end
  end
  vim.api.nvim_set_decoration_provider(ns,{})
]]
)

test(
  'gutter, winbar, cursor, and vertical scrolling preserve code',
  [[
  local lines = {}; for i=1,100 do lines[i] = ('line_%d = "sky"'):format(i) end
  reset(lines,{below_eof=false})
  vim.wo.number = true
  vim.wo.signcolumn = 'yes'
  vim.wo.winbar = ' Stardust '
  vim.cmd('normal! 40Gzt')
  vim.cmd('redraw!')
  local before = screen()
  sd.start(); advance(60)
  same_text(before,screen(),25)
  local view = layout.get(vim.api.nvim_get_current_win(),vim.api.nvim_get_current_buf(),require('stardust.config').resolve(),{},canvas_ns)
  assert(view and view.rows[1].first == view.rows[1].last, 'cursor row is not reserved')
  assert(#notices == 0,vim.inspect(notices))
]]
)

test(
  'shared buffer exclusions and tab changes clean up the EOF canvas',
  [[
  reset({'one','two'})
  sd.start(); advance(20)
  vim.cmd('tab split')
  vim.wo.wrap = true
  advance(2)
  assert(sd.status().canvases == 0 and sd.status().windows == 0)
  vim.cmd('tabprevious')
  advance(2)
  assert(sd.status().windows == 1 and sd.status().canvases == 0)
  vim.cmd('tabonly!')
  advance(2)
  assert(sd.status().canvases == 1)
  vim.b.stardust_disable = true
  advance(2)
  assert(sd.status().windows == 0 and sd.status().canvases == 0)
  vim.b.stardust_disable = false
  advance(2)
  assert(sd.status().windows == 1)
]]
)

test(
  'deletion, undo, buffer switching, and wipeout leave no stale decorations',
  [[
  reset({'one','two','three'})
  sd.start(); advance(30)
  local old = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(old,0,-1,false,{})
  assert(#vim.api.nvim_buf_get_extmarks(old,canvas_ns,0,-1,{}) == 0)
  advance(10)
  vim.cmd('undo')
  advance(10)
  vim.api.nvim_win_set_buf(0,vim.api.nvim_create_buf(true,false))
  advance(5)
  assert(#vim.api.nvim_buf_get_extmarks(old,canvas_ns,0,-1,{}) == 0)
  vim.api.nvim_buf_delete(old,{force=true})
  advance(5)
  assert(sd.status().active and #notices == 0,vim.inspect(notices))
]]
)

test(
  'runtime errors stop cleanly instead of producing a repeated error loop',
  [[
  reset({'one'})
  sd.start(); advance(20)
  local get = layout.get
  layout.get = function() error('intentional test failure') end
  vim.cmd('redraw!')
  assert(vim.wait(500,function() return not sd.status().active end,5))
  layout.get = get
  assert(#vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{}) == 0)
  assert(#notices == 1 and notices[1][2] == vim.log.levels.ERROR,vim.inspect(notices))
  vim.wait(100,function() return false end,10)
  assert(#notices == 1)
]]
)

test(
  'plugin command entry point registers and toggles successfully',
  [[
  reset({'one'})
  vim.cmd('runtime plugin/stardust.lua')
  vim.cmd('Stardust start'); advance(2)
  assert(sd.status().active)
  vim.cmd('Stardust')
  assert(not sd.status().active)
  vim.cmd('Stardust status')
  assert(#notices == 1)
]]
)

ui.close()
print(('%d passed, %d failed'):format(passed, failed))
vim.cmd(failed == 0 and 'qa!' or 'cquit 1')
