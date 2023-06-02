local git = require("gitblame.git")
local utils = require("gitblame.utils")
local start_job = utils.start_job
local timeago = require("lua-timeago")

---@type integer
local NAMESPACE_ID = vim.api.nvim_create_namespace("git-blame-virtual-text")

---@type table<string, string>
local last_position = {}

---@class GitInfo
---@field blames table<string, BlameInfo>
---@field git_repo_path string

---@type table<string, GitInfo>
local files_data = {}

---@type table<string, boolean>
local files_data_loading = {}

---@type string
local current_author

---@type boolean
local need_update_after_horizontal_move = false

--- This shouldn't be used directly. Use `get_date_format` instead.
---@type boolean
local date_format_has_relative_time

---@type string
local current_blame_text

---@type table timer luv timer object
local delay_timer

---@return string
local function get_date_format()
    return vim.g.gitblame_date_format
end

---@return string
local function get_uncommitted_message_template()
    return vim.g.gitblame_message_when_not_committed
end

---@return string
local function get_blame_message_template()
    return vim.g.gitblame_message_template
end

local function clear_virtual_text()
    vim.api.nvim_buf_del_extmark(0, NAMESPACE_ID, 1)
end

---@param blames table[]
---@param filepath string
---@param lines string[]
local function process_blame_output(blames, filepath, lines)
    if not files_data[filepath] then
        files_data[filepath] = {}
    end
    ---@type BlameInfo
    local info
    for _, line in ipairs(lines) do
        local message = line:match("^([A-Za-z0-9]+) ([0-9]+) ([0-9]+) ([0-9]+)")
        if message then
            local parts = {}
            for part in line:gmatch("%w+") do
                table.insert(parts, part)
            end

            local startline = tonumber(parts[3])
            info = {
                startline = startline or 0,
                sha = parts[1],
                endline = startline + tonumber(parts[4]) - 1,
            }

            if parts[1]:match("^0+$") == nil then
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
            if line:match("^author ") then
                local author = line:gsub("^author ", "")
                info.author = author
            elseif line:match("^author%-time ") then
                local text = line:gsub("^author%-time ", "")
                info.date = text
            elseif line:match("^committer ") then
                local committer = line:gsub("^committer ", "")
                info.committer = committer
            elseif line:match("^committer%-time ") then
                local text = line:gsub("^committer%-time ", "")
                info.committer_date = text
            elseif line:match("^summary ") then
                local text = line:gsub("^summary ", "")
                info.summary = text
            end
        end
    end

    if not files_data[filepath] then
        files_data[filepath] = {}
    end
    files_data[filepath].blames = blames
end

---@param callback fun()
local function load_blames(callback)
    local blames = {}

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if #lines == 0 then
        return
    end

    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then
        return
    end

    local buftype = vim.api.nvim_buf_get_option(0, "bt")
    if buftype ~= "" then
        return
    end

    local filetype = vim.api.nvim_buf_get_option(0, "ft")
    if vim.tbl_contains(vim.g.gitblame_ignored_filetypes, filetype) then
        return
    end

    if files_data_loading[filepath] then
        return
    end

    files_data_loading[filepath] = true

    git.get_repo_root(function(git_root)
        local command = "git --no-pager -C "
            .. vim.fn.shellescape(git_root)
            .. " blame -b -p -w --date relative --contents - "
            .. vim.fn.shellescape(filepath)

        start_job(command, {
            input = table.concat(lines, "\n") .. "\n",
            on_stdout = function(data)
                process_blame_output(blames, filepath, data)
                if callback then
                    callback()
                end
            end,
            on_exit = function()
                files_data_loading[filepath] = nil
            end,
        })
    end)
end

--- Checks if the date format contains a relative time placeholder.
---@return boolean
local function check_uses_relative_date()
    if date_format_has_relative_time then
        return date_format_has_relative_time
    else
        date_format_has_relative_time = get_date_format():match("%%r") ~= nil
    end
    return false
end

