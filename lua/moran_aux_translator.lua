-- moran_aux_translator -- 實現直接輔助碼篩選的翻譯器
--
-- Author: ksqsf
-- License: GPLv3
-- Version: 0.1.5
--
-- 0.1.5: 允許自定義預取長度。
--
-- 0.1.4: 繼續優化邏輯。
--
-- 0.1.3: 優化邏輯。
--
-- 0.1.2：句子優先，避免輸入過程中首選長度大幅波動。一定程度上提高性能。
--
-- 0.1.1：三碼優先單字。
--
-- 0.1.0: 實作。


local moran = require("moran")
local Module = {}
Module.WORD_TOLERANCE = 10

-- 一些音節需要較多預取
local BIG_SYLLABLES = {
  ["ji"] = 200,
  ["ui"] = 200,
  ["yi"] = 200,
}

function Module.init(env)
  env.aux_table = moran.load_zrmdb()
  env.translator = Component.Translator(env.engine, "", "script_translator@translator")
  env.prefetch_threshold = env.engine.schema.config:get_int("moran/prefetch") or -1
  -- 四码词组优先
  env.is_phrase_first = env.engine.schema.config:get_bool("moran/phrase_first") or true
  env.single_word_code_len = env.is_phrase_first and 3 or 4
  -- 输入辅助码首选后移
  env.is_aux_priority = env.engine.schema.config:get_bool("moran/aux_priority") or true
  local aux_position = env.engine.schema.config:get_string("moran/aux_position") or "any"
  if aux_position == "first" then
    env.is_aux_for_first = true
  elseif aux_position == "last" then
    env.is_aux_for_last = true
  else
    env.is_aux_for_any = true
  end

  env.previous_word = ""
  env.previous_word_aux = ""

  local aux_length = nil

  -- 在自帶的 OnSelect 之前生效，從而獲取到 selected candidate
  local function on_select_pre(ctx)
    aux_length = nil

    local composition = ctx.composition
    if composition:empty() then
      return
    end

    local segment = composition:back()
    if not (segment.status == "kSelected" or segment.status == "kConfirmed") then
      return
    end

    local cand = segment:get_selected_candidate()
    if cand and cand.comment and cand.comment ~= "" then
      aux_length = #cand.comment
    end
  end

  -- 在自帶的 OnSelect 之後生效，
  local function on_select_post(ctx)
    if aux_length then
      ctx.input = ctx.input:sub(1, #ctx.input - aux_length)
      if ctx.composition:has_finished_composition() then
        ctx:commit()
      end
    end
    aux_length = nil
    env.previous_word = ""
    env.previous_word_aux = ""
  end

  env.notifier_pre = env.engine.context.select_notifier:connect(on_select_pre, 0)
  env.notifier_post = env.engine.context.select_notifier:connect(on_select_post)
end

function Module.fini(env)
  env.notifier_pre:disconnect()
  env.notifier_post:disconnect()
  env.aux_table = nil
  env.translator = nil
  collectgarbage()
end

function Module.func(input, seg, env)
  -- 每 10% 的翻譯觸發一次 GC
  if math.random() < 0.1 then
    collectgarbage()
  end
  local input_len = utf8.len(input)
  -- 单字场景
  if input_len <= env.single_word_code_len then
    local sp = input:sub(1, 2)
    local aux = input:sub(3, input_len)
    local iter = aux.len and Module.translate_with_aux(env, seg, sp, aux) or
    Module.translate_without_aux(env, seg, input)
    local first_cand = iter()
    local mv_cnt = 0
    if env.is_aux_priority and first_cand.text == env.previous_word and aux ~= env.previous_word_aux then
      -- 因为备选有重复的问题，导致移动位置不准确，需要移动到其他环节处理该逻辑
      mv_cnt = 3;
    end
    env.previous_word = first_cand.text
    env.previous_word_aux = aux
    for cand in iter do
      if mv_cnt == 0 then
        yield(first_cand)
      end
      mv_cnt = mv_cnt - 1
      yield(cand)
    end
    if mv_cnt > 0 then
      yield(first_cand)
    end
  elseif input_len % 2 == 1 then
    local sp = input:sub(1, input_len - 1)
    local aux = input:sub(input_len, input_len)
    local iter = Module.translate_with_aux(env, seg, sp, aux)
    local first_cand = iter()
    local mv_cnt = 0
    if env.is_aux_priority and first_cand.text == env.previous_word then
      mv_cnt = 3;
    end
    env.previous_word = ""
    env.previous_word_aux = ""
    for cand in iter do
      if mv_cnt == 0 then
        yield(first_cand)
      end
      mv_cnt = mv_cnt - 1
      yield(cand)
    end
    if mv_cnt > 0 then
      yield(first_cand)
    end
  elseif input_len % 2 == 0 then
    local filled = false
    for cand, _ in Module.translate_without_aux(env, seg, input) do
      if not filled then
        env.previous_word = cand.text
        filled = true
      end
      yield(cand)
    end
  end
end

-- nil = unrestricted
function Module.get_prefetch_threshold(env, sp)
  local p = env.prefetch_threshold or -1
  if p <= 0 then
    return nil
  end
  if BIG_SYLLABLES[sp] then
    return math.max(BIG_SYLLABLES[sp], p)
  else
    return p
  end
end

-- Returns a stateful iterator of <Candidate, String?>.
function Module.translate_with_aux(env, seg, sp, aux)
  local iter = Module.translate_without_aux(env, seg, sp)
  local threshold = Module.get_prefetch_threshold(env, sp)
  local matched = {}
  local unmatched = {}
  local n_matched = 0
  local n_unmatched = 0
  for cand in iter do
    if Module.candidate_match(env, cand, aux) then
      table.insert(matched, cand)
      cand.comment = aux
      n_matched = n_matched + 1
    else
      table.insert(unmatched, cand)
      n_unmatched = n_unmatched + 1
    end
    if threshold and (n_matched + n_unmatched > threshold) then
      break
    end
  end

  local i = 1
  return function()
    if i <= n_matched then
      i = i + 1
      return matched[i - 1], aux
    elseif i <= n_matched + n_unmatched then
      i = i + 1
      return unmatched[i - 1 - n_matched], nil
    else
      -- late candidates can also be matched.
      local cand = iter()
      if Module.candidate_match(env, cand, aux) then
        cand.comment = aux
        return cand, aux
      else
        return cand, nil
      end
    end
  end
end

-- Returns a stateful iterator of <Candidate, String?>.
function Module.translate_without_aux(env, seg, sp)
  local translation = env.translator:query(sp, seg)
  if translation == nil then return function() return nil end end
  local advance, obj = translation:iter()
  return function()
    local c = advance(obj)
    return c, nil
  end
end

function Module.candidate_match(env, cand, aux)
  if not cand then
    return nil
  end
  if not (cand.type == "phrase" or cand.type == "user_phrase") then
    return false
  end

  for i, gt in pairs(Module.aux_list(env, cand.text)) do
    if aux == gt then
      return true
    end
  end
  return false
end

function Module.aux_list(env, word)
  local aux_list = {}
  local first = nil
  local last = nil
  local any_use = env.is_aux_for_any
  for _, c in utf8.codes(word) do
    if not first then first = c end
    last = c
    -- any char
    if any_use then
      local c_aux_list = env.aux_table[c]
      if c_aux_list then
        for _, c_aux in pairs(c_aux_list) do
          table.insert(aux_list, c_aux:sub(1, 1))
          table.insert(aux_list, c_aux)
        end
      end
    end
  end
  -- First char & last char
  if not any_use and env.is_aux_for_first then
    local c_aux_list = env.aux_table[first]
    for _, c_aux in pairs(c_aux_list) do
      table.insert(aux_list, c_aux:sub(1, 1))
      table.insert(aux_list, c_aux)
    end
  end
  if not any_use and env.is_aux_for_last then
    local c_aux_list = env.aux_table[last]
    for _, c_aux in pairs(c_aux_list) do
      table.insert(aux_list, c_aux:sub(1, 1))
      table.insert(aux_list, c_aux)
    end
  end
  return aux_list
end

return Module
