local git = require("gitblame.git")
local utils = require("gitblame.utils")
local start_job = utils.start_job
local timeago = require("lua-timeago")
local M = {}

---@alias timestamp integer unix epoch representation of time

---@type integer
local NAMESPACE_ID = vim.api.nvim_create_namespace("git-blame-virtual-text")

---@type PositionInfo
local last_position = {
    filepath = nil,
    line = -1,
    is_on_same_line = false,
}

---@class GitInfo
---@field blames table<string, BlameInfo>
---@field git_repo_path string?

---@type table<string, GitInfo>
local files_data = {}

---@type table<string, boolean>
local files_data_loading = {}

---@type string
local current_author

---@type boolean
local need_update_after_horizontal_move = false

---This shouldn't be used directly. Use `get_date_format` instead.
---@type boolean
local date_format_has_relative_time

---@type string
local current_blame_text

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

-- A luv timer object. Used exclusively for debouncing in `debounce`.
local debounce_timer = nil

-- Debounces `func` by `delay` milliseconds.
-- **IMPORTANT:** This refers to a single timer object (`debounce_timer`) for the debounce; beware!
---@param func function the function which will be wrapped
---@param delay integer time in milliseconds
---@return function debounced_func the debounced function which you can execute
local function debounce(func, delay)
    return function(...)
        local args = { ... }
        if debounce_timer then
            debounce_timer:stop()
            debounce_timer = nil
        end

        debounce_timer = vim.defer_fn(function()
            func(unpack(args))
            debounce_timer = nil
        end, delay)
    end
end

---@param blames table[]
---@param filepath string
---@param lines string[]
local function process_blame_output(blames, filepath, lines)
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
                info.date = tonumber(text) or os.time()
            elseif line:match("^committer ") then
                local committer = line:gsub("^committer ", "")
                info.committer = committer
            elseif line:match("^committer%-time ") then
                local text = line:gsub("^committer%-time ", "")
                info.committer_date = tonumber(text) or os.time()
            elseif line:match("^summary ") then
                local text = line:gsub("^summary ", "")
                info.summary = text
            end
        end
    end

    if not files_data[filepath] then
        files_data[filepath] = { blames = {} }
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

---Checks if the date format contains a relative time placeholder.
---@return boolean
local function check_uses_relative_date()
    if date_format_has_relative_time then
        return date_format_has_relative_time
    else
        date_format_has_relative_time = get_date_format():match("%%r") ~= nil
    end
    return false
end

---@param date timestamp
---@return string
local function format_date(date)
    local format = get_date_format()
    if check_uses_relative_date() then
        format = format:gsub("%%r", timeago.format(date))
    end
    if format == "*t" then
        return "*t"
    end
    return os.date(format, date) --[[@as string]]
end

---@param filepath string
---@param linenumber number
---@return BlameInfo?
local function get_line_blame_info(filepath, linenumber)
    ---@type BlameInfo?
    local info = nil
    for _, v in ipairs(files_data[filepath].blames) do
        if linenumber >= v.startline and linenumber <= v.endline then
            info = v
            break
        end
    end
    return info
end

---@param filepath string
---@param line1 number
---@param line2 number
---@return table<number,BlameInfo>
local function get_range_blame_info(filepath, line1, line2)
    ---@type table<number,BlameInfo>
    local range_info = {}

    for _, blame in ipairs(files_data[filepath].blames) do
        local blame_is_out_of_range = (blame.startline < line1 and blame.endline < line1)
            or (blame.startline > line2 and blame.endline > line2)

        if not blame_is_out_of_range then
            range_info[#range_info + 1] = blame
        end
    end
    return range_info
end

---Return blame information for the given line. If given a visual selection,
---return blame information for the most recently updated line.
---@param filepath string?
---@param line1 number
---@param line2 number?
---@return BlameInfo?
local function get_blame_info(filepath, line1, line2)
    if not filepath or not files_data[filepath] then
        return nil
    end
    if line2 and line1 ~= line2 then
        local blame_range = get_range_blame_info(filepath, line1, line2)
        ---@type BlameInfo|nil
        local latest_blame = nil
        for _, blame in ipairs(blame_range) do
            if latest_blame == nil or blame.date > latest_blame.date then
                latest_blame = blame
            end
        end

        return latest_blame
    else
        return get_line_blame_info(filepath, line1)
    end
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
---@field date timestamp
---@field committer_date timestamp
---@field summary string
---@field sha string
---@field startline number
---@field endline number

---@param filepath string
---@param info BlameInfo?
---@param callback fun(blame_text: string|nil)
local function get_blame_text(filepath, info, callback)
    local is_info_commit = info
        and info.author
        and info.date
        and info.committer
        and info.committer_date
        and info.author ~= "External file (--contents)"
        and info.author ~= "Not Committed Yet"

    if info and is_info_commit then
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
                local result = not is_ignored and format_blame_text(info, get_uncommitted_message_template()) or nil
                callback(result)
            end)
        end
    end
end

