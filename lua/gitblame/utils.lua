local M = {}

function __FILE__() return debug.getinfo(3, 'S').source end
function __LINE__() return debug.getinfo(3, 'l').currentline end
function __FUNC__() return debug.getinfo(3, 'n').name end

local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

function M.log(text)
    print(string.format('[%s][%s-%s] %s', os.clock(), __FUNC__(), __LINE__(),
                        dump(text)))
end

---@param cmd string
---@param opts table
---@return number | 'the job id'
function M.start_job(cmd, opts)
    opts = opts or {}
    local id = vim.fn.jobstart(cmd, {
        stdout_buffered = true,
        on_stdout = function(_, data, _)
            if data and opts.on_stdout then opts.on_stdout(data) end
        end,
        on_exit = function(_, data, _)
            if opts.on_exit then opts.on_exit(data) end
        end
    })

    if opts.input then
        vim.fn.chansend(id, opts.input)
        vim.fn.chanclose(id, 'stdin')
    end

    return id
end

---@return string|nil
function M.get_filepath()
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return nil end
    if filepath:match('^term://') then return nil end
    return filepath
end

---@return number
function M.get_line_number() return vim.api.nvim_win_get_cursor(0)[1] end

---Returns a command which will be ran in `sh`. This is useful in cases
---where user's default shell is not POSIX-compliant.
---@param command string
---@return string
function M.get_posix_shell_command(command)
    return "echo '" .. command .. "' | sh"
end

return M
