local start_job = require('gitblame.utils').start_job
local M = {}

---@param callback fun(is_ignored: boolean)
function M.check_is_ignored(callback)
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return true end

    start_job('git check-ignore ' .. filepath,
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
        start_job('open ' .. commit_url)
    end)

end

---@param callback fun(url: string)
function M.get_remote_url(callback)
    start_job('git config --get remote.origin.url', {
        on_stdout = function(url)
            if url and url[1] then
                callback(url[1])
            else
                callback(nil)
            end
        end
    })
end

return M
