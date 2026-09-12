local context = [[
  local sky=require('stardust.sky')
  local opts=vim.tbl_extend('force',quiet,{stars=0,ships=6,
    fleet={{right={' A ','BCD',' E '},left={' a ','bcd',' e '}}}})
  local cfg=require('stardust.config').resolve(opts)
  local palette=require('stardust.palette').setup(cfg)
  local view=require('stardust.layout').empty(160,40)
  local function create(seed)
    local scene=sky.new(seed)
    assert(sky.battle(scene,view,cfg))
    hold(scene)
    local ship=scene.objects[#scene.objects]
    return scene,ship,ship.battle
  end
  local function find(predicate)
    for seed=1,300 do
      local scene,ship,battle=create(seed*7919)
      if predicate(ship,battle) then return seed*7919,scene,ship,battle end
    end
    error('no matching chase')
  end
  local function advance(scene,dt,fps)
    local frames=math.floor(dt*fps)
    for _=1,frames do sky.step(scene,view,cfg,1/fps,2) end
    sky.step(scene,view,cfg,dt-frames/fps,2)
  end
  local function enemy_cells(scene)
    local result={}
    for _,cell in ipairs(sky.frame(scene,view,cfg,palette)) do
      if cell.hl == palette.enemy[7] and cell.glyph:match('[ABCDEabcde]') then
        result[#result+1]=cell
      end
    end
    return result
  end
]]

return {
  {
    'regular ship previews stay solo and automatic chases have varied arrivals and speeds',
    context .. [[
    local solo,chases=0,0
    local arrivals,speeds,lasers={},{},{}
    for seed=1,100 do
      local scene=sky.new(seed*7919)
      assert(sky.object(scene,view,cfg,'ship') and not scene.objects[1].battle)
      scene.objects={}
      assert(sky.object(scene,view,cfg))
      if scene.objects[1].battle then chases=chases+1 else solo=solo+1 end
      assert(sky.battle(scene,view,cfg))
      local battle=scene.objects[2].battle
      arrivals[#arrivals+1]=battle.arrival
      speeds[#speeds+1]=battle.speed
      lasers[#lasers+1]=battle.laser_speed
    end
    assert(solo > chases and chases > 0,'automatic ships should mostly fly solo')
    table.sort(arrivals); table.sort(speeds); table.sort(lasers)
    assert(arrivals[#arrivals]-arrivals[1] > 3,'pursuers always arrive together')
    assert(speeds[#speeds]-speeds[1] > 3 and lasers[#lasers]-lasers[1] > 20)
    cfg.battles=0
    local scene=sky.new(7919)
    assert(not sky.battle(scene,view,cfg))
    assert(sky.object(scene,view,cfg) and not scene.objects[1].battle)
    cfg.battles=10
    local every=0
    for seed=1,40 do
      scene=sky.new(seed*7919)
      assert(sky.object(scene,view,cfg))
      if scene.objects[1].battle then every=every+1 end
    end
    assert(every == 40,'level 10 should turn every automatic flight into a chase')
    cfg.battles=3
  ]],
  },
  {
    'the first bullet destroys the hull at contact in either direction and at every FPS',
    context .. [[
    for _,dx in ipairs({-1,1}) do
      local seed=find(function(ship,battle)
        local contact=battle.shots[1].contact
        return ship.dx == dx and not battle.boost_at and contact
          and battle.laser_speed-battle.enemy_speed > 25
          and contact*battle.enemy_speed < view.width-20
      end)
      local expected
      for _,fps in ipairs({1,2,10,30,60,120}) do
        local scene,ship,battle=create(seed)
        local contact=battle.shots[1].contact
        advance(scene,contact-1/30,fps)
        assert(not battle.hit and #enemy_cells(scene) == 5)
        local front,rear
        for _,cell in ipairs(sky.frame(scene,view,cfg,palette)) do
          if cell.glyph == '━' then front=math.max(front or -math.huge,cell.x*dx) end
        end
        for _,cell in ipairs(enemy_cells(scene)) do
          rear=math.min(rear or math.huge,cell.x*dx)
        end
        assert(front and rear-front > 0 and rear-front <= 3,'bullet did not approach hull')
        advance(scene,1/30,fps)
        assert(battle.hit and battle.hit.shot == battle.shots[1],'first bullet was ignored')
        assert(#enemy_cells(scene) == 0,'enemy survived contact')
        local blast=false
        for _,cell in ipairs(sky.frame(scene,view,cfg,palette)) do
          if cell.glyph == '✹' then
            blast=true
            assert(cell.x == battle.hit.x and cell.y == battle.row)
            assert(math.abs(cell.x*dx-rear) <= 1,'explosion detached from impact')
          end
        end
        assert(blast,'no impact flash')
        advance(scene,0.1,fps)
        local cells=sky.frame(scene,view,cfg,palette)
        assert(not expected or vim.deep_equal(cells,expected),'impact changes with FPS')
        expected=cells
        advance(scene,1.1,fps); assert(#enemy_cells(scene) == 0)
        sky.step(scene,view,cfg,1000,2); assert(#scene.objects == 0)
      end
    end
  ]],
  },
  {
    'slow bullets and escaping enemies miss without absorbing hits',
    context
      .. [[
    for _,boost in ipairs({false,true}) do
      local _,scene,ship,battle=find(function(_,candidate)
        return boost and candidate.boost_at and not candidate.shots[1].contact
          or not boost and not candidate.boost_at and candidate.laser_speed <= candidate.enemy_speed
      end)
      local time=boost and battle.boost_at+0.02 or battle.shots[1].at+0.1
      advance(scene,time,60)
      local function gap()
        local rear,bullet
        for _,cell in ipairs(enemy_cells(scene)) do
          rear=math.min(rear or math.huge,cell.x*ship.dx)
        end
        for _,cell in ipairs(sky.frame(scene,view,cfg,palette)) do
          if cell.glyph == '━' then bullet=math.max(bullet or -math.huge,cell.x*ship.dx) end
        end
        assert(rear and bullet and rear > bullet,'escaping enemy overlaps a bullet')
        return rear-bullet
      end
      local before=gap()
      advance(scene,0.1,60)
      assert(gap() >= before - (boost and 0 or 1),'bullet caught an escaping enemy')
      assert(not battle.hit and #enemy_cells(scene) == 5)
      sky.step(scene,view,cfg,1000,2)
      assert(not battle.hit and #scene.objects == 0,'escape did not clean up')
    end
    -- A collision beyond the far edge must not destroy an already departed ship.
    local _,scene,ship,battle=find(function(_,candidate)
      local contact=candidate.shots[1].contact
      return contact and contact*candidate.enemy_speed > view.width+20
    end)
    sky.step(scene,view,cfg,1000,2)
    assert(not battle.hit and #scene.objects == 0)
  ]],
  },
  {
    'pursuers ease into the lane visibly while the enemy stays on course',
    context .. [[
    local directions={}
    for seed=1,40 do
      local scene,ship,battle=create(seed*7919)
      local start_y=ship.y
      advance(scene,battle.align_at,60)
      local enemy_rows={}
      for _,cell in ipairs(enemy_cells(scene)) do enemy_rows[cell.glyph]=cell.y end
      assert(ship.y == start_y and battle.align_duration >= 1.1)
      local previous,changed,rows=ship.y,nil,{}
      for i=1,90 do
        sky.step(scene,view,cfg,battle.align_duration/90,2)
        if ship.y ~= previous then changed=changed or i*battle.align_duration/90 end
        assert(math.abs(ship.y-previous) <= 1,'ship jumped over rows')
        rows[ship.y]=true; previous=ship.y
        for _,cell in ipairs(enemy_cells(scene)) do
          assert(cell.y == enemy_rows[cell.glyph],'enemy moved into the firing lane')
        end
      end
      assert(changed and changed > 0.1 and vim.tbl_count(rows) >= 2)
      assert(ship.y+battle.gun_y == battle.row)
      directions[ship.dx..':'..(ship.y > start_y and 'down' or 'up')]=true
      advance(scene,battle.shots[1].at-battle.age,60)
      local laser
      for _,cell in ipairs(sky.frame(scene,view,cfg,palette)) do
        if cell.glyph == '━' then laser=cell end
      end
      assert(laser and laser.y == battle.row)
      assert(laser.x == ship.x+(battle.gun_x+1)*ship.dx,'laser missed the muzzle')
      cfg.battles=0
      sky.step(scene,view,cfg,0,2); local y=ship.y
      sky.step(scene,view,cfg,0.1,2); assert(ship.y == y)
      cfg.battles=3
    end
    assert(vim.tbl_count(directions) == 4)
  ]],
  },
  {
    'Neovim displays destruction on the first contact frame',
    context .. [[
    local create_sky=sky.new
    local scene
    sky.new=function() scene=create_sky(7919); return scene end
    reset({'x'},opts); rt.step(0); sky.new=create_sky
    assert(sd.battle())
    hold(scene)
    local battle=scene.objects[1].battle
    local contact=battle.shots[1].contact
    assert(contact,'test chase has no collision')
    rt.step(contact-1/30); vim.cmd('redraw!'); assert(not battle.hit)
    rt.step(1/30); vim.cmd('redraw!')
    assert(battle.hit)
    assert(vim.fn.screenstring(battle.row,battle.hit.x+1) == '✹','impact missing from screen')
    rt.step(1.1); vim.cmd('redraw!')
    assert(vim.fn.screenstring(battle.row,battle.hit.x+1) ~= '✹')
    sd.stop(); assert(#marks() == 0)
  ]],
  },
}
