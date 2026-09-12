return {
  {
    'levels map to doubling frequencies with randomized waits',
    [[
    local sky=require('stardust.sky')
    local resolve=require('stardust.config').resolve
    local view=require('stardust.layout').empty(120,40)
    assert(sky.mean_interval(1) == 3600 and sky.mean_interval(7) == 56.25)
    assert(sky.mean_interval(10) > 7 and sky.mean_interval(10) < 7.1)
    local cfg=resolve(vim.tbl_extend('force',quiet,{stars=0,showers=3}))
    local times={}
    for seed=1,100 do
      local scene=sky.new(seed*1877)
      sky.step(scene,view,cfg,0,2)
      assert(scene.due.shower >= 450 and scene.due.shower <= 1350,scene.due.shower)
      assert(not scene.due.meteor and not scene.due.moon)
      times[scene.due.shower]=true
    end
    assert(vim.tbl_count(times) == 100)
    cfg=resolve(vim.tbl_extend('force',quiet,{stars=0,showers=10}))
    local scene=sky.new(41); sky.step(scene,view,cfg,0,2)
    local due=scene.due.shower
    assert(due >= 3.5 and due <= 10.6)
    sky.step(scene,view,cfg,due-0.1,2); assert(not scene.shower)
    sky.step(scene,view,cfg,0.2,2); assert(scene.shower)
    assert(scene.due.shower-scene.age >= 3.5 and scene.due.shower-scene.age <= 10.6)
    cfg=resolve(vim.tbl_extend('force',quiet,{stars=0}))
    scene=sky.new(17); sky.step(scene,view,cfg,10000,2)
    assert(not scene.shower and not scene.due.shower)
    assert(not sky.shower(scene,view,cfg),'level 0 also disables previews')
    assert(not sky.meteor(scene,view,cfg) and not sky.object(scene,view,cfg,'moon'))
    cfg=resolve({meteors=0})
    assert(sky.shower(sky.new(1),view,cfg),'showers do not depend on lone meteors')
  ]],
  },
  {
    'due objects wait for a free slot instead of losing their turn',
    [[
    local sky=require('stardust.sky')
    local cfg=require('stardust.config').resolve(vim.tbl_extend('force',quiet,{stars=0,moons=10,planets=10}))
    local view=require('stardust.layout').empty(120,40)
    local scene=sky.new(23)
    sky.step(scene,view,cfg,0,2)
    assert(scene.due.moon and scene.due.planet)
    local first=math.min(scene.due.moon,scene.due.planet)
    sky.step(scene,view,cfg,first+0.01,2)
    assert(scene.object,'nothing appeared at its due time')
    local other=scene.object.kind == 'moon' and 'planet' or 'moon'
    local pending=scene.due[other]
    for _=1,600 do sky.step(scene,view,cfg,1/10,2) end
    assert(scene.due[other] ~= pending,'the waiting kind never got its turn')
    local seen={}
    for _=1,2000 do sky.step(scene,view,cfg,1/10,2); if scene.object then seen[scene.object.kind]=true end end
    assert(seen.moon and seen.planet)
  ]],
  },
  {
    'showers span a broad band and all trails finish even behind text or after resizing',
    [[
    local sky=require('stardust.sky')
    local cfg=require('stardust.config').resolve(vim.tbl_extend('force',quiet,{stars=0,showers=1}))
    local palette=require('stardust.palette').setup(cfg)
    local layout=require('stardust.layout')
    for _,direction in ipairs({0.25,0.75}) do
      local view=layout.empty(120,40)
      local scene=sky.new(11); scene.random=function() return direction end
      hold(scene)
      assert(sky.shower(scene,view,cfg)); assert(not sky.shower(scene,view,cfg))
      hold(scene)
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
    local cfg=require('stardust.config').resolve({stars=0,moons=0,planets=0,comets=0,showers=1})
    local palette=require('stardust.palette').setup(cfg)
    local view=require('stardust.layout').empty(120,40)
    local expected
    for _,fps in ipairs({1,2,10,30,60,120}) do
      local scene=sky.new(91)
      assert(sky.shower(scene,view,cfg) and sky.battle(scene,view,cfg))
      hold(scene)
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
    local cfg=require('stardust.config').resolve({showers=1})
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
    cfg.battles=0
    assert(not sky.battle(scene,view,cfg) and scene.object == current)
    reset({'preview'},{stars=0,moons=6,ships=6})
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
      reset(lines,{stars=0,meteors=7,showers=3,ships=6})
      local sky=require('stardust.sky')
      local create=sky.new
      sd.stop()
      local scene
      sky.new=function(seed) scene=create(seed); scene.random=function() return 0.75 end; return scene end
      sd.start(); rt.step(0); sky.new=create
      local before=screen()
      vim.cmd('Stardust '..kind)
      hold(scene)
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