---Updates `current_blame_text` and sets the virtual text if it should.
---@param blame_text string?
local function update_blame_text(blame_text)
    clear_virtual_text()

    if not blame_text then
        return
    end
    current_blame_text = blame_text

    local virt_text_column = nil
    if vim.g.gitblame_virtual_text_column and utils.get_line_length() < vim.g.gitblame_virtual_text_column then
        virt_text_column = vim.g.gitblame_virtual_text_column
    end

    if vim.g.gitblame_display_virtual_text == false or vim.g.gitblame_display_virtual_text == 0 then
        return
    end
    local options = {
        id = 1,
        virt_text = { { blame_text, vim.g.gitblame_highlight_group } },
        virt_text_win_col = virt_text_column,
    }
    local user_options = vim.g.gitblame_set_extmark_options or {}
    if type(user_options) == "table" then
        utils.merge_map(user_options, options)
    elseif user_options then
        utils.log("gitblame_set_extmark_options should be a table")
    end

    local line = utils.get_line_number()
    vim.api.nvim_buf_set_extmark(0, NAMESPACE_ID, line - 1, 0, options)
end

---@class PositionInfo
---@field filepath string?
---@field line integer
---@field is_on_same_line boolean

---@return PositionInfo
local function get_position_info()
    local filepath = utils.get_filepath()
    local line = utils.get_line_number()
    local is_on_same_line = last_position.filepath == filepath and last_position.line == line

    return {
        filepath = filepath,
        line = line,
        is_on_same_line = is_on_same_line,
    }
end

local function show_blame_info()
    if not vim.g.gitblame_enabled then
        return
    end

    local position_info = get_position_info()

    local filepath = position_info.filepath
    local line = position_info.line

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

    local info = get_blame_info(filepath, line)
    get_blame_text(filepath, info, function(blame_text)
        update_blame_text(blame_text)
    end)
end

local function schedule_show_info_display()
    local position_info = get_position_info()

    if position_info.is_on_same_line then
        if not need_update_after_horizontal_move then
            return
        else
            need_update_after_horizontal_move = false
        end
    end

    if position_info.is_on_same_line then
        show_blame_info()
    else
        clear_virtual_text()
        show_blame_info()
    end

    last_position.filepath = position_info.filepath
    last_position.line = position_info.line
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
    if get_position_info().is_on_same_line then
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

---Returns SHA for the latest commit to the current branch.
---@param callback fun(sha: string)
local function get_latest_sha(callback)
    start_job("git rev-parse HEAD", {
        on_stdout = function(data)
            callback(data[1])
        end,
    })
end

---@param sha string?
---@return boolean
local function is_valid_sha(sha)
    local empty_sha = "0000000000000000000000000000000000000000"
    return sha ~= nil and sha ~= "" and sha ~= empty_sha
end

---Returns SHA for the current line or SHA
---for the latest commit in visual selection
---@param callback fun(sha: string)
---@param line1 number?
---@param line2 number?
M.get_sha = function(callback, line1, line2)
    local filepath = utils.get_filepath()
    local line_number = line1 or utils.get_line_number()
    local info = get_blame_info(filepath, line_number, line2)

    if info then
        callback(info.sha)
    else
        load_blames(function()
            local new_info = get_blame_info(filepath, line_number, line2)
            callback(new_info and new_info.sha or "")
        end)
    end
end

M.open_commit_url = function()
    M.get_sha(function(sha)
        if is_valid_sha(sha) then
            git.open_commit_in_browser(sha)
        else
            utils.log("Unable to open commit URL as SHA is empty")
        end
    end)
end

-- See :h nvim_create_user_command for more information.
---@class CommandArgs
---@field line1 number
---@field line2 number

---@param args CommandArgs
M.open_file_url = function(args)
    local filepath = utils.get_filepath()
    if filepath == nil then
        return
    end

    ---@param sha string
    local callback = function(sha)
        git.open_file_in_browser(filepath, sha, args.line1, args.line2)
    end

    if vim.g.gitblame_use_blame_commit_file_urls then
        M.get_sha(callback, args.line1, args.line2)
    else
        get_latest_sha(callback)
    end
end

M.get_current_blame_text = function()
    return current_blame_text
end

M.is_blame_text_available = function()
    return current_blame_text and current_blame_text ~= ""
end

M.copy_sha_to_clipboard = function()
    M.get_sha(function(sha)
        if is_valid_sha(sha) then
            utils.copy_to_clipboard(sha)
        else
            utils.log("Unable to copy SHA")
        end
    end)
end

---@param args CommandArgs
M.copy_file_url_to_clipboard = function(args)
    local filepath = utils.get_filepath()
    if filepath == nil then
        return
    end

    ---@param sha string
    local callback = function(sha)
        git.get_file_url(filepath, sha, args.line1, args.line2, function(url)
            utils.copy_to_clipboard(url)
        end)
    end

    if vim.g.gitblame_use_blame_commit_file_urls then
        M.get_sha(callback, args.line1, args.line2)
    else
        get_latest_sha(callback)
    end
end

