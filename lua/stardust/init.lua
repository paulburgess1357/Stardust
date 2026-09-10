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
  if resolved.autostart or running then
    M.start()
  end
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
    or { active = false, paused = false, windows = 0, stars = 0, canvases = 0, skipped = {} }
end

function M.meteor()
  if not M.status().active then
    M.start()
  end
  return require('stardust.runtime').meteor()
end

function M.register_commands()
  vim.api.nvim_create_user_command('Stardust', function(args)
    local action = args.args == '' and 'toggle' or args.args
    if action == 'status' then
      vim.notify(vim.inspect(M.status()), vim.log.levels.INFO, { title = 'Stardust' })
    elseif action == 'meteor' then
      if not M.meteor() then
        vim.notify('Stardust: no clear meteor path in this view', vim.log.levels.INFO)
      end
    elseif action == 'start' or action == 'stop' or action == 'toggle' then
      M[action]()
    else
      vim.notify('Stardust: expected start, stop, toggle, meteor, or status', vim.log.levels.ERROR)
    end
  end, {
    nargs = '?',
    desc = 'Twinkling stars and occasional meteors',
    force = true,
    complete = function()
      return { 'start', 'stop', 'toggle', 'meteor', 'status' }
    end,
  })
end

return M
