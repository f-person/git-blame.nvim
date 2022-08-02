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

---Merges map entries of `source` into `target`.
---@param source table<any, any>
---@param target table<any, any>
function M.merge_map(source, target)
    for k, v in pairs(source) do target[k] = v end
end

---Keeping it outside the function improves performance by not
---finding the OS every time.
local open_cmd
---Attempts to open a given URL in the system default browser, regardless of the OS.
---Source: https://stackoverflow.com/a/18864453/9714875
---@param url string
function M.launch_url(url)
    if not open_cmd then
        if package.config:sub(1, 1) == '\\' then
            open_cmd = function(_url)
                M.start_job(string.format('start "%s"', _url))
            end
        elseif (io.popen("uname -s"):read '*a'):match 'Darwin' then
            open_cmd = function(_url)
                M.start_job(string.format('open "%s"', _url))
            end
        else
            open_cmd = function(_url)
                M.start_job(string.format('xdg-open "%s"', _url))
            end
        end
    end

    open_cmd(url)
end

---@param text string
function M.copy_to_clipboard(text) vim.fn.setreg('+', text) end

return M