---@param date osdate
---@return string
local function format_date(date)
    local format = get_date_format()
    if check_uses_relative_date() then
        format = format:gsub("%%r", timeago.format(date))
    end

    return os.date(format, date)
end

---@param filepath string?
---@param linenumber number
---@return BlameInfo|nil
local function get_blame_info(filepath, linenumber)
    if not filepath or not files_data[filepath] then
        return nil
    end

    ---@type BlameInfo
    local info
    for _, v in ipairs(files_data[filepath].blames) do
        if linenumber >= v.startline and linenumber <= v.endline then
            info = v
            break
        end
    end
    return info
end

---@param info BlameInfo
---@param template string
---@return string formatted_message
local function format_blame_text(info, template)
    local text = template
    --utils.log(info)
    text = text:gsub("<author>", info.author)
    text = text:gsub("<committer>", info.committer)
    text = text:gsub("<committer%-date>", format_date(info.committer_date))
    text = text:gsub("<date>", format_date(info.date))

    local summary_escaped = info.summary:gsub("%%", "%%%%")
    text = text:gsub("<summary>", summary_escaped)

    text = text:gsub("<sha>", info.sha and string.sub(info.sha, 1, 7) or "")

    return text
end

---@class BlameInfo
---@field author string
---@field committer string
---@field date osdate
---@field committer_date osdate
---@field summary string
---@field sha string
---@field startline number
---@field endline number

---@param info BlameInfo|nil
---@param callback fun(blame_text: string|nil)
local function get_blame_text(filepath, info, callback)
    local is_info_commit = info
        and info.author
        and info.date
        and info.committer
        and info.committer_date
        and info.author ~= "Not Committed Yet"

    if is_info_commit then
        info.author = info.author == current_author and "You" or info.author
        info.committer = info.committer == current_author and "You" or info.committer

        local blame_text = format_blame_text(info, get_blame_message_template())
        callback(blame_text)
    else
        if info then
            info = utils.shallowcopy(info)
        else
            info = {}
        end

        info.author = "You"
        info.committer = "You"
        info.summary = "Not Commited Yet"

        -- NOTE: While this works okay-ish, I'm not sure this is the behavior
        -- people expect, since sometimes git-blame just doesn't provide
        -- the date of uncommited changes.
        info.date = info.date or os.time()
        info.committer_date = info.committer_date or os.time()

        if #files_data[filepath].blames > 0 then

            local blame_text = format_blame_text(info, get_uncommitted_message_template())
            callback(blame_text)
        else
            git.check_is_ignored(function(is_ignored)
                local result = not is_ignored and format_blame_text(info, get_uncommitted_message_template())
                    or nil
                callback(result)
            end)
        end
    end
end

---Updates `current_blame_text` and sets the virtual text if it should.
---@param blame_text string|nil
local function update_blame_text(blame_text)
    clear_virtual_text()

    if not blame_text then
        return
    end
    current_blame_text = blame_text

    local virt_text_column = nil
    if vim.g.gitblame_virtual_text_column ~= vim.NIL
        and utils.get_line_length() < vim.g.gitblame_virtual_text_column
    then
        virt_text_column = vim.g.gitblame_virtual_text_column
    end

    local should_display_virtual_text = vim.g.gitblame_display_virtual_text == 1
    if should_display_virtual_text then
        local options = { id = 1, virt_text = { { blame_text, "gitblame" } },
            virt_text_win_col = virt_text_column }
        local user_options = vim.g.gitblame_set_extmark_options or {}
        if type(user_options) == "table" then
            utils.merge_map(user_options, options)
        elseif user_options then
            utils.log("gitblame_set_extmark_options should be a table")
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
    if files_data[filepath].git_repo_path == "" then
        return
    end
    if not files_data[filepath].blames then
        load_blames(show_blame_info)
        return
    end

    last_position.filepath = filepath
    last_position.line = line

    local info = get_blame_info(filepath, line)
    get_blame_text(filepath, info, function(blame_text)
        update_blame_text(blame_text)
    end)
end

