local current_author

-- returns output of a command
function os.capture(cmd)
    local handle = assert(io.popen(cmd, 'r'))
    local output = assert(handle:read('*a'))
    handle:close()

    output = string.gsub(string.gsub(output, '^%s+', ''), '%s+$', '')
    return output
end

local function find_current_author()
    if current_author == nil then
        current_author = os.capture('git config --get user.name')
    end
end

local function get_blame_info()
    find_current_author()

    local blame_infos = {}
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
                for _, found_info in ipairs(blame_infos) do
                    if found_info.sha == parts[1] then
                        info.author = found_info.author
                        info.time = found_info.time
                        info.summary = found_info.summary
                        break
                    end
                end
            end

            table.insert(blame_infos, info)
        elseif info then
            if line:match('^author ') then
                local author = line:gsub('^author ', '')
                info.author = author == current_author and 'You' or author
            elseif line:match('^author-time ') then
                local text = line:gsub('^author-time ', '')
                -- TODO parse text to "Time ago" format string
                info.time = text
            elseif line:match('^summary ') then
                local text = line:gsub('^summary ', '')
                info.summary = text
            end
        end
    end

    return blame_infos
end

return {get_blame_info = get_blame_info}
