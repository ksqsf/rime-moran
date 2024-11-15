-- moran_pin.lua
-- version: 0.1.1
-- author: kuroame
-- license: GPLv3
-- You may copy, distribute and modify the software as long as you track changes/dates in source files. Any modifications to or software including (via compiler) GPL-licensed code must also be made available under the GPL along with build & install instructions.

-- changelog
-- 0.1.1: simple configuration
-- 0.1.0: init



-- userdb
-- 将用户的pin记录存储在userdb中
local user_db = {}
local sep_t = " \t"
-- epoch : 2024/11/11 00:00 in min
local epoch = 28854240
local ref_count = 0
local pin_db = UserDb("moran_pin", "userdb")
function user_db.release()
    ref_count = ref_count - 1
    if ref_count > 0 then
        return
    end
    if pin_db:loaded() then
        pin_db:close()
    end
end

function user_db.acquire()
    if not pin_db:loaded() then
        pin_db:open()
        if not pin_db:loaded() then
            return
        end
    end
    ref_count = ref_count + 1
end

---@param input string
---@return function iterator
function user_db.query_and_unpack(input)
    local res = pin_db:query(input .. sep_t)
    local function iter()
        local next_func, self = res:iter()
        return function()
            while true do
                local key, value = next_func(self)
                if key == nil then
                    return nil
                end
                local entry = user_db.unpack_entry(key, value)
                if entry ~= nil then
                    return entry
                end
            end
        end
    end
    return iter()
end

function user_db.timestamp_now()
    return math.floor((os.time()) / 60) - epoch
end

---@param n string weight/output commits
---@param m string timestamp in min from epoch
---@return str encoded commits
function user_db.encode(n, m)
    local n_prime = n + 8 -- move the range to [0, 15]
    if n >= 0 then
        return m * 16 + n_prime
    else
        return -(m * 16 + n_prime)
    end
end

---@param x string encoded commits
---@return n string weight/output commits
---@return m string timestamp in min from epoch
function user_db.decode(x)
    local n, m
    if x >= 0 then
        m = math.floor(x / 16)
        n = (x % 16) - 8
    else
        local x_abs = -x
        m = math.floor(x_abs / 16)
        n = (x_abs % 16) - 8
    end
    return n, m
end

---@param key string
---@param value string
---@return table|nil
function user_db.unpack_entry(key, value)
    local result = {}

    local code, phrase = key:match("^(.-)%s+(.+)$")
    if code and phrase then
        result.code = code
        result.phrase = phrase
    else
        return nil
    end

    local commits, dee, tick = 0, 0.0, 0
    for k, v in value:gmatch("(%a+)=(%S+)") do
        if k == "c" then
            commits = tonumber(v) or 0
        elseif k == "d" then
            dee = math.min(10000.0, tonumber(v) or 0.0)
        elseif k == "t" then
            tick = tonumber(v) or 0
        end
    end
    local output_commits, timestamp = user_db.decode(commits)

    -- just neglect tombstoned entries
    if output_commits < 0 then
        return nil
    end

    result.raw_commits = commits
    result.commits = output_commits
    result.timestamp = timestamp
    result.dee = dee
    result.tick = tick

    return result
end

---@param input string
---@param cand_text string
function user_db.toggle_pin_status(input, cand_text)
    local pinned_res = pin_db:query(input .. sep_t)
    if pinned_res ~= nil then
        local key = input .. sep_t .. cand_text
        local max_commits = 0
        for k, v in pinned_res:iter() do
            local unpacked = user_db.unpack_entry(k, v)
            if unpacked then
                -- found existing entry here
                if key == k then
                    -- if it's an active one, set its commit counter to -1 to tombstone it
                    if unpacked.commits > 0 then
                        user_db.tombstone(key)
                        -- good to leave now
                        return
                    end
                end
                max_commits = math.max(max_commits, unpacked.commits)
            end
        end

        -- commit counter ranges from 0 to 7 (minus one is considered as tombstoned)
        if max_commits >= 7 then
            -- whoops, maximum reached, we need to rearrange the commit counter from 0 to 7
            -- if there's no vacancy, we need to tombstone the one with a minimum commit counter (most unimportant one) to make room for the new one
            user_db.rearrange(input, cand_text)
        else
            -- nothing much to worry, upsert the new entry here
            user_db.upsert(key, max_commits + 1)
        end
    end
end

function user_db.rearrange(input, cand_text)
    local pinned_res = pin_db:query(input .. sep_t)
    local key = input .. sep_t .. cand_text
    local entries = {}
    local active_entries = {}
    local max_commits = -1
    local min_commits = math.huge
    local min_key = nil

    -- traverse all entries to find the one with the minimum commit counter
    for k, v in pinned_res:iter() do
        local unpacked = user_db.unpack_entry(k, v)
        if unpacked then
            entries[k] = unpacked
            if unpacked.commits >= 0 then
                table.insert(active_entries, { key = k, entry = unpacked })
                if unpacked.commits > max_commits then
                    max_commits = unpacked.commits
                end
                if unpacked.commits < min_commits then
                    min_commits = unpacked.commits
                    min_key = k
                end
            end
        end
    end

    -- check if we need to delete the one with the minimum commit counter
    if #active_entries >= 8 then
        if not entries[key] or entries[key].commits < 0 then
            user_db.upsert(min_key, -1)
            entries[min_key].commits = -1
            for i, item in ipairs(active_entries) do
                if item.key == min_key then
                    table.remove(active_entries, i)
                    break
                end
            end
        else
            -- the key already exists, hence no need to tombstone any entry
        end
    end

    local new_commits = 0
    for _, item in ipairs(active_entries) do
        local k = item.key
        local entry = item.entry
        if k ~= key then
            user_db.upsert(k, new_commits)
            new_commits = new_commits + 1
        end
    end

    -- upsert the new entry
    user_db.upsert(key, new_commits)