local function schedule_show_info_display()
    ---@type integer
    local delay = vim.g.gitblame_delay
    if not delay or delay == 0 then
        show_blame_info()
    else
        if delay_timer and vim.loop.is_active(delay_timer) then
            delay_timer:stop()
            delay_timer:close()
        end
        clear_virtual_text()
        delay_timer = vim.defer_fn(show_blame_info, delay)
    end
end

local function cleanup_file_data()
    local filepath = vim.api.nvim_buf_get_name(0)
    files_data[filepath] = nil
end

---@param callback fun(current_author: string)
local function find_current_author(callback)
    start_job("git config --get user.name", {
        ---@param data string[]
        on_stdout = function(data)
            current_author = data[1]
            if callback then
                callback(current_author)
            end
        end,
    })
end

local function clear_files_data()
    files_data = {}
end

local function handle_buf_enter()
    git.get_repo_root(function(git_repo_path)
        if git_repo_path == "" then
            return
        end

        vim.schedule(function()
            show_blame_info()
        end)
    end)
end

local function init()
    vim.schedule(function()
        find_current_author(show_blame_info)
    end)
end

local function handle_text_changed()
    local filepath = utils.get_filepath()
    if not filepath then
        return
    end

    local line = utils.get_line_number()

    if last_position.filepath == filepath and last_position.line == line then
        need_update_after_horizontal_move = true
    end

    load_blames(show_blame_info)
end

local function handle_insert_leave()
    local timer = vim.loop.new_timer()
    timer:start(
        50,
        0,
        vim.schedule_wrap(function()
            handle_text_changed()
        end)
    )
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

            callback(new_info and new_info.sha or "")
        end)
    end
end

local function open_commit_url()
    get_sha(function(sha)
        local empty_sha = "0000000000000000000000000000000000000000"

        if sha and sha ~= empty_sha then
            git.open_commit_in_browser(sha)
        else
            utils.log("Unable to open commit URL as SHA is empty")
        end
    end)
end

local function open_file_url()
    local filepath = utils.get_filepath()
    if filepath == nil then
        return
    end

    local line_number = utils.get_line_number()

    git.open_file_in_browser(filepath, line_number)
end

local function get_current_blame_text()
    return current_blame_text
end

local function is_blame_text_available()
    return current_blame_text ~= nil
end

local function copy_sha_to_clipboard()
    get_sha(function(sha)
        if sha then
            utils.copy_to_clipboard(sha)
        else
            utils.log("Unable to copy SHA")
        end
    end)
end

local function copy_file_url_to_clipboard()
    local filepath = utils.get_filepath()
    if filepath == nil then
        return
    end

    local line_number = utils.get_line_number()

    git.get_file_url(filepath, line_number, function(url)
        utils.copy_to_clipboard(url)
    end)
end

local function copy_commit_url_to_clipboard()
    get_sha(function(sha)
        if sha then
            git.get_remote_url(function(remote_url)
                local commit_url = git.get_commit_url(sha, remote_url)
                utils.copy_to_clipboard(commit_url)
            end)
        else
            utils.log("Unable to copy SHA")
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
    if vim.g.gitblame_enabled == 0 then
        return
    end

    vim.g.gitblame_enabled = 0

    clear_all_extmarks()
    clear_files_data()
    last_position = {}
end

return {
    init = init,
    show_blame_info = show_blame_info,
    schedule_show_info_display = schedule_show_info_display,
    clear_virtual_text = clear_virtual_text,
    load_blames = load_blames,
    cleanup_file_data = cleanup_file_data,
    clear_files_data = clear_files_data,
    handle_buf_enter = handle_buf_enter,
    handle_text_changed = handle_text_changed,
    handle_insert_leave = handle_insert_leave,
    open_commit_url = open_commit_url,
    open_file_url = open_file_url,
    get_current_blame_text = get_current_blame_text,
    is_blame_text_available = is_blame_text_available,
    copy_sha_to_clipboard = copy_sha_to_clipboard,
    copy_commit_url_to_clipboard = copy_commit_url_to_clipboard,
    copy_file_url_to_clipboard = copy_file_url_to_clipboard,
    disable = disable,
}
