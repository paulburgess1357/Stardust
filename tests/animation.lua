return {
  {
    'meteor motion is independent of FPS and remains on one diagonal',
    [[
    local sky=require('stardust.sky')
    local cfg=require('stardust.config').resolve(vim.tbl_extend('force',quiet,{stars=0,meteors=7}))
    local colors=require('stardust.palette').setup(cfg)
    local layout=require('stardust.layout')
    local view=layout.empty(200,120)
    local expected
    for _,fps in ipairs({1,2,10,30,60,120}) do
      local scene=sky.new(19); scene.random=function() return 0.75 end
      assert(sky.meteor(scene,view,cfg)); hold(scene)
      local body=scene.meteor
      for _=1,fps*2 do sky.step(scene,view,cfg,1/fps,#colors.stars) end
      local pos={body.x,body.y,body.step}
      assert(not expected or vim.deep_equal(pos,expected)); expected=pos
      for _,cell in ipairs(sky.frame(scene,view,cfg,colors)) do
        assert((cell.x-body.origin_x)*body.dx == 2*(cell.y-body.origin_y))
      end
    end
  ]],
  },
  {
    'meteors and comets keep moving behind text until their tails leave the edge',
    [[
    local sky=require('stardust.sky')
    local cfg=require('stardust.config').resolve({stars=0})
    local colors=require('stardust.palette').setup(cfg)
    local layout=require('stardust.layout')
    for _,kind in ipairs({'meteor','comet'}) do
      for _,height in ipairs({8,64}) do
        local view=layout.empty(100,height)
        local scene=sky.new(17); scene.random=function() return 0.75 end
        assert(kind == 'meteor' and sky.meteor(scene,view,cfg) or sky.object(scene,view,cfg,kind))
        hold(scene)
        local body=kind == 'meteor' and scene.meteor or scene.object
        local x=body.x
        sky.step(scene,layout.empty(100,height,50),cfg,0.5,#colors.stars)
        assert(body.x ~= x and #sky.frame(scene,layout.empty(100,height,50),cfg,colors) == 0)
        for _=1,250 do sky.step(scene,view,cfg,0.1,#colors.stars) end
        assert(scene.meteor == nil and scene.object == nil)
      end
    end
  ]],
  },
  {
    'a meteor crosses the last file line without restarting or stopping',
    [[
    local sky=require('stardust.sky')
    local create=sky.new
    local scene
    sky.new=function(seed) scene=create(seed); scene.random=function() return 0.75 end; return scene end
    local lines={}; for i=1,12 do lines[i]='x' end
    reset(lines,{stars=0,meteors=7})
    rt.step(0); sky.new=create
    local picks,index={0.75,0,0.25,0.2},0
    scene.random=function() index=index+1; return picks[index] or 0.5 end
    assert(sd.meteor()); hold(scene)
    local body=scene.meteor
    local crossed=false
    for _=1,360 do
      rt.step(1/60); vim.cmd('redraw!')
      if body.head and body.y == 13 then
        crossed=true
        assert(vim.fn.screenstring(13,body.x+1) == '✦')
      end
    end
    assert(crossed and scene.meteor == nil)
  ]],
  },
  {
    'stationary objects fade in place and expire',
    [[
    local sky=require('stardust.sky')
    local cfg=require('stardust.config').resolve({stars=0,meteors=0,showers=0})
    local colors=require('stardust.palette').setup(cfg)
    local view=require('stardust.layout').empty(100,20)
    for _,kind in ipairs({'moon','planet'}) do
      local scene=sky.new(19)
      assert(sky.object(scene,view,cfg,kind)); hold(scene)
      local object=scene.object; local x,y=object.x,object.y
      assert(#sky.frame(scene,view,cfg,colors) == 0)
      sky.step(scene,view,cfg,2,#colors.stars)
      assert(#sky.frame(scene,view,cfg,colors) > 0 and object.x == x and object.y == y)
      sky.step(scene,view,cfg,30,#colors.stars)
      assert(scene.object == nil)
    end
  ]],
  },
  {
    'ship artwork and colors are preserved in both directions',
    [[
    local sky=require('stardust.sky')
    local cfg=require('stardust.config').resolve(vim.tbl_extend('force',quiet,{stars=0,ships=6,fleet={{right={' A ','B C'},left={' a ','b c'},color='#abcdef'}}}))
    local colors=require('stardust.palette').setup(cfg)
    local view=require('stardust.layout').empty(100,20)
    for _,direction in ipairs({0.25,0.75}) do
      local scene=sky.new(19); scene.random=function() return direction end
      assert(sky.object(scene,view,cfg,'ship')); hold(scene)
      local object=scene.object
      sky.step(scene,view,cfg,3,#colors.stars)
      local cells=sky.frame(scene,view,cfg,colors)
      assert(#cells == 3)
      local chars={}
      for _,cell in ipairs(cells) do chars[cell.glyph]=true; assert(cell.hl == colors.fleet[1][7]) end
      assert(object.dx == 1 and chars.A and chars.B and chars.C or object.dx == -1 and chars.a and chars.b and chars.c)
      sky.step(scene,view,cfg,40,#colors.stars); assert(scene.object == nil)
    end
  ]],
  },
  {
    'star density follows the level and the empty area',
    [[
    local sky=require('stardust.sky')
    local layout=require('stardust.layout')
    local resolve=require('stardust.config').resolve
    local view=layout.empty(100,20)
    local counts={}
    for _,level in ipairs({1,3,10}) do
      local cfg=resolve(vim.tbl_extend('force',quiet,{stars=level}))
      local colors=require('stardust.palette').setup(cfg)
      local scene=sky.new(19)
      for _=1,600 do sky.step(scene,view,cfg,1/60,#colors.stars) end
      counts[level]=#scene.stars
      assert(#scene.stars == sky.star_target(level,view.area),'level '..level)
    end
    assert(counts[1] < counts[3] and counts[3] < counts[10])
    assert(sky.star_target(10,1000000) == 200,'density is capped per scene')
    local cfg=resolve(vim.tbl_extend('force',quiet,{stars=0}))
    local scene=sky.new(19); sky.step(scene,view,cfg,1,2)
    assert(#scene.stars == 0)
  ]],
  },
  {
    'occluded stars stay bounded and expire naturally',
    [[
    local sky=require('stardust.sky')
    local cfg=require('stardust.config').resolve(vim.tbl_extend('force',quiet,{stars=5}))
    local colors=require('stardust.palette').setup(cfg)
    local layout=require('stardust.layout')
    local view=layout.empty(100,20)
    local scene=sky.new(19)
    for _=1,60 do sky.step(scene,view,cfg,1/60,#colors.stars) end
    local stars=vim.deepcopy(scene.stars)
    sky.step(scene,layout.empty(100,20,50),cfg,0,#colors.stars)
    assert(vim.deep_equal(scene.stars,stars),'occupancy erased stars')
    assert(#sky.frame(scene,layout.empty(100,20,50),cfg,colors) == 0)
    sky.step(scene,layout.empty(100,20,50),cfg,20,#colors.stars)
    assert(#scene.stars == 0)
  ]],
  },
  {
    'the animation leaves Lua global randomness untouched',
    [[
    math.randomseed(814); local expected=math.random(); math.randomseed(814)
    reset({'hello'}); advance(); sd.stop()
    assert(math.random() == expected)
  ]],
  },
}
