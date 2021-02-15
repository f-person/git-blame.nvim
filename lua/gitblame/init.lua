local start_job = require('gitblame/utils').start_job
local log = require('gitblame/utils').log

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

---@param blames string[]
---@param filepath string
---@param lines string[]
local function process_blame_output(blames, filepath, lines)
    if not files_data[filepath] then files_data[filepath] = {} end
    files_data[filepath].is_processing_blame_output = true
    local info
    for _, line in ipairs(lines) do
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
                        info.committer = found_info.committer
                        info.date = found_info.date
                        info.committer_date = found_info.committer_date
                        info.summary = found_info.summary
                        break
                    end
                end
            end

            table.insert(blames, info)
        elseif info then
            if line:match('^author ') then
                local author = line:gsub('^author ', '')
                info.author = author
            elseif line:match('^author%-time ') then
                local text = line:gsub('^author%-time ', '')
                info.date = text
            elseif line:match('^committer ') then
                local committer = line:gsub('^committer ', '')
                info.committer = committer
            elseif line:match('^committer%-time ') then
                local text = line:gsub('^committer%-time ', '')
                info.committer_date = text
            elseif line:match('^summary ') then
                local text = line:gsub('^summary ', '')
                info.summary = text
            end
        end
    end

    if not files_data[filepath] then files_data[filepath] = {} end
    files_data[filepath].blames = blames
    files_data[filepath].is_processing_blame_output = false
end

local function get_git_repo_root()
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return "" end

    local git_root = ""

    if not files_data[filepath] then files_data[filepath] = {} end

    if files_data[filepath].git_repo_path then
        git_root = files_data[filepath].git_repo_path
    else
        git_root = vim.fn.finddir('.git/..', filepath .. ';')
        files_data[filepath].git_repo_path = git_root
    end
    return git_root
end

---@param callback fun()
local function load_blames(callback)
    local blames = {}

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if #lines == 0 then return end

    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return end

    local git_root = get_git_repo_root()
    if git_root == "" then return end

    local command = 'git --no-pager -C ' .. git_root ..
                        ' blame -b -p --date relative --contents - ' .. filepath
    start_job(command, {
        input = table.concat(lines, '\n') .. '\n',
        on_stdout = function(data)
            process_blame_output(blames, filepath, data)
            if callback then callback() end
        end
    })
end

local function show_blame_info()
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return end
    if filepath:match('^term://') then return end

    local line = vim.api.nvim_win_get_cursor(0)[1]

    if last_position.filepath == filepath and last_position.line == line then
        return
    end

    if not files_data[filepath] then
        load_blames(show_blame_info)
        return
    end
    if files_data[filepath].git_repo_path == "" then return end
    if not files_data[filepath].blames then
        load_blames(show_blame_info)
        return
    end

    clear_virtual_text()

    last_position.filepath = filepath
    last_position.line = line

    local info, blame_text
    for _, v in ipairs(files_data[filepath].blames) do
        if line >= v.startline and line <= v.endline then
            info = v
            break
        end
    end
    if info and info.author and info.date and info.committer and
        info.committer_date and info.author ~= 'Not Committed Yet' then
        date_format = vim.g.gitblame_date_format

        blame_text = vim.g.gitblame_message_template
        blame_text = blame_text:gsub('<author>',
                                     info.author == current_author and 'You' or
                                         info.author)
        blame_text = blame_text:gsub('<committer>', info.committer ==
                                         current_author and 'You' or
                                         info.committer)
        blame_text = blame_text:gsub('<committer%-date>',
                                     os.date(date_format, info.committer_date))
        blame_text = blame_text:gsub('<date>', os.date(date_format, info.date))
        blame_text = blame_text:gsub('<summary>', info.summary)
        blame_text = blame_text:gsub('<sha>', string.sub(info.sha, 1, 7))
    elseif #files_data[filepath].blames > 0 then
        blame_text = '  Not Committed Yet'
    else
        return
    end

    vim.api.nvim_buf_set_virtual_text(0, NAMESPACE_ID, line - 1,
                                      {{blame_text, 'gitblame'}}, {})
end

local function cleanup_file_data()
    local filepath = vim.api.nvim_buf_get_name(0)
    files_data[filepath] = nil
end

---@param callback fun(current_author: string)
local function find_current_author(callback)
    start_job('git config --get user.name', {
        on_stdout = function(data)
            current_author = data[1]
            if callback then callback(current_author) end
        end
    })
end

local function clear_files_data() files_data = {} end

local function handle_buf_enter()
    local git_repo_path = get_git_repo_root()
    if git_repo_path == "" then return end

    vim.schedule(function() show_blame_info() end)
end

local function init()
    vim.schedule(function() find_current_author(show_blame_info) end)
end

return {
    init = init,
    get_git_repo_root = get_git_repo_root,
    show_blame_info = show_blame_info,
    clear_virtual_text = clear_virtual_text,
    load_blames = load_blames,
    cleanup_file_data = cleanup_file_data,
    clear_files_data = clear_files_data,
    handle_buf_enter = handle_buf_enter
}
