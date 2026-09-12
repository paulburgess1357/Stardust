local M = {}
local config = require('stardust.config')
local options

function M.setup(opts)
  local resolved = config.resolve(opts)
  local runtime = package.loaded['stardust.runtime']
  local running = runtime and runtime.status().active
  if running then
    runtime.stop()
  end
  options = resolved
  M.register_commands()
  M.start()
end

function M.start()
  options = options or config.resolve()
  require('stardust.runtime').start(options)
end

function M.stop()
  local runtime = package.loaded['stardust.runtime']
  if runtime then
    runtime.stop()
  end
end

function M.toggle()
  if M.status().active then
    M.stop()
  else
    M.start()
  end
end

function M.status()
  local runtime = package.loaded['stardust.runtime']
  return runtime and runtime.status()
    or {
      active = false,
      windows = 0,
      stars = 0,
      objects = 0,
      showers = 0,
      battles = 0,
      canvases = 0,
      skipped = {},
      fps = 0,
    }
end

for _, kind in ipairs({ 'meteor', 'shower', 'battle' }) do
  M[kind] = function()
    if not M.status().active then
      M.start()
    end
    return require('stardust.runtime')[kind]()
  end
end

function M.object(kind)
  if kind ~= nil and not require('stardust.sky').objects[kind] then
    error('stardust: object must be moon, planet, comet, or ship')
  end
  if not M.status().active then
    M.start()
  end
  return require('stardust.runtime').object(kind)
end

function M.register_commands()
  vim.api.nvim_create_user_command('Stardust', function(args)
    local action = args.args == '' and 'toggle' or args.args
    if action == 'status' then
      vim.notify(vim.inspect(M.status()), vim.log.levels.INFO, { title = 'Stardust' })
    elseif action == 'meteor' or action == 'shower' or action == 'battle' then
      if not M[action]() then
        vim.notify(
          action == 'battle' and 'Stardust: battles disabled or no room for a chase in this view'
            or 'Stardust: effect disabled, already active, or no room in this view',
          vim.log.levels.INFO
        )
      end
    elseif action == 'moon' or action == 'planet' or action == 'comet' or action == 'ship' then
      if not M.object(action) then
        vim.notify(
          'Stardust: object disabled or no room for another in this view',
          vim.log.levels.INFO
        )
      end
    elseif action == 'start' or action == 'stop' or action == 'toggle' then
      M[action]()
    else
      vim.notify(
        'Stardust: expected start, stop, toggle, meteor, shower, battle, moon, planet, comet, ship, or status',
        vim.log.levels.ERROR
      )
    end
  end, {
    nargs = '?',
    desc = 'Twinkling stars, meteors, and celestial objects',
    force = true,
    complete = function()
      return {
        'start',
        'stop',
        'toggle',
        'meteor',
        'shower',
        'battle',
        'moon',
        'planet',
        'comet',
        'ship',
        'status',
      }
    end,
  })
end

return M
