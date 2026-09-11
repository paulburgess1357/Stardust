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
    sd.setup(vim.tbl_deep_extend('force', {meteor={enabled=false},objects={enabled=false}}, opts or {}))
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
    {meteor=false},{wat=true},{autostart=1},{terminals=1},{palette='red'},
    {objects=false},{objects={speed=0}},{objects={types={}}},{objects={types={'saturn'}}},
    {objects={interval={8,2}}},{objects={enabled=1}},{objects={wat=true}},
    {objects={ships={}}},{objects={ships={'unknown'}}},
    {enabled=false},{enabled={ships=1}},{enabled={unknown=true}},
    {colors=false},{colors={stars={}}},{colors={ships='red'}},{colors={unknown='#ffffff'}},
    {objects={ships={{right='x'}}}},{objects={ships={{right='x',left='x',wat=true}}}},
    {objects={ships={{right='   ',left='x'}}}},{objects={ships={{right='x\ny',left='x'}}}},
    {objects={ships={{right='界',left='x'}}}},{objects={ships={{right=string.rep('x',17),left='x'}}}},
    {objects={ships={{right={'a','b','c','d','e'},left='x'}}}},
    {objects={ships={{right='x',left='x',color='blue'}}}}}) do
    assert(not pcall(resolve, opts), vim.inspect(opts))
  end
  local input = {meteor={trail=4}, colors={stars={'#abcdef'}}, objects={ships={{right={'xy'},left={'yx'}}}}}
  local output = resolve(input)
  output.colors.stars[1] = '#000000'
  output.objects.ships[1].right[1] = 'changed'
  assert(input.colors.stars[1] == '#abcdef' and input.objects.ships[1].right[1] == 'xy')
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
  'meteors keep a diagonal in short and tall views and finish their trails at an edge',
  [[
  local simulation = require('stardust.sky')
  local cfg = require('stardust.config').resolve({stars=0,meteor={enabled=false,speed=18},objects={enabled=false}})
  local colors = require('stardust.palette').setup(cfg)
  for _,height in ipairs({8,64}) do
    for _,direction in ipairs({0.25,0.75}) do
      local view, empty = layout.empty(100,height,3), layout.empty(100,height,50)
      local scene = simulation.new(17)
      scene.random = function() return direction end
      assert(simulation.meteor(scene,view,cfg))
      local head = scene.meteor
      local start_x, start_y = head.x, head.y
      for _=1,2 do simulation.step(scene,empty,cfg,1/18,#colors.stars) end
      assert(scene.meteor == head and head.head, 'occlusion ended the flight')
      assert(#simulation.frame(scene,empty,cfg,colors) == 0, 'occupied cells were painted')
      assert(math.abs(head.x-start_x) == 2 and head.y == start_y+1, 'diagonal flattened')
      assert(#simulation.frame(scene,view,cfg,colors) > 0, 'meteor did not reappear')
      local draining = false
      for _=1,140 do
        simulation.step(scene,view,cfg,1/18,#colors.stars)
        if scene.meteor then
          if not head.head then
            assert(head.x <= 1 or head.x >= 98 or head.y == height, 'head stopped inside viewport')
            draining = draining or #head.trail > 0
          end
          for _,cell in ipairs(simulation.frame(scene,view,cfg,colors)) do
            assert(simulation.safe(view,cell.x,cell.y))
          end
        end
      end
      assert(draining, 'tail did not finish fading after the head exited')
      assert(scene.meteor == nil)
    end
  end
]]
)

test(
  'diagonal particles keep one track through fractional frames and brightness transitions',
  [[
  local simulation = require('stardust.sky')
  local cfg = require('stardust.config').resolve({stars=0,meteor={enabled=false},objects={enabled=false}})
  local colors = require('stardust.palette').setup(cfg)
  for _,kind in ipairs({'meteor','comet'}) do
    for _,direction in ipairs({0.25,0.75}) do
      local scene,view = simulation.new(19),layout.empty(200,120,3)
      scene.random = function() return direction end
      if kind == 'meteor' then
        assert(simulation.meteor(scene,view,cfg))
      else
        assert(simulation.object(scene,view,cfg,kind))
      end
      local body = kind == 'meteor' and scene.meteor or scene.object
      local origin_x,origin_y = body.x,body.y
      local previous,previous_x,previous_y = nil,body.x,body.y
      local eased = false
      for _=1,40 do
        simulation.step(scene,view,cfg,1/30,#colors.stars)
        local cells = simulation.frame(scene,view,cfg,colors)
        for _,cell in ipairs(cells) do
          assert((cell.x-origin_x)*body.dx == 2*(cell.y-origin_y), 'particle switched to a parallel track')
        end
        if previous and body.x == previous_x and body.y == previous_y and not vim.deep_equal(cells,previous) then
          eased = true
        end
        previous,previous_x,previous_y = cells,body.x,body.y
      end
      assert(eased, 'motion had no intermediate brightness frames')
    end
  end
]]
)

test(
  'meteor motion and fading depend on elapsed time rather than frame rate',
  [[
  local simulation = require('stardust.sky')
  local cfg = require('stardust.config').resolve({stars=0,meteor={enabled=false},objects={enabled=false}})
  local colors = require('stardust.palette').setup(cfg)
  local view = layout.empty(200,120,3)
  local positions = {}
  for _,fps in ipairs({10,15,30}) do
    local scene = simulation.new(19)
    scene.random = function() return 0.75 end
    assert(simulation.meteor(scene,view,cfg))
    for _=1,fps*2 do simulation.step(scene,view,cfg,1/fps,#colors.stars) end
    local body = scene.meteor
    assert(body and body.head)
    positions[#positions+1] = {x=body.x,y=body.y,step=body.step}
    local youngest = body.trail[#body.trail]
    assert(youngest and youngest.age < 1e-8, 'new trail segment has the wrong age')
  end
  assert(vim.deep_equal(positions[1],positions[2]) and vim.deep_equal(positions[2],positions[3]))
]]
)

test(
  'explicit category colors and per-ship overrides produce foreground-only highlights',
  [[
  local resolve = require('stardust.config').resolve
  local palette = require('stardust.palette')
  vim.api.nvim_set_hl(0,'Normal',{bg='#000000',fg='#ffffff'})
  local cfg = resolve({colors={stars={'#c80000'},meteors='#00c800',ships='#0000c8',moons='#c8c800',planets='#00c8c8',comets='#c800c8'},
    objects={ships={{right='x',left='x',color='#646464'},{right='y',left='y'}}}})
  local ramps = palette.setup(cfg)
  assert(#ramps.stars == 1)
  local expected = {meteor=0x00be00,ship=0x0000be,moon=0xbebe00,planet=0x00bebe,comet=0xbe00be}
  for kind,fg in pairs(expected) do
    local hl = vim.api.nvim_get_hl(0,{name=ramps[kind][8]})
    assert(hl.fg == fg and hl.bg == nil, kind)
  end
  assert(vim.api.nvim_get_hl(0,{name=ramps.stars[1][8]}).fg == 0xbe0000)
  assert(vim.api.nvim_get_hl(0,{name=ramps.ships[1][8]}).fg == 0x5f5f5f)
  assert(ramps.ships[2] == ramps.ship)
  vim.api.nvim_set_hl(0,'Identifier',{fg='#ff0000'})
  vim.api.nvim_set_hl(0,'Special',{fg='#ff0000'})
  palette.setup(cfg)
  assert(vim.api.nvim_get_hl(0,{name=ramps.stars[1][8]}).fg == 0xbe0000)
]]
)

test(
  'moons and planets stay fixed, fade in and out, and respect text occupancy',
  [[
  local simulation = require('stardust.sky')
  local cfg = require('stardust.config').resolve({stars=0,meteor={enabled=false},objects={enabled=false,speed=20}})
  local colors = require('stardust.palette').setup(cfg)
  local view = layout.empty(100,8,3)
  for _,kind in ipairs({'moon','planet'}) do
    local scene = simulation.new(19)
    assert(simulation.object(scene,view,cfg,kind))
    assert(not simulation.object(scene,view,cfg,kind), 'unbounded object count')
    local object = scene.object
    local x,y = object.x,object.y
    assert(#simulation.frame(scene,view,cfg,colors) == 0, 'object did not fade in')
    for _=1,10 do simulation.step(scene,view,cfg,0.25,#colors.stars) end
    local cells = simulation.frame(scene,view,cfg,colors)
    assert(#cells == #simulation.objects[kind], vim.inspect(cells))
    for _,cell in ipairs(cells) do assert(vim.fn.strdisplaywidth(cell.glyph) == 1) end
    local blocked = layout.empty(100,8,50)
    simulation.step(scene,blocked,cfg,0.1,#colors.stars)
    assert(scene.object and #simulation.frame(scene,blocked,cfg,colors) == 0)
    while object.age < object.life-1 do
      simulation.step(scene,view,cfg,0.1,#colors.stars)
      assert(scene.object == object and object.x == x and object.y == y, 'celestial object drifted')
    end
    local fading = simulation.frame(scene,view,cfg,colors)
    assert(#fading > 0 and fading[1].hl ~= cells[1].hl, 'object did not fade out')
    for _=1,20 do simulation.step(scene,view,cfg,0.1,#colors.stars) end
    assert(scene.object == nil)
  end
  cfg.objects.enabled = true
  cfg.objects.interval = {1,1}
  cfg.objects.types = {'planet'}
  local scene = simulation.new(19)
  for _=1,25 do simulation.step(scene,view,cfg,1/15,#colors.stars) end
  assert(scene.object and scene.object.kind == 'planet')
]]
)

test(
  'comet tails follow the head diagonal in both directions and exit completely',
  [[
  local simulation = require('stardust.sky')
  local cfg = require('stardust.config').resolve({stars=0,meteor={enabled=false},objects={enabled=false}})
  local colors = require('stardust.palette').setup(cfg)
  for _,direction in ipairs({0.25,0.75}) do
    local scene, view = simulation.new(19), layout.empty(100,64,3)
    scene.random = function() return direction end
    assert(simulation.object(scene,view,cfg,'comet'))
    local object = scene.object
    local history = {{x=object.x,y=object.y}}
    for _=1,12 do
      simulation.step(scene,view,cfg,1/6,#colors.stars)
      if history[#history].x ~= object.x then
        history[#history+1] = {x=object.x,y=object.y}
      end
    end
    local cells = simulation.frame(scene,view,cfg,colors)
    assert(#cells == 4)
    assert(cells[1].y > cells[#cells].y, 'horizontal comet tail')
    for i,cell in ipairs(cells) do
      local previous = history[#history-i+1]
      assert(cell.x == previous.x and cell.y == previous.y, 'tail left the head path')
    end
    local tail_only = false
    for _=1,150 do
      simulation.step(scene,view,cfg,1/6,#colors.stars)
      if scene.object and not simulation.safe(view,object.x,object.y) then
        local visible = simulation.frame(scene,view,cfg,colors)
        for _,cell in ipairs(visible) do assert(cell.glyph ~= '✧') end
        tail_only = tail_only or #visible > 0
      end
    end
    assert(tail_only, 'comet tail disappeared with the head')
    assert(scene.object == nil)
  end
]]
)

test(
  'custom ship artwork is selected once and renders exactly in either direction',
  [[
  local simulation = require('stardust.sky')
  local definitions = {
    {right='AB◇',left='◇ba'},
    {right={' U ','[U]'},left={' u ','[u]'},color='#abcdef'},
    {right='Q',left='q'},
  }
  local expected = {{right='AB◇',left='◇ba'},{right=' U\n[U]',left=' u\n[u]'},{right='Q',left='q'}}
  for variant=1,3 do
    local cfg = require('stardust.config').resolve({stars=0,meteor={enabled=false},objects={enabled=false,speed=20,ships=definitions}})
    local colors = require('stardust.palette').setup(cfg)
    for _,direction in ipairs({0.25,0.75}) do
      local scene,view = simulation.new(19),layout.empty(100,8,3)
      local picks,i = {(variant-0.5)/3,direction,0.2},0
      scene.random = function() i=i+1; return picks[i] or 0.25 end
      assert(simulation.object(scene,view,cfg,'ship'))
      local object = scene.object
      assert(object.variant == variant)
      local x,y = object.x,object.y
      for _=1,8 do simulation.step(scene,view,cfg,0.05,#colors.stars) end
      assert(object.y == y and math.abs(object.x-x) == 8)
      local cells = simulation.frame(scene,view,cfg,colors)
      local left,right,bottom = math.huge,0,0
      for _,cell in ipairs(cells) do
        left,right,bottom = math.min(left,cell.x),math.max(right,cell.x),math.max(bottom,cell.y)
        assert(cell.hl == colors.ships[variant][7], 'ship color ignored')
      end
      local rows = {}
      for row=y,bottom do
        local chars = {}
        for col=left,right do
          local glyph = ' '
          for _,cell in ipairs(cells) do if cell.x == col and cell.y == row then glyph=cell.glyph end end
          chars[#chars+1] = glyph
        end
        rows[#rows+1] = table.concat(chars):gsub(' +$','')
      end
      assert(table.concat(rows,'\n') == expected[variant][object.dx == 1 and 'right' or 'left'], vim.inspect(rows))
      simulation.step(scene,layout.empty(100,8,50),cfg,0.05,#colors.stars)
      assert(scene.object == object and #simulation.frame(scene,layout.empty(100,8,50),cfg,colors) == 0)
      for _=1,120 do
        simulation.step(scene,view,cfg,0.05,#colors.stars)
        if scene.object then assert(object.y == y and object.variant == variant) end
      end
      assert(scene.object == nil)
    end
  end
]]
)

test(
  'category switches suppress existing particles, automatic spawning, and previews',
  [[
  local simulation = require('stardust.sky')
  local resolve = require('stardust.config').resolve
  local view = layout.empty(100,64,3)
  local cfg = resolve({meteor={enabled=false},objects={enabled=false}})
  assert(cfg.meteor.speed == 24, 'default meteor speed was not increased')
  local colors = require('stardust.palette').setup(cfg)
  local scene = simulation.new(19)
  for _=1,30 do simulation.step(scene,view,cfg,1/30,#colors.stars) end
  assert(#scene.stars > 0)
  cfg.enabled.stars = false
  assert(#simulation.frame(scene,view,cfg,colors) == 0)
  simulation.step(scene,view,cfg,0.1,#colors.stars)
  assert(#scene.stars == 0)
  assert(simulation.meteor(scene,view,cfg))
  cfg.enabled.meteors = false
  assert(#simulation.frame(scene,view,cfg,colors) == 0)
  simulation.step(scene,view,cfg,0.1,#colors.stars)
  assert(scene.meteor == nil and not simulation.meteor(scene,view,cfg))
  for _,kind in ipairs({'moon','planet','comet','ship'}) do
    scene = simulation.new(19)
    assert(simulation.object(scene,view,cfg,kind))
    cfg.enabled[kind .. 's'] = false
    assert(#simulation.frame(scene,view,cfg,colors) == 0)
    simulation.step(scene,view,cfg,0.1,#colors.stars)
    assert(scene.object == nil and not simulation.object(scene,view,cfg,kind))
  end
  cfg.meteor.enabled,cfg.objects.enabled = true,true
  cfg.meteor.interval,cfg.objects.interval = {1,1},{1,1}
  scene.next_meteor,scene.next_object = scene.age,scene.age
  for _=1,100 do simulation.step(scene,view,cfg,0.1,#colors.stars) end
  assert(#scene.stars == 0 and scene.meteor == nil and scene.object == nil)
  cfg.enabled.moons = true
  for _=1,20 do simulation.step(scene,view,cfg,0.1,#colors.stars) end
  assert(scene.object and scene.object.kind == 'moon', 'random spawning ignored category switches')
  reset({'one'},{enabled={stars=false,meteors=false,ships=false,moons=false,planets=false,comets=false}})
  sd.start(); advance(30)
  assert(sd.status().stars == 0 and sd.status().objects == 0 and sd.status().canvases == 0)
  assert(not sd.meteor() and not sd.object('ship') and not sd.object('comet') and not sd.object('moon') and not sd.object('planet'))
]]
)

test(
  'multiline custom ships appear on screen without painting their transparent spaces',
  [[
  local definitions = {{right={' A ','B C'},left={' a ','b c'},color='#abcdef'}}
  local cfg = require('stardust.config').resolve({stars=0,meteor={enabled=false},objects={enabled=false,ships=definitions}})
  local colors = require('stardust.palette').setup(cfg)
  local scene = require('stardust.sky').new(19)
  local view = layout.empty(100,1,3)
  assert(not require('stardust.sky').object(scene,view,cfg,'ship'), 'sprite exceeds available height')
  reset({'one'},{stars=0,objects={ships=definitions}})
  assert(sd.object('ship'))
  advance(45)
  local pixels,found = screen(),{}
  for row=2,vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].height-1 do
    for col=1,100 do
      local char = pixels[row][col]
      if char == 'A' or char == 'a' then
        assert(pixels[row+1][col] == ' ', 'transparent center was painted')
        assert(pixels[row+1][col-1] == (char == 'A' and 'B' or 'b'))
        assert(pixels[row+1][col+1] == (char == 'A' and 'C' or 'c'))
        found[#found+1] = char
      end
    end
  end
  assert(#found == 1, 'custom ship did not render completely')
  assert(#notices == 0,vim.inspect(notices))
]]
)

test(
  'mode changes clear decorations without resetting stars or a meteor flight',
  [[
  reset({'one'})
  sd.start(); advance(45)
  assert(sd.meteor())
  advance(10)
  local count = sd.status().stars
  local before = vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{details=true})[1][4].virt_lines
  vim.api.nvim_exec_autocmds('ModeChanged',{pattern='nt:t'})
  assert(#vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{}) == 0)
  rt.step(0)
  local after = vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{details=true})[1][4].virt_lines
  assert(vim.deep_equal(before,after), 'mode switch restarted the sky')
  assert(sd.status().stars == count)
]]
)

test(
  'object preview commands render on the EOF canvas and clean up on stop',
  [[
  for _, kind in ipairs({'moon','planet','comet','ship'}) do
    reset({'one'},{objects={ships={{right='╞═◉═╡',left='╞═◉═╡'}}}})
    vim.cmd('Stardust ' .. kind)
    advance(kind == 'ship' and 30 or 15)
    assert(sd.status().objects == 1)
    local glyph = kind == 'ship' and '╞' or require('stardust.sky').objects[kind][1][3]
    local found = false
    for _,mark in ipairs(vim.api.nvim_buf_get_extmarks(0,canvas_ns,0,-1,{details=true})) do
      for _,row in ipairs(mark[4].virt_lines) do
        for _,chunk in ipairs(row) do found = found or chunk[1] == glyph end
      end
    end
    assert(found, kind .. ' did not render')
    sd.stop()
    assert(sd.status().objects == 0)
  end
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

test(
  'terminal normal mode draws stars, preserving output and the other window canvas',
  [[
  reset({'file above terminal'})
  _G.filebuf, _G.filewin = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  vim.cmd('belowright split'); vim.cmd('enew')
  _G.termbuf, _G.termwin = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  _G.termchan = vim.api.nvim_open_term(termbuf,{})
  vim.wo.wrap = true
  vim.api.nvim_chan_send(termchan,'prompt> ')
  assert(vim.wait(500,function() return vim.api.nvim_buf_get_lines(termbuf,0,1,false)[1] == 'prompt> ' end,5))
  _G.term_lines = vim.api.nvim_buf_get_lines(termbuf,0,-1,false)
  sd.start(); advance(90)
  _G.check_terminal = function()
    assert(not sd.status().paused and sd.status().windows == 2, vim.inspect(sd.status()))
    assert(#vim.api.nvim_buf_get_extmarks(filebuf,canvas_ns,0,-1,{}) == 1)
    assert(#vim.api.nvim_buf_get_extmarks(termbuf,canvas_ns,0,-1,{}) == 0)
    assert(#vim.api.nvim_buf_get_extmarks(termbuf,star_ns,0,-1,{}) == 0)
    assert(vim.deep_equal(term_lines,vim.api.nvim_buf_get_lines(termbuf,0,-1,false)))
    for _,win in ipairs({filewin,termwin}) do
      local wi = vim.fn.getwininfo(win)[1]
      local found = 0
      for row=wi.winrow+1,wi.winrow+wi.height-1 do
        for col=wi.wincol+3,wi.wincol+wi.width-4 do
          local glyph = vim.fn.screenstring(row,col)
          if glyph ~= ' ' and glyph ~= '~' and glyph ~= '' then found=found+1 end
        end
      end
      assert(found > 0, 'no visible stars in window ' .. win)
    end
    assert(#notices == 0,vim.inspect(notices))
  end
  check_terminal()
]]
)

ui.request('nvim_input', 'i')
test(
  'terminal insert mode keeps both skies visible and running',
  [[
  assert(vim.api.nvim_get_mode().mode == 't')
  advance(30)
  check_terminal()
  local before = screen()
  assert(vim.wait(500,function()
    vim.cmd('redraw!')
    return not vim.deep_equal(before,screen())
  end,10), 'terminal input stopped the animation timer')
  check_terminal()
]]
)

test(
  'terminal output replaces stars and scrolling and resizing preserve decorations',
  [[
  vim.api.nvim_chan_send(termchan,'\r\n' .. string.rep('X',85))
  assert(vim.wait(500,function() return vim.api.nvim_buf_get_lines(termbuf,1,2,false)[1] == string.rep('X',85) end,5))
  vim.cmd('redraw!')
  local wi = vim.fn.getwininfo(termwin)[1]
  for col=1,85 do assert(vim.fn.screenstring(wi.winrow+1,col) == 'X') end
  vim.api.nvim_chan_send(termchan,string.rep('\r\noutput',40) .. '\r\n')
  assert(vim.wait(500,function() return vim.api.nvim_buf_line_count(termbuf) > 40 end,5))
  vim.api.nvim_win_set_height(termwin,10)
  advance(30)
  assert(sd.status().windows == 2 and sd.status().canvases == 1, vim.inspect(sd.status()))
  local view = layout.get(termwin,termbuf,require('stardust.config').resolve(),{},canvas_ns)
  assert(view and view.top > 1 and view.free == 0)
  assert(#notices == 0,vim.inspect(notices))
  sd.setup({terminals=false})
  advance(2)
  assert(sd.status().windows == 1 and not sd.status().paused)
  assert(sd.status().skipped[termwin] == 'terminals disabled')
]]
)
ui.request('nvim_input', '<C-\\><C-n>')

ui.close()
print(('%d passed, %d failed'):format(passed, failed))
vim.cmd(failed == 0 and 'qa!' or 'cquit 1')