M.copy_commit_url_to_clipboard = function()
    M.get_sha(function(sha)
        if is_valid_sha(sha) then
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

-- Validates the `parameter_name` against `available_values`. Returns an error message
-- if `parameter_name` doesn't match `available_values`.
--
---@param parameter_name string
---@param available_values object[]
---@return string|nil
local function validate_enum_parameter(parameter_name, available_values)
    local current_value = vim.g[parameter_name]

    if not vim.tbl_contains(available_values, current_value) then
        return string.format(
            "Invalid value for `%s`: %s. Available values are %s",
            parameter_name,
            current_value,
            vim.inspect(available_values)
        )
    end
end

-- Verifies the debounce configuration and displays an error message if it is invalid.
-- Returns `true` if the configuration is valid, `false` otherwise.
--
---@return boolean
local function verify_debounce_configuration()
    local error_message = validate_enum_parameter("gitblame_schedule_event", { "CursorMoved", "CursorHold" })
        or validate_enum_parameter("gitblame_clear_event", { "CursorMovedI", "CursorHoldI" })

    if type(vim.g.gitblame_delay) ~= "number" or vim.g.gitblame_delay < 0 then
        error_message =
            string.format("Invald value for `gitblame_delay`: %s. It should be a positive number", vim.g.gitblame_delay)
    end

    if error_message ~= nil then
        vim.notify(error_message, vim.log.levels.ERROR, {})
    end

    return error_message == nil
end

---@type function
local function maybe_clear_virtual_text_and_schedule_info_display()
    local position_info = get_position_info()

    if not position_info.is_on_same_line and not need_update_after_horizontal_move then
        clear_virtual_text()
    end

    debounce(schedule_show_info_display, math.floor(vim.g.gitblame_delay))()
end

local function set_autocmds()
    local autocmd = vim.api.nvim_create_autocmd
    local group = vim.api.nvim_create_augroup("gitblame", { clear = true })

    if not verify_debounce_configuration() then
        return
    end

    ---@type "CursorMoved" | "CursorHold"
    local event_schedule = vim.g.gitblame_schedule_event
    ---@type "CursorMovedI" | "CursorHoldI"
    local event_clear = vim.g.gitblame_clear_event

    ---@type function
    local func_schedule = schedule_show_info_display
    if event_schedule == "CursorMoved" then
        func_schedule = maybe_clear_virtual_text_and_schedule_info_display
    end

    ---@type function
    local func_clear = clear_virtual_text
    if event_clear == "CursorMovedI" then
        func_clear = debounce(clear_virtual_text, math.floor(vim.g.gitblame_delay))
    end

    autocmd(event_schedule, { callback = func_schedule, group = group })
    autocmd(event_clear, { callback = func_clear, group = group })
    autocmd("InsertEnter", { callback = clear_virtual_text, group = group })
    autocmd("TextChanged", { callback = handle_text_changed, group = group })
    autocmd("InsertLeave", { callback = handle_insert_leave, group = group })
    autocmd("BufEnter", { callback = handle_buf_enter, group = group })
    autocmd("BufDelete", { callback = cleanup_file_data, group = group })
end

M.disable = function(force)
    if not vim.g.gitblame_enabled and not force then
        return
    end

    vim.g.gitblame_enabled = false
    pcall(vim.api.nvim_del_augroup_by_name, "gitblame")
    clear_all_extmarks()
    clear_files_data()
    last_position = {
        filepath = nil,
        line = -1,
        is_on_same_line = false,
    }
    current_blame_text = ""
end

M.enable = function()
    if vim.g.gitblame_enabled then
        return
    end

    vim.g.gitblame_enabled = true
    init()
    set_autocmds()
end

M.toggle = function()
    if vim.g.gitblame_enabled then
        M.disable()
    else
        M.enable()
    end
end

local create_cmds = function()
    local command = vim.api.nvim_create_user_command

    command("GitBlameToggle", M.toggle, {})
    command("GitBlameEnable", M.enable, {})
    command("GitBlameDisable", M.disable, {})
    command("GitBlameOpenCommitURL", M.open_commit_url, {})
    command("GitBlameOpenFileURL", M.open_file_url, { range = true })
    command("GitBlameCopySHA", M.copy_sha_to_clipboard, {})
    command("GitBlameCopyCommitURL", M.copy_commit_url_to_clipboard, {})
    command("GitBlameCopyFileURL", M.copy_file_url_to_clipboard, { range = true })
end

---@class SetupOptions
---@field enabled? boolean
---@field message_template string?
---@field date_format string?
---@field message_when_not_committed string?
---@field highlight_group string?
---@field gitblame_set_extmark_options table? @see vim.api.nvim_buf_set_extmark() to check what you can pass here
---@field display_virtual_text boolean?
---@field ignored_filetypes string[]?
---@field delay number? Visual delay for displaying virtual text
---@field use_blame_commit_file_urls boolean? Use the latest blame commit instead of the latest branch commit for file urls.
---@field virtual_text_column number? The column on which to start displaying virtual text
---@field clipboard_register string? The clipboard register to use when copying commit SHAs or file URLs 

---@param opts SetupOptions?
M.setup = function(opts)
    require("gitblame.config").setup(opts)

    create_cmds()

    if vim.g.gitblame_enabled == 1 or vim.g.gitblame_enabled == true then
        init()
        set_autocmds()
    else
        M.disable(true)
    end
end

return M