end

function user_db.dump_raw()
    local res = pin_db:query("")
    local function iter()
        local next_func, self = res:iter()
        return function()
            while true do
                local key, value = next_func(self)
                if key == nil then
                    return nil
                end
                return key, value
            end
        end
    end
    return iter()
end

function user_db.upsert(key, output_commits)
    local encoded_commit = user_db.encode(output_commits, user_db.timestamp_now())
    pin_db:update(key, "c=" .. encoded_commit .. " d=0 t=1")
end

function user_db.tombstone(key)
    user_db.upsert(key, -1)
end

-- pin_processor
-- 处理ctrl+t
local kAccepted = 1
local kNoop = 2
local pin_processor = {}

function pin_processor.init(env)
    user_db.acquire()
end

function pin_processor.fini(env)
    user_db.release()
end

function pin_processor.func(key_event, env)
    -- ctrl + x to trigger
    if not key_event:ctrl() or key_event:release() then
        return kNoop
    end
    -- + t
    if key_event.keycode == 0x74 then
        local context = env.engine.context
        local input = context.input
        local cand = context:get_selected_candidate()
        local gcand = cand:get_genuine()
        local text = gcand.text
        user_db.toggle_pin_status(input, text)
        context:refresh_non_confirmed_composition()
        -- + a
    elseif key_event.keycode == 0x61 then
        -- todo: add quick code
        return kNoop
    else
        return kNoop
    end
    return kAccepted
end

-- pin_filter
-- 从pin记录中读取候选项，并将其插入到候选列表的最前面
local pin_filter = {}

function pin_filter.init(env)
    env.indicator = env.engine.schema.config:get_string("moran/pin/indicator") or "📌"
    user_db.acquire()
end

function pin_filter.fini(env)
    user_db.release()
end

function pin_filter.func(t_input, env)
    local input = env.engine.context.input
    local commits = {}
    for unpacked in user_db.query_and_unpack(input) do
        table.insert(commits, unpacked)
    end
    -- descending sort
    table.sort(commits, function(a, b)
        return a.commits > b.commits
    end)
    for _, unpacked in ipairs(commits) do
        local cand = Candidate("pinned", 0, #input, unpacked.phrase, env.indicator)
        cand.preedit = input
        yield(cand)
    end
    for cand in t_input:iter() do
        yield(cand)
    end
end

-- panacea_translator
-- 基于pin功能 以 编码[infix]词 的形式触发，灵活造词
local panacea_translator = {}

function panacea_translator.init(env)
    env.infix = env.engine.schema.config:get_string("moran/pin/panacea/infix") or '//'
    env.enscaped_infix = string.gsub(env.infix, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    env.prompt = env.engine.schema.config:get_string("moran/pin/panacea/prompt") or "〔加詞〕"
    env.indicator = env.engine.schema.config:get_string("moran/pin/indicator") or "📌"
    user_db.acquire()
    local pattern = string.format("(.+)%s(.+)", env.enscaped_infix)
    local function on_commit(ctx)
        local commit_text = ctx:get_commit_text()
        local code, original_code = ctx.input:match(pattern)
        if original_code and code and commit_text then
            user_db.toggle_pin_status(code, commit_text)
        end
    end

    local function on_update_or_select(ctx)
        local code, original_code = ctx.input:match(pattern)
        if original_code and code then
            local segment = ctx.composition:back()
            segment.prompt = env.prompt .." | " .. code
        end
    end

    env.commit_notifier = env.engine.context.commit_notifier:connect(on_commit)
    env.select_notifier = env.engine.context.select_notifier:connect(on_update_or_select)
    env.update_notifier = env.engine.context.update_notifier:connect(on_update_or_select)
end

function panacea_translator.fini(env)
    env.commit_notifier:disconnect()
    env.select_notifier:disconnect()
    env.update_notifier:disconnect()
    user_db.release()
end

function panacea_translator.func(input, seg, env)
    local pattern = "[a-z]+"..env.enscaped_infix
    local match = input:match(pattern)

    if match then
        local tip_cand = Candidate("pin_tip", 0, #match, "", "➕"..env.indicator)
        tip_cand.quality = math.huge
        yield(tip_cand)
        return
    end
end

return {
    pin_filter = pin_filter,
    pin_processor = pin_processor,
    panacea_translator = panacea_translator,
}

-- Local Variables:
-- lua-indent-level: 4
-- End:
