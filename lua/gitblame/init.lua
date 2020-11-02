function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

local NAMESPACE_ID = 2

-- returns output of a command
function os.capture(cmd)
    local handle = assert(io.popen(cmd, 'r'))
    local output = assert(handle:read('*a'))

    handle:close()

    output = string.gsub(string.gsub(output, '^%s+', ''), '%s+$', '')
    return output
end

local function clear_virtual_text()
    vim.api.nvim_buf_clear_namespace(0, NAMESPACE_ID, 0, -1)
end

local function load_blames()
    local blames = {}
    print('called load_blames')

    local filepath = vim.api.nvim_buf_get_name(0)
    local blame_output = os.capture(
                             'git --no-pager blame -b -p --date relative - ' ..
                                 filepath)

    local info
    for line in blame_output:gmatch('([^\n]*)\n?') do
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
                        info.time = found_info.time
                        info.summary = found_info.summary
                        break
                    end
                end
            end

            table.insert(blames, info)
        elseif info then
            if line:match('^author ') then
                local author = line:gsub('^author ', '')
                info.author = author == currentAuthor and 'You' or author
            elseif line:match('^author%-time ') then
                local text = line:gsub('^author%-time ', '')

                -- TODO format date
                info.date = os.date('*t', text)
            elseif line:match('^summary ') then
                local text = line:gsub('^summary ', '')
                info.summary = text
            end
        end
    end

    blameInfos[filepath] = blames
end

local function show_blame_info()
    clear_virtual_text()

    local line = vim.api.nvim_win_get_cursor(0)[1]
    local filepath = vim.api.nvim_buf_get_name(0)
    if not blameInfos[filepath] then load_blames() end

    local info, blame_text
    for _, v in ipairs(blameInfos[filepath]) do
        if line >= v.startline and line <= v.endline then
            info = v
            break
        end
    end
    if info and info.author and info.author ~= 'Not Committed Yet' then
        local formatted_date = ''
        if info.date then
            formatted_date = info.date.day .. '.' .. info.date.month .. '.' ..
                                 info.date.year .. ', ' .. info.date.hour .. ':' ..
                                 info.date.min
        end

        blame_text =
            '  ' .. info.author .. ' • ' .. formatted_date .. ' • ' ..
                info.summary
    else
        blame_text = '  Not Committed Yet'
    end

    vim.api.nvim_buf_set_virtual_text(0, NAMESPACE_ID, line - 1,
                                      {{blame_text, 'gitblame'}}, {})
end

local function check_is_git_repo()
    return #os.capture('git rev-parse --show-toplevel 2>/dev/null') > 0
end

local function find_current_author()
    currentAuthor = os.capture('git config --get user.name')
end

local function init()
    blameInfos = {}
    if not check_is_git_repo() then return end

    find_current_author()

    load_blames()
end

return {
    init = init,
    show_blame_info = show_blame_info,
    clear_virtual_text = clear_virtual_text,
    load_blames = load_blames
}
