local M = {}

M.default_opts = {
    enabled = true,
    ignored_filetypes = {},
    virtual_text_column = nil,
    date_format = "%c",
    message_template = "  <author> • <date> • <summary>",
    message_when_not_committed = "  Not Committed Yet",
    highlight_group = "Comment",
    delay = 0,
    display_virtual_text = true,
    set_extmark_options = {},
}

M.setup = function(opts)
    opts = opts or {}
    opts = vim.tbl_deep_extend("force", M.default_opts, opts)

    for key, value in pairs(opts) do
        if vim.g["gitblame_" .. key] == nil then
            vim.g["gitblame_" .. key] = value
        end
    end
end

return M
