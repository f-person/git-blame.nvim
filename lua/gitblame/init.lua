local luajob = require('gitblame/luajob')

---@type integer
local NAMESPACE_ID = 2

---@type table<string, string>
local last_position = {}

---@type table<string, table>
local files_data = {}

---@type string
local current_author

local function clear_virtual_text()
    vim.api.nvim_buf_clear_namespace(0, NAMESPACE_ID, 0, -1)
end

---@param s string
local function get_lines(s)
    if s:sub(-1) ~= "\n" then s = s .. "\n" end
    return s:gmatch("(.-)\n")
end

---@param blames string[]
---@param filepath string
---@param blame_output string
local function process_blame_output(blames, filepath, output)
    local info
    for line in get_lines(output) do
        local message = line:match('^([A-Za-z0-9]+) ([0-9]+) ([0-9]+) ([0-9]+)')
        if message then
            local parts = {}
            for part in line:gmatch("%w+") do
                table.insert(parts, part)
            end

            local startline = tonumber(parts[3])
            info = {
                startline = startline,
                sha = parts[1],
                endline = startline + tonumber(parts[4]) - 1
            }

            if parts[1]:match('^0+$') == nil then
                for _, found_info in ipairs(blames) do
                    if found_info.sha == parts[1] then
                        info.author = found_info.author
                        info.date = found_info.date
                        info.summary = found_info.summary
                        break
                    end
                end
            end

            table.insert(blames, info)
        elseif info then
            if line:match('^author ') then
                local author = line:gsub('^author ', '')
                info.author = author == current_author and 'You' or author
            elseif line:match('^author%-time ') then
                local text = line:gsub('^author%-time ', '')
                info.date = os.date('*t', text)
            elseif line:match('^summary ') then
                local text = line:gsub('^summary ', '')
                info.summary = text
            end
        end
    end

    if not files_data[filepath] then files_data[filepath] = {} end
    files_data[filepath].blames = blames
end

---@param callback fun(): void
local function load_blames(callback)
    local blames = {}

    local filepath = vim.api.nvim_buf_get_name(0)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if #lines == 0 then return end

    local job = luajob:new({
        cmd = 'git --no-pager blame -b -p --date relative --contents - ' ..
            filepath,
        on_stdout = function(err, data)
            if data then
                process_blame_output(blames, filepath, data)
                if callback then callback() end
            end

        end
    })
    job.start()
    job.send(table.concat(lines, '\n') .. '\n')
end

---@param callback fun(is_in_git_repo: boolean): void
local function check_is_in_git_repo(callback)
    local filepath = vim.api.nvim_buf_get_name(0)

    local job = luajob:new({
        cmd = 'git ls-files --error-unmatch ' .. filepath,
        on_exit = function(code) callback(code == 0) end
    })
    job:start()
end

---@param callback fun(is_in_git_repo: boolean): void
local function check_file_in_git_repo(callback)
    local filepath = vim.api.nvim_buf_get_name(0)

    vim.schedule(function()
        check_is_in_git_repo(function(is_in_git_repo)
            if not files_data[filepath] then
                files_data[filepath] = {}
            end
            files_data[filepath].is_in_git_repo = is_in_git_repo
            if callback then callback(is_in_git_repo) end
        end)
    end)
end

local function show_blame_info()
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath:match('^term://') then return end
    local line = vim.api.nvim_win_get_cursor(0)[1]

    if last_position.filepath == filepath and last_position.line == line then
        return
    end

    if not files_data[filepath] then
        load_blames(show_blame_info)
        return
    end
    if not files_data[filepath].is_in_git_repo then return end
    if not files_data[filepath].blames then
        load_blames(show_blame_info)
        return
    end

    clear_virtual_text()

    if not files_data[filepath] or not files_data[filepath].blames then
        load_blames(show_blame_info)
        return
    end

    last_position.filepath = filepath
    last_position.line = line

    local info, blame_text
    for _, v in ipairs(files_data[filepath].blames) do
        if line >= v.startline and line <= v.endline then
            info = v
            break
        end
    end
    if info and info.author and info.author ~= 'Not Committed Yet' then
        formatted_date = info.date.day .. '.' .. info.date.month .. '.' ..
                             info.date.year .. ', ' .. info.date.hour .. ':' ..
                             info.date.min

        blame_text = vim.g.gitblame_message_template
        blame_text = blame_text:gsub('<author>', info.author)
        blame_text = blame_text:gsub('<date>', formatted_date)
        blame_text = blame_text:gsub('<summary>', info.summary)
    else
        blame_text = '  Not Committed Yet'
    end

    vim.api.nvim_buf_set_virtual_text(0, NAMESPACE_ID, line - 1,
                                      {{blame_text, 'gitblame'}}, {})
end

local function cleanup_file_data()
    local filepath = vim.api.nvim_buf_get_name(0)
    files_data[filepath] = nil
end

---@param callback fun(current_author: string): void
local function find_current_author(callback)
    local job = luajob:new({
        cmd = 'git config --get user.name',
        on_stdout = function(err, data)
            if data then
                current_author = data:match('^%s*(.*%S)')
                if callback then callback(current_author) end
            end
        end
    })
    job.start()
end

local function clear_files_data() files_data = {} end

local function handle_buf_enter()
    vim.schedule(function()
        check_file_in_git_repo(function(is_in_git_repo)
            if not is_in_git_repo then return end

            vim.schedule(show_blame_info)
        end)
    end)
end

return {
    init = find_current_author,
    show_blame_info = show_blame_info,
    clear_virtual_text = clear_virtual_text,
    load_blames = load_blames,
    cleanup_file_data = cleanup_file_data,
    clear_files_data = clear_files_data,
    handle_buf_enter = handle_buf_enter
}
