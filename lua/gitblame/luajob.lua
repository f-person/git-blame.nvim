-- https://github.com/TravonteD/luajob
local M = {}

local function close_safely(handle)
    if not handle:is_closing() then handle:close() end
end

function M:new(o)
    o = o or {}
    for n, f in pairs(o) do self[n] = f end
    setmetatable(o, self)
    self.__index = self
    return o
end

function M.send(data)
    M.stdin:write(data)
    M.stdin:shutdown()
end

function M.stop()
    close_safely(M.stdin)
    close_safely(M.stderr)
    close_safely(M.stdout)
    close_safely(M.handle)
end

function M.shutdown(code, signal)
    if M.on_exit then M.on_exit(code, signal) end
    if M.on_stdout then M.stdout:read_stop() end
    if M.on_stderr then M.stderr:read_stop() end
    M.stop()
end

function M.options()
    local options = {}
    local args = vim.fn.split(M.cmd, ' ')

    M.stdin = vim.loop.new_pipe(false)
    M.stdout = vim.loop.new_pipe(false)
    M.stderr = vim.loop.new_pipe(false)

    options.command = table.remove(args, 1)
    options.args = args
    options.stdio = {M.stdin, M.stdout, M.stderr}

    if M.cwd then options.cwd = M.cwd end

    if M.env then options.env = M.env end

    if M.detach then options.detach = M.detach end

    return options
end

function M.start()
    local options = M.options()
    M.handle = vim.loop.spawn(options.command, options,
                              vim.schedule_wrap(M.shutdown))
    if M.on_stdout then M.stdout:read_start(vim.schedule_wrap(M.on_stdout)) end
    if M.on_stderr then M.stderr:read_start(vim.schedule_wrap(M.on_stderr)) end
end
return M
