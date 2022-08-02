local utils = require('gitblame.utils')
local M = {}

---@param callback fun(is_ignored: boolean)
function M.check_is_ignored(callback)
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return true end

    utils.start_job('git check-ignore ' .. vim.fn.shellescape(filepath),
                    {on_exit = function(data) callback(data ~= 1) end})
end

---@param sha string
---@param remote_url string
---@return string
local function get_commit_url(sha, remote_url)
    local commit_path = '/commit/' .. sha

    local domain, path = string.match(remote_url, ".*git%@(.*)%:(.*)%.git")
    if domain and path then
        return 'https://' .. domain .. '/' .. path .. commit_path
    end

    local url = string.match(remote_url, ".*git%@(.*)%.git")
    if url then return 'https://' .. url .. commit_path end

    local https_url = string.match(remote_url, "(https%:%/%/.*)%.git")
    if https_url then return https_url .. commit_path end

    return remote_url .. commit_path
end

---@param sha string
function M.open_commit_in_browser(sha)
    M.get_remote_url(function(remote_url)
        local commit_url = get_commit_url(sha, remote_url)
        utils.launch_url(commit_url)
    end)
end

---@param callback fun(url: string)
function M.get_remote_url(callback)
    if not utils.get_filepath() then return end
    local remote_url_command = 'cd ' .. vim.fn.shellescape(vim.fn.expand('%:p:h')) ..
                                   ' && git config --get remote.origin.url'

    utils.start_job(remote_url_command, {
        on_stdout = function(url)
            if url and url[1] then
                callback(url[1])
            else
                callback(nil)
            end
        end
    })
end

---@param callback fun()
function M.get_repo_root(callback)
    if not utils.get_filepath() then return end
    local command = 'cd ' .. vim.fn.shellescape(vim.fn.expand('%:p:h')) ..
                        ' && git rev-parse --show-toplevel'

    utils.start_job(command, {on_stdout = function(data) callback(data[1]) end})
end

return M
