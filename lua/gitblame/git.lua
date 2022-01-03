local start_job = require('gitblame.utils').start_job
local M = {}

---@param callback fun(is_ignored: boolean)
function M.check_is_ignored(callback)
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return true end

    start_job('git check-ignore ' .. filepath,
              {on_exit = function(data) callback(data == 0) end})
end

return M
