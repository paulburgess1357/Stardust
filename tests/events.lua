return {
  {
    'showers are rare, randomized, configurable, and optional',
    [[
    local sky=require('stardust.sky')
    local resolve=require('stardust.config').resolve
    local view=require('stardust.layout').empty(120,40)
    local cfg=resolve({stars=0,objects={}})
    local times={}
    for seed=1,100 do
      local scene=sky.new(seed*1877)
      sky.step(scene,view,cfg,0,2)
      assert(scene.next_shower >= 300 and scene.next_shower <= 900)
      times[scene.next_shower]=true
    end
    assert(vim.tbl_count(times) == 100)
    cfg=resolve({stars=0,objects={},shower_interval=100})
    local scene=sky.new(41); sky.step(scene,view,cfg,0,2)
    local due=scene.next_shower
    sky.step(scene,view,cfg,due-0.1,2); assert(not scene.shower)
    sky.step(scene,view,cfg,0.2,2); assert(scene.shower)
    assert(scene.next_shower-scene.age >= 50 and scene.next_shower-scene.age <= 150)
    cfg=resolve({stars=0,objects={},shower_interval=0})
    scene=sky.new(17); sky.step(scene,view,cfg,10000,2)
    assert(not scene.shower and not scene.next_shower)
    assert(sky.shower(scene,view,cfg),'zero disables automatic showers, not previews')
    cfg=resolve({enabled={meteors=false}})
    assert(not sky.shower(sky.new(1),view,cfg))
    sky.step(scene,view,cfg,0,2); assert(not scene.shower and not scene.meteor)
  ]],
  },
  {
    'showers span a broad band and all trails finish even behind text or after resizing',
    [[
    local sky=require('stardust.sky')
    local cfg=require('stardust.config').resolve({stars=0,objects={},shower_interval=0})
    local palette=require('stardust.palette').setup(cfg)
    local layout=require('stardust.layout')
    for _,direction in ipairs({0.25,0.75}) do
      local view=layout.empty(120,40)
      local scene=sky.new(11); scene.random=function() return direction end
      scene.next_meteor=math.huge
      assert(sky.shower(scene,view,cfg)); assert(not sky.shower(scene,view,cfg))
      local left,right=120,0
      for _,body in ipairs(scene.shower.meteors) do
        left=math.min(left,body.origin_x); right=math.max(right,body.origin_x)
      end
      assert(right-left >= view.width/3 and right-left <= view.width/2)
      assert(#scene.shower.meteors >= 24 and #scene.shower.meteors <= 48)
      sky.step(scene,view,cfg,2,2)
      assert(#sky.frame(scene,view,cfg,palette) > 50,'shower too sparse')
      local hidden=layout.empty(120,40,60)
      assert(#sky.frame(scene,hidden,cfg,palette) == 0)
      sky.step(scene,hidden,cfg,0.5,2); assert(scene.shower)
      sky.step(scene,layout.empty(25,8),cfg,20,2)
      assert(not scene.shower,'shower left stale particles')
    end
  ]],
  },
  {
    'showers and battles use elapsed time at every supported frame rate',
    [[
    local sky=require('stardust.sky')
    local cfg=require('stardust.config').resolve({stars=0,objects={'ship'},shower_interval=0})
    local palette=require('stardust.palette').setup(cfg)
    local view=require('stardust.layout').empty(120,40)
    local expected
    for _,fps in ipairs({1,2,10,30,60,120}) do
      local scene=sky.new(91)
      assert(sky.shower(scene,view,cfg) and sky.battle(scene,view,cfg))
      scene.next_meteor,scene.next_object=math.huge,math.huge
      for _=1,2*fps do sky.step(scene,view,cfg,1/fps,2) end
      local cells=sky.frame(scene,view,cfg,palette)
      table.sort(cells,function(a,b) return a.y == b.y and a.x < b.x or a.y < b.y end)
      assert(not expected or vim.deep_equal(cells,expected),'different frame at FPS '..fps)
      expected=cells
      sky.step(scene,view,cfg,100,2)
      assert(not scene.object and not scene.shower)
    end
  ]],
  },
  {
    'battle previews replace active objects without warnings or disturbing other effects',
    [[
    local sky=require('stardust.sky')
    local cfg=require('stardust.config').resolve({shower_interval=0})
    local layout=require('stardust.layout')
    local view=layout.empty(120,40)
    local scene=sky.new(71)
    sky.step(scene,view,cfg,0,2)
    assert(sky.meteor(scene,view,cfg) and sky.shower(scene,view,cfg))
    local stars,meteor,shower=scene.stars,scene.meteor,scene.shower
    assert(sky.object(scene,view,cfg,'moon'))
    for _=1,8 do
      local old=scene.object
      assert(sky.battle(scene,view,cfg))
      assert(scene.object ~= old and scene.object.battle)
      assert(scene.stars == stars and scene.meteor == meteor and scene.shower == shower)
      local current=scene.object
      assert(not sky.object(scene,view,cfg,'planet') and scene.object == current)
    end
    local current=scene.object
    assert(not sky.battle(scene,layout.empty(30,10),cfg) and scene.object == current)
    cfg.enabled.ship_enemies=false
    assert(not sky.battle(scene,view,cfg) and scene.object == current)
    reset({'preview'},{stars=0,objects={'moon','ship'}})
    assert(sd.object('moon'))
    for _=1,8 do
      vim.cmd('Stardust battle')
      assert(sd.status().battles == 1 and sd.status().objects == 1)
    end
    assert(#notices == 0,vim.inspect(notices))
  ]],
  },
  {
    'showers and battles render across the last file line without covering text',
    [[
    for _,kind in ipairs({'shower','battle'}) do
      local lines={}; for i=1,12 do lines[i]='text' end
      reset(lines,{stars=0,meteors=true,objects={'ship'}})
      local sky=require('stardust.sky')
      local create=sky.new
      sd.stop()
      local scene
      sky.new=function(seed) scene=create(seed); scene.random=function() return 0.75 end; return scene end
      sd.start(); rt.step(0); sky.new=create
      local before=screen()
      vim.cmd('Stardust '..kind)
      scene.next_meteor,scene.next_object,scene.next_shower=math.huge,math.huge,math.huge
      assert(sd.status()[kind == 'shower' and 'showers' or 'battles'] == 1)
      rt.step(3.5); vim.cmd('redraw!'); preserve_text(before)
      local canvas=marks()
      assert(#canvas == 1 and #canvas[1][4].virt_lines > 0)
      local visible=false
      for row=13,28 do
        for col=6,96 do
          local char=vim.fn.screenstring(row,col)
          visible=visible or char ~= '' and char ~= ' ' and char ~= '~'
        end
      end
      assert(visible,'effect missing below the file')
      rt.step(100); vim.cmd('redraw!')
      assert(sd.status().showers == 0 and sd.status().battles == 0)
      sd.stop(); assert(#marks() == 0)
    end
  ]],
  },
}
