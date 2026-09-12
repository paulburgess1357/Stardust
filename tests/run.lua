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
  _G.sd = require('stardust')
  _G.rt = require('stardust.runtime')
  _G.canvas_ns = vim.api.nvim_get_namespaces()['stardust.canvas']
  _G.star_ns = vim.api.nvim_get_namespaces()['stardust.stars']
  _G.notices = {}
  vim.notify = function(message) notices[#notices+1]=message end
  _G.reset = function(lines, opts)
    sd.stop()
    vim.cmd('silent! tabonly!'); vim.cmd('silent! only!'); vim.cmd('enew!')
    vim.wo.wrap=false; vim.wo.conceallevel=0; vim.wo.diff=false; vim.wo.foldenable=false
    vim.wo.number=false; vim.wo.relativenumber=false; vim.wo.signcolumn='no'
    vim.wo.scrolloff=0; vim.wo.winbar=''; vim.wo.list=false
    vim.api.nvim_buf_set_lines(0,0,-1,false,lines or {'hello'})
    vim.api.nvim_win_set_cursor(0,{1,0})
    sd.setup(vim.tbl_extend('force',{meteors=false,objects={}},opts or {}))
    _G.notices={}
    vim.cmd('redraw!')
  end
  _G.advance = function(n)
    for _=1,n or 120 do rt.step(1/60) end
    vim.cmd('redraw!')
    assert(#notices == 0,vim.inspect(notices))
  end
  _G.screen = function()
    local rows={}
    for row=1,vim.o.lines do
      rows[row]={}
      for col=1,vim.o.columns do rows[row][col]=vim.fn.screenstring(row,col) end
    end
    return rows
  end
  _G.preserve_text = function(before)
    local after=screen()
    for row=1,vim.o.lines-2 do
      for col,char in ipairs(before[row]) do
        if char ~= ' ' and char ~= '' and char ~= '~' then
          assert(after[row][col] == char, ('text covered at %d:%d: %s -> %s'):format(row,col,char,after[row][col]))
        end
      end
    end
  end
  _G.marks = function(buf)
    return vim.api.nvim_buf_get_extmarks(buf or 0,canvas_ns,0,-1,{details=true})
  end
  _G.find_star = function()
    for row=2,26 do
      for col=15,96 do
        local glyph=vim.fn.screenstring(row,col)
        if glyph == '·' or glyph == '∘' or glyph == '✧' or glyph == '✦' then
          return row,col,glyph
        end
      end
    end
    error('no visible star')
  end
]])

