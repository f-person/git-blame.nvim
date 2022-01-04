local utils = require('gitblame.utils')
local M = {}

---@param callback fun(is_ignored: boolean)
function M.check_is_ignored(callback)
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return true end

    utils.start_job('git check-ignore ' .. filepath,
                    {on_exit = function(data) callback(data == 0) end})
end

---@param sha string
---@param remote_url string
---@return string
local function get_commit_url(sha, remote_url)
    return remote_url .. '/commit/' .. sha
end

---@param sha string
function M.open_commit_in_browser(sha)
    M.get_remote_url(function(remote_url)
        local commit_url = get_commit_url(sha, remote_url)
        utils.start_job('open ' .. commit_url)
    end)
end

---@param callback fun(url: string)
function M.get_remote_url(callback)
    local filepath = utils.get_filepath()
    if not filepath then
        utils.log('filepath is empty')
        return
    end
    local remote_url_command = 'cd "`dirname \'' .. filepath .. '\'`"' ..
                                   " && git config --get remote.origin.url"
    -- Echo and pipe it to `sh` to execute in a POSIX shell
    -- as it might not be user's shell and things will break in that case.
    local shell_command = "echo '" .. remote_url_command .. "' | sh"

    utils.log(shell_command)
    utils.start_job(shell_command, {
        on_stdout = function(url)
            utils.log('on_stdout ' .. url[1])
            if url and url[1] then
                callback(url[1])
            else
                callback(nil)
            end
        end
    })
end

return M
