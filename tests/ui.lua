-- A real Neovim UI over stdio RPC, using only Neovim's bundled Lua libraries.
local M = {}

function M.start(root, width, height)
  local uv = vim.uv
  local input, output, errors = uv.new_pipe(false), uv.new_pipe(false), uv.new_pipe(false)
  local unpack = vim.mpack.Unpacker()
  local replies, stderr, sequence = {}, {}, 0
  local process, pid = uv.spawn(vim.v.progpath, {
    args = {
      '--embed',
      '--headless',
      '-u',
      'NONE',
      '-i',
      'NONE',
      '--cmd',
      'set noswapfile noundofile nomodeline',
    },
    stdio = { input, output, errors },
    cwd = root,
  }, function() end)
  assert(process, pid)
  output:read_start(function(err, chunk)
    assert(not err, err)
    if not chunk then
      return
    end
    local offset = 1
    while offset <= #chunk do
      local message
      message, offset = unpack(chunk, offset)
      if message and message[1] == 1 then
        replies[message[2]] = message
      end
    end
  end)
  errors:read_start(function(_, chunk)
    if chunk then
      stderr[#stderr + 1] = chunk
    end
  end)
  local client = {}
  function client.request(method, ...)
    sequence = sequence + 1
    local id = sequence
    input:write(vim.mpack.encode({ 0, id, method, { ... } }))
    assert(
      vim.wait(10000, function()
        return replies[id] ~= nil
      end, 1),
      'RPC timeout: ' .. method .. table.concat(stderr)
    )
    local reply = replies[id]
    replies[id] = nil
    assert(reply[3] == vim.NIL, vim.inspect(reply[3]))
    return reply[4]
  end
  function client.lua(code, ...)
    return client.request('nvim_exec_lua', code, { ... })
  end
  function client.close()
    process:kill('sigterm')
    for _, handle in ipairs({ input, output, errors, process }) do
      if not handle:is_closing() then
        handle:close()
      end
    end
  end
  client.request('nvim_ui_attach', width or 100, height or 32, { rgb = true, ext_linegrid = true })
  client.lua('vim.opt.rtp:prepend(...); vim.o.termguicolors = true; vim.o.wrap = false', root)
  return client
end

return M
