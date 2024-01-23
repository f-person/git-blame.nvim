local M = {}

---@type table
local language = require('lua-timeago/languages/en')

function M.set_language(new_language)
    local new_language_type = type(new_language)

    if new_language_type == "table" then
        language = new_language
    elseif new_language_type == "string" then
        language = require('languages/' .. new_language)
    end

    assert(language and language.justnow)
    assert(language.minute and language.minute.singular and
        language.minute.plural)
    assert(language.hour and language.hour.singular and language.hour.plural)
    assert(language.day and language.day.singular and language.day.plural)
    assert(language.week and language.week.singular and language.week.plural)
    assert(language.month and language.month.singular and language.month.plural)
    assert(language.year and language.year.singular and language.year.plural)
end

---@param num number
---@return number
local function round(num) return math.floor(num + 0.5) end

---@param time timestamp
---@return string
function M.format(time)
    local now = os.time()
    local diff_seconds = os.difftime(now, time)
    if diff_seconds < 45 then return language.justnow end

    local diff_minutes = diff_seconds / 60
    if diff_minutes < 1.5 then return language.minute.singular end
    if diff_minutes < 59.5 then
        return round(diff_minutes) .. ' ' .. language.minute.plural
    end

    local diff_hours = diff_minutes / 60
    if diff_hours < 1.5 then return language.hour.singular end
    if diff_hours < 23.5 then
        return round(diff_hours) .. ' ' .. language.hour.plural
    end

    local diff_days = diff_hours / 24
    if diff_days < 1.5 then return language.day.singular end
    if diff_days < 7.5 then
        return round(diff_days) .. ' ' .. language.day.plural
    end

    local diff_weeks = diff_days / 7
    if diff_weeks < 1.5 then return language.week.singular end
    if diff_weeks < 4.5 then
        return round(diff_weeks) .. ' ' .. language.week.plural
    end

    local diff_months = diff_days / 30
    if diff_months < 1.5 then return language.month.singular end
    if diff_months < 11.5 then
        return round(diff_months) .. ' ' .. language.month.plural
    end

    local diff_years = diff_days / 365.25
    if diff_years < 1.5 then return language.year.singular end
    return round(diff_years) .. ' ' .. language.year.plural
end

return M
