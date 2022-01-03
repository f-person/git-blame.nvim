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

return M
