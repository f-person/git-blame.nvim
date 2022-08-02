local git = require('gitblame.git')
local utils = require('gitblame.utils')
local start_job = utils.start_job
local timeago = require('lua-timeago')

---@type integer
local NAMESPACE_ID = vim.api.nvim_create_namespace('git-blame-virtual-text')

---@type table<string, string>
local last_position = {}

---@type table<string, table>
local files_data = {}

---@type string
local current_author

---@type boolean
local need_update_after_horizontal_move = false

---@type boolean
local date_format_has_relative_time

---@type string
local current_blame_text

---@return string
local function get_date_format() return vim.g.gitblame_date_format end

local function clear_virtual_text()
    vim.api.nvim_buf_del_extmark(0, NAMESPACE_ID, 1)
end

---@param blames table[]
---@param filepath string
---@param lines string[]
local function process_blame_output(blames, filepath, lines)
    if not files_data[filepath] then files_data[filepath] = {} end
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
end

---@param callback fun()
local function load_blames(callback)
    local blames = {}

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if #lines == 0 then return end

    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return end

    local filetype = vim.api.nvim_buf_get_option(0, 'ft')
    if vim.tbl_contains(vim.g.gitblame_ignored_filetypes, filetype) then
        return
    end

    git.get_repo_root(function(git_root)
        local command = 'git --no-pager -C ' .. vim.fn.shellescape(git_root) ..
                            ' blame -b -p -w --date relative --contents - ' ..
                            vim.fn.shellescape(filepath)

        start_job(command, {
            input = table.concat(lines, '\n') .. '\n',
            on_stdout = function(data)
                process_blame_output(blames, filepath, data)
                if callback then callback() end
            end
        })
    end)
end

---@param date osdate
---@return string
local function format_date(date)
    local format = get_date_format()
    if date_format_has_relative_time then
        format = format:gsub("%%r", timeago.format(date))
    end

    return os.date(format, date)
end

---@param filepath string
---@param linenumber number
---@return table|nil
local function get_blame_info(filepath, linenumber)
    if not files_data[filepath] then return end

    local info
    for _, v in ipairs(files_data[filepath].blames) do
        if linenumber >= v.startline and linenumber <= v.endline then
            info = v
            break
        end
    end
    return info
end

---@param blame_info table
---@param callback fun(blame_text: string)
local function get_blame_text(filepath, blame_info, callback)
    local info = blame_info
    local isBlameInfoAvailable = info and info.author and info.date and
                                     info.committer and info.committer_date and
                                     info.author ~= 'Not Committed Yet'

    local notCommitedBlameText = '  Not Committed Yet'
    if isBlameInfoAvailable then
        local blame_text = vim.g.gitblame_message_template
        blame_text = blame_text:gsub('<author>',
                                     info.author == current_author and 'You' or
                                         info.author)
        blame_text = blame_text:gsub('<committer>', info.committer ==
                                         current_author and 'You' or
                                         info.committer)
        blame_text = blame_text:gsub('<committer%-date>',
                                     format_date(info.committer_date))
        blame_text = blame_text:gsub('<date>', format_date(info.date))
        blame_text = blame_text:gsub('<summary>', info.summary)
        blame_text = blame_text:gsub('<sha>', string.sub(info.sha, 1, 7))
        callback(blame_text)
    elseif #files_data[filepath].blames > 0 then
        callback(notCommitedBlameText)
    else
        git.check_is_ignored(function(is_ignored)
            callback(not is_ignored and notCommitedBlameText or nil)
        end)
    end
end

---Updates `current_blame_text` and sets the virtual text if it should.
---@param blame_text string
local function update_blame_text(blame_text)
    clear_virtual_text()

    current_blame_text = blame_text
    if not blame_text then return end

    local should_display_virtual_text = vim.g.gitblame_display_virtual_text == 1
    if should_display_virtual_text then
        local options = {id = 1, virt_text = {{blame_text, 'gitblame'}}}
        local user_options = vim.g.gitblame_set_extmark_options or {}
        if type(user_options) == 'table' then
            utils.merge_map(user_options, options)
        elseif user_options then
            utils.log('gitblame_set_extmark_options should be a table')
        end

        local line = utils.get_line_number()
        vim.api.nvim_buf_set_extmark(0, NAMESPACE_ID, line - 1, 0, options)
    end
end

local function show_blame_info()
    local filepath = utils.get_filepath()
    local line = utils.get_line_number()

    if last_position.filepath == filepath and last_position.line == line then
        if not need_update_after_horizontal_move then
            return
        else
            need_update_after_horizontal_move = false
        end
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

    last_position.filepath = filepath
    last_position.line = line

    local info = get_blame_info(filepath, line)
    get_blame_text(filepath, info, update_blame_text)
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
    git.get_repo_root(function(git_repo_path)
        if git_repo_path == "" then return end

        vim.schedule(function() show_blame_info() end)
    end)
end

local function init()
    date_format_has_relative_time = get_date_format():match('%%r') ~= nil
    vim.schedule(function() find_current_author(show_blame_info) end)
end

local function handle_text_changed()
    local filepath = utils.get_filepath()
    if not filepath then return end

    local line = utils.get_line_number()

    if last_position.filepath == filepath and last_position.line == line then
        need_update_after_horizontal_move = true
    end

    load_blames(show_blame_info)
end

local function handle_insert_leave()
    local timer = vim.loop.new_timer()
    timer:start(50, 0, vim.schedule_wrap(function() handle_text_changed() end))
end

---Returns SHA for the current line.
---@param callback fun(sha: string)
local function get_sha(callback)
    local filepath = utils.get_filepath()
    local line_number = utils.get_line_number()
    local info = get_blame_info(filepath, line_number)

    if info then
        callback(info.sha)
    else
        load_blames(function()
            local new_info = get_blame_info(filepath, line_number)

            callback(new_info.sha)
        end)
    end
end

local function open_commit_url()
    get_sha(function(sha)
        local empty_sha = '0000000000000000000000000000000000000000'

        if sha and sha ~= empty_sha then
            git.open_commit_in_browser(sha)
        else
            utils.log('Unable to open commit URL as SHA is empty')
        end
    end)

end

local function get_current_blame_text() return current_blame_text end

local function is_blame_text_available() return current_blame_text ~= nil end

local function copy_sha_to_clipboard()
    get_sha(function(sha)
        if sha then
            utils.copy_to_clipboard(sha)
        else
            utils.log('Unable to copy SHA')
        end
    end)
end

local function clear_all_extmarks()
    local buffers = vim.api.nvim_list_bufs()

    for _, buffer_handle in ipairs(buffers) do
        vim.api.nvim_buf_del_extmark(buffer_handle, NAMESPACE_ID, 1)
    end
end

local function disable()
    if vim.g.gitblame_enabled == 0 then return end

    vim.g.gitblame_enabled = 0

    clear_all_extmarks()
    clear_files_data()
    last_position = {}
end

return {
    init = init,
    show_blame_info = show_blame_info,
    clear_virtual_text = clear_virtual_text,
    load_blames = load_blames,
    cleanup_file_data = cleanup_file_data,
    clear_files_data = clear_files_data,
    handle_buf_enter = handle_buf_enter,
    handle_text_changed = handle_text_changed,
    handle_insert_leave = handle_insert_leave,
    open_commit_url = open_commit_url,
    get_current_blame_text = get_current_blame_text,
    is_blame_text_available = is_blame_text_available,
    copy_sha_to_clipboard = copy_sha_to_clipboard,
    disable = disable
}