test(
  'appearance options validate and copy user data',
  [[
  local resolve=require('stardust.config').resolve
  for _,opts in ipairs({{fps=0},{fps=121},{fps=0/0},{fps={min=30,max=60}},
    {stars=-1},{stars=math.huge},{stars=1.5},{meteors=1},{objects=false},{objects={'saturn'}},
    {shower_interval=-1},{shower_interval=0/0},{shower_interval=math.huge},{shower_interval=1.5},
    {shower_interval=false},{shower_interval=86401},{enabled={ship_enemies=1}},
    {enabled=false},{enabled={stars=1}},{enabled={unknown=true}},
    {enabled={moons=false},objects={'moon','moon'}},
    {objects={'moon','moon'}},{colors=false},{colors={stars={}}},{colors={ships='red'}},
    {colors={unknown='#ffffff'}},{ships={}},{ships={{right='x'}}},
    {ships={{right='x',left='x',wat=true}}},{ships={{right='界',left='x'}}},
    {ships={{right='x\ny',left='x'}}},{ships={{right='x',left='x',color=false}}},
    {ships={{right=string.rep('x',17),left='x'}}},{cursor_row=true},{autostart=true}}) do
    assert(not pcall(resolve,opts),vim.inspect(opts))
  end
  local input={colors={stars={'#abcdef'}},ships={{right={'AB'},left={'ba'}}}}
  local cfg=resolve(input)
  cfg.colors.stars[1]='#000000'; cfg.ships[1].right[1]='changed'
  assert(input.colors.stars[1] == '#abcdef' and input.ships[1].right[1] == 'AB')
  assert(#resolve({objects={}}).objects == 0)
]]
)

test(
  'category booleans disable spawning and previews without changing other defaults',
  [[
  local resolve=require('stardust.config').resolve
  local cfg=resolve({stars=24,enabled={ships=false}})
  assert(cfg.stars == 24 and cfg.meteors and cfg.kinds.moon and not cfg.kinds.ship)
  assert(vim.deep_equal(cfg.objects,{'moon','planet','comet'}))
  for _,kind in ipairs({'moon','planet','comet','ship'}) do
    sd.setup({enabled={[kind..'s']=false}})
    assert(not sd.object(kind))
  end
  sd.setup({enabled={stars=false,meteors=false,moons=false,planets=false,comets=false,ships=false}})
  rt.step(0)
  assert(sd.status().stars == 0 and sd.status().canvases == 0)
  assert(not sd.meteor())
]]
)

test(
  'setup starts automatically and rendering preserves text, undo, and transparency',
  [[
  local lines={}; for i=1,80 do lines[i]='    local value = "界"' end
  reset(lines)
  vim.api.nvim_set_hl(0,'Normal',{fg='#ffffff'})
  vim.api.nvim_exec_autocmds('ColorScheme',{})
  local tick,undo=vim.api.nvim_buf_get_changedtick(0),vim.fn.undotree().seq_cur
  vim.bo.modified=false
  local before=screen()
  advance()
  assert(sd.status().active and sd.status().stars > 0)
  find_star(); preserve_text(before)
  assert(vim.deep_equal(lines,vim.api.nvim_buf_get_lines(0,0,-1,false)))
  assert(vim.api.nvim_buf_get_changedtick(0) == tick and vim.fn.undotree().seq_cur == undo and not vim.bo.modified)
  assert(#vim.api.nvim_buf_get_extmarks(0,star_ns,0,-1,{}) == 0)
  for name in pairs(vim.api.nvim_get_hl(0,{})) do
    if name:match('^Stardust') then assert(vim.api.nvim_get_hl(0,{name=name}).bg == nil,name) end
  end
]]
)

test(
  'colors adapt to dark, light, and transparent themes without setting a background',
  [[
  reset({'theme check'})
  local normal=vim.api.nvim_get_hl(0,{name='Normal'})
  local background=vim.o.background
  local function brightness(color)
    local r=math.floor(color/65536)%256
    local g=math.floor(color/256)%256
    local b=color%256
    return (r*0.2126+g*0.7152+b*0.0722)/255
  end
  for _,theme in ipairs({'dark','light'}) do
    vim.o.background=theme
    for _,transparent in ipairs({false,true}) do
      local bg=theme == 'dark' and 0x121418 or 0xf5f5f0
      vim.api.nvim_set_hl(0,'Normal',{fg=theme == 'dark' and 0xffffff or 0x111111,bg=not transparent and bg or nil})
      vim.api.nvim_exec_autocmds('ColorScheme',{})
      for _,prefix in ipairs({'StardustStar1_','StardustMeteor','StardustShip','StardustEnemy','StardustLaser'}) do
        local bright=vim.api.nvim_get_hl(0,{name=prefix..'8'})
        local dim=vim.api.nvim_get_hl(0,{name=prefix..'1'})
        local contrast=math.abs(brightness(bright.fg)-brightness(bg))
        assert(contrast > 0.3,prefix..' lacks contrast on '..theme)
        assert(contrast > math.abs(brightness(dim.fg)-brightness(bg)))
        assert(bright.bg == nil and dim.bg == nil)
      end
      assert(vim.api.nvim_get_hl(0,{name='Normal'}).bg == (not transparent and bg or nil))
    end
  end
  vim.o.background='dark'; vim.api.nvim_set_hl(0,'Normal',{fg=0xffffff})
  vim.api.nvim_exec_autocmds('ColorScheme',{})
  local dark=vim.api.nvim_get_hl(0,{name='StardustStar1_8'}).fg
  vim.o.background='light'
  assert(vim.api.nvim_get_hl(0,{name='StardustStar1_8'}).fg ~= dark,'background option did not refresh palette')
  vim.o.background=background; vim.api.nvim_set_hl(0,'Normal',normal)
  vim.api.nvim_exec_autocmds('ColorScheme',{})
]]
)

test(
  'moving the cursor through the screen does not clear stars or restart them',
  [[
  local lines={}; for i=1,80 do lines[i]='code' end
  reset(lines); advance()
  local before=screen()
  local count=sd.status().stars
  for row=1,26 do
    vim.api.nvim_win_set_cursor(0,{row,0})
    rt.step(0); vim.cmd('redraw!')
    for col=15,96 do
      assert(vim.fn.screenstring(row,col) == before[row][col], 'cursor erased a star')
    end
  end
  vim.api.nvim_win_set_cursor(0,{1,0}); rt.step(0); vim.cmd('redraw!')
  assert(vim.deep_equal(before,screen()),'cursor movement changed the sky')
  assert(sd.status().stars == count)
]]
)

test(
  'text temporarily hides stars without deleting them',
  [[
  local lines={}; for i=1,80 do lines[i]='x' end
  reset(lines); advance()
  local row,col,glyph=find_star()
  vim.api.nvim_buf_set_lines(0,row-1,row,false,{string.rep('Z',98)})
  rt.step(0); vim.cmd('redraw!')
  assert(vim.fn.screenstring(row,col) == 'Z')
  vim.api.nvim_buf_set_lines(0,row-1,row,false,{'x'})
  rt.step(0); vim.cmd('redraw!')
  assert(vim.fn.screenstring(row,col) == glyph,'occlusion deleted or restarted the star')
]]
)

test(
  'startup dashboards and other nofile buffers animate like normal buffers',
  [[
  for _,ft in ipairs({'snacks_dashboard','alpha','dashboard','custom_startup'}) do
    reset({'','','','                    NEOVIM                    ','','                 [r] Recent files','' })
    vim.bo.buftype='nofile'; vim.bo.filetype=ft; vim.bo.modifiable=false
    local before=screen()
    advance()
    assert(sd.status().windows == 1 and sd.status().canvases == 1,ft)
    find_star(); preserve_text(before)
    assert(not vim.bo.modifiable and vim.api.nvim_buf_line_count(0) == 7)
  end
]]
)

test(
  'wrapped text, tabs, Unicode, winbars, folds, and diff retain visible stars',
  [[
  for _,mode in ipairs({'wrap','linebreak','tabs','winbar','fold','diff','conceal','horizontal'}) do
    local lines={}
    for i=1,80 do lines[i]= (mode == 'wrap' or mode == 'linebreak')
      and string.rep('word ',24) or '\t界\tvalue' end
    reset(lines)
    if mode == 'wrap' or mode == 'linebreak' then vim.wo.wrap=true; vim.wo.linebreak=mode == 'linebreak' end
    if mode == 'tabs' then vim.bo.tabstop=3; vim.bo.vartabstop='3,5' end
    if mode == 'winbar' then vim.wo.winbar=' Stardust '; vim.wo.number=true; vim.wo.signcolumn='yes' end
    if mode == 'fold' then vim.wo.foldenable=true; vim.cmd('2,20fold') end
    if mode == 'diff' then vim.wo.diff=true end
    if mode == 'conceal' then vim.wo.conceallevel=2; vim.cmd('syntax match TestConceal /value/ conceal cchar=*') end
    if mode == 'horizontal' then vim.cmd('normal! 8zl') end
    sd.stop(); vim.cmd('redraw!'); local before=screen(); sd.start(); advance()
    preserve_text(before)
    assert(sd.status().windows == 1 and sd.status().stars > 0,mode .. ': ' .. vim.inspect(sd.status()))
    find_star()
  end
]]
)

test(
  'late semantic highlights do not hide the sky; diagnostic text wins',
  [[
  for _,count in ipairs({3,80}) do
    local lines={}; for i=1,count do lines[i]='local value = 1' end
    reset(lines); advance()
    local tick=vim.api.nvim_buf_get_changedtick(0)
    local ns=vim.api.nvim_create_namespace('test.semantic')
    for i=1,800 do vim.api.nvim_buf_set_extmark(0,ns,i%math.min(count,24),0,{end_col=5,hl_group='Keyword'}) end
    assert(vim.api.nvim_buf_get_changedtick(0) == tick)
    advance(30); find_star()
    assert(sd.status().windows == 1)
    vim.api.nvim_buf_set_extmark(0,ns,1,0,{virt_text={{string.rep('D',95),'Normal'}},virt_text_win_col=2,priority=0})
    vim.cmd('redraw!')
    for col=3,97 do assert(vim.fn.screenstring(2,col) == 'D') end
  end
]]
)

test(
  'virtual decoration limits and virtual lines protect occupied cells without disabling a window',
  [[
  reset({'one','two','three'})
  local ns=vim.api.nvim_create_namespace('test.decorations')
  for _=1,512 do vim.api.nvim_buf_set_extmark(0,ns,1,0,{virt_text={{'hint','Normal'}}}) end
  advance(); assert(sd.status().active and sd.status().canvases == 1)
  vim.api.nvim_buf_clear_namespace(0,ns,0,-1)
  vim.api.nvim_buf_set_extmark(0,ns,1,0,{virt_lines={{{'DIAGNOSTIC','Normal'}}}})
  advance(); assert(sd.status().windows == 1)
  for col=1,10 do assert(vim.fn.screenstring(3,col) == ('DIAGNOSTIC'):sub(col,col)) end
  assert(vim.fn.screenstring(4,1) == 't')
]]
)

test(
  'same-buffer splits share a bounded EOF canvas and keep their views',
  [[
  reset({'one','two','three'})
  vim.cmd('vsplit'); vim.cmd('vertical resize 32')
  local views={}
  for _,win in ipairs(vim.api.nvim_list_wins()) do views[win]=vim.api.nvim_win_call(win,vim.fn.winsaveview) end
  advance()
  assert(#marks() == 1 and sd.status().windows == 2)
  for win,view in pairs(views) do assert(vim.deep_equal(view,vim.api.nvim_win_call(win,vim.fn.winsaveview))) end
  vim.cmd('only'); advance(2)
  assert(#marks() == 1)
]]
)

test(
  'scrolling and edits discard obsolete EOF decorations before repainting',
  [[
  local lines={}; for i=1,80 do lines[i]='line '..i end
  reset(lines); vim.cmd('normal! Gzt'); advance()
  assert(#marks() == 1)
  vim.cmd('normal! ggzt'); vim.cmd('redraw!')
  assert(#marks() == 0)
  rt.step(0); assert(sd.status().canvases == 0)
  reset({'one'}); advance()
  vim.api.nvim_buf_set_lines(0,1,1,false,{'NEW SECOND LINE','NEW THIRD LINE'})
  assert(#marks() == 0)
  vim.cmd('redraw!')
  assert(vim.fn.screenstring(2,1) == 'N' and vim.fn.screenstring(3,1) == 'N')
  advance(2); assert(#marks() == 1)
]]
)

for _, mode in ipairs({ { ':echo "pending"', 'c' }, { 'v', 'v' }, { 'R', 'R' } }) do
  ui.lua([[reset({'one','two','three'}); advance()]])
  ui.request('nvim_input', mode[1])
  test(
    'animation continues in ' .. mode[2] .. ' mode',
    [[
    local before=marks()
    assert(#before == 1)
    assert(vim.wait(750,function() return not vim.deep_equal(before,marks()) end,10),'animation paused')
    assert(sd.status().active and #marks() == 1)
    if vim.api.nvim_get_mode().mode == 'c' then assert(vim.fn.getcmdline() == 'echo "pending"') end
    assert(#notices == 0,vim.inspect(notices))
  ]]
  )
  ui.request('nvim_input', '<Esc>')
end

test(
  'focus loss keeps the sky visible and animated',
  [[
  reset({'one'}); advance()
  local before=marks()
  vim.api.nvim_exec_autocmds('FocusLost',{})
  assert(#marks() == 1)
  assert(vim.wait(750,function() return not vim.deep_equal(before,marks()) end,10))
  vim.api.nvim_exec_autocmds('FocusGained',{})
]]
)

ui.lua([[
  reset({'one','two','three'})
  local buf=vim.api.nvim_create_buf(false,true)
  vim.api.nvim_buf_set_lines(buf,0,-1,false,{'COMMAND POPUP','pending command'})
  _G.popup=vim.api.nvim_open_win(buf,false,{relative='editor',row=9,col=35,width=28,height=2,style='minimal',border='single',zindex=200})
  advance()
]])
ui.request('nvim_input', ':echo "pending"')
test(
  'command popups remain readable above the animated sky',
  [[
  advance(10)
  local label='COMMAND POPUP'
  for col=1,#label do assert(vim.fn.screenstring(11,36+col) == label:sub(col,col)) end
  assert(vim.fn.getcmdline() == 'echo "pending"')
  assert(#marks() == 1)
]]
)
ui.request('nvim_input', '<Esc>')
ui.lua([[vim.api.nvim_win_close(popup,true)]])

test(
  'floating windows receive no stars or virtual lines',
  [[
  reset({'body'})
  local buf=vim.api.nvim_create_buf(false,true)
  vim.api.nvim_buf_set_lines(buf,0,-1,false,{'hover doc','signature'})
  local win=vim.api.nvim_open_win(buf,false,{relative='editor',row=5,col=20,width=50,height=8,style='minimal',border='single'})
  advance()
  assert(sd.status().windows == 1 and sd.status().skipped[win] == 'floating window')
  assert(#marks(buf) == 0 and #marks() == 1)
  for row=7,14 do for col=22,70 do
    local glyph=vim.fn.screenstring(row,col)
    assert(glyph ~= '·' and glyph ~= '∘' and glyph ~= '✧' and glyph ~= '✦','star inside a float at '..row..':'..col)
  end end
  vim.api.nvim_win_close(win,true)
]]
)

test(
  'terminal input and output use the same placement rules',
  [[
  reset({'file'})
  _G.filebuf=vim.api.nvim_get_current_buf()
  vim.cmd('belowright split'); vim.cmd('enew')
  _G.termbuf=vim.api.nvim_get_current_buf()
  _G.termchan=vim.api.nvim_open_term(termbuf,{})
  vim.wo.wrap=true
  vim.api.nvim_chan_send(termchan,'prompt> ')
  assert(vim.wait(500,function() return vim.api.nvim_buf_get_lines(termbuf,0,1,false)[1] == 'prompt> ' end,5))
  _G.terminal_text=vim.api.nvim_buf_get_lines(termbuf,0,-1,false)
  advance()
  assert(sd.status().windows == 2 and #marks(termbuf) == 0)
  assert(vim.deep_equal(terminal_text,vim.api.nvim_buf_get_lines(termbuf,0,-1,false)))
  assert(#marks(filebuf) == 1)
]]
)
ui.request('nvim_input', 'i')
test(
  'terminal input does not pause any view',
  [[
  assert(vim.api.nvim_get_mode().mode == 't')
  local before=marks(filebuf)
  assert(vim.wait(750,function() return not vim.deep_equal(before,marks(filebuf)) end,10))
  assert(vim.deep_equal(terminal_text,vim.api.nvim_buf_get_lines(termbuf,0,-1,false)))
  vim.api.nvim_chan_send(termchan,'\r\n'..string.rep('X',85))
  assert(vim.wait(500,function() return vim.api.nvim_buf_get_lines(termbuf,1,2,false)[1] == string.rep('X',85) end,5))
  vim.cmd('redraw!')
  local row=vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].winrow+1
  for col=1,85 do assert(vim.fn.screenstring(row,col) == 'X') end
]]
)
ui.request('nvim_input', '<C-\\><C-n>')

test(
  'invalid setup preserves a running sky; repeated start and stop clean up',
  [[
  reset({'one'})
  for _=1,8 do sd.setup(); advance(2); sd.stop() end
  sd.setup(); assert(not pcall(sd.setup,{fps=0})); assert(sd.status().active)
  sd.start(); advance(2); sd.stop(); sd.stop()
  vim.wait(100,function() return false end,10)
  assert(not sd.status().active and #marks() == 0)
  for _,event in ipairs(vim.api.nvim_get_autocmds({})) do assert(event.group_name ~= 'StardustRuntime') end
]]
)

test(
  'preview commands and category choices stay consistent',
  [[
  for _,kind in ipairs({'meteor','moon','planet','comet','ship'}) do
    reset({'one'},{meteors=true,objects={'moon','planet','comet','ship'}})
    vim.cmd('Stardust '..kind); advance(30)
    assert(sd.status().active and #marks() == 1)
    assert(kind == 'meteor' and not sd.meteor() or kind ~= 'meteor' and not sd.object(kind))
  end
  sd.setup({stars=0,meteors=false,objects={}}); rt.step(0)
  assert(sd.status().stars == 0 and sd.status().canvases == 0)
  assert(not sd.meteor() and not sd.object('ship'))
]]
)

test(
  'runtime errors stop once and remove decorations',
  [[
  reset({'one'}); advance()
  local layout=require('stardust.layout')
  local get=layout.get
  layout.get=function() error('intentional test failure') end
  vim.cmd('redraw!')
  assert(vim.wait(500,function() return not sd.status().active end,5))
  layout.get=get
  assert(#marks() == 0 and #notices == 1)
]]
)

for _, case in ipairs(dofile(root .. '/tests/animation.lua')) do
  test(case[1], case[2])
end
for _, file in ipairs({ 'events', 'battle' }) do
  for _, case in ipairs(dofile(root .. '/tests/' .. file .. '.lua')) do
    test(case[1], case[2])
  end
end
ui.close()
print(('%d passed, %d failed'):format(passed, failed))
vim.cmd(failed == 0 and 'qa!' or 'cquit 1')
