-- moran_aux_translator -- 實現直接輔助碼篩選的翻譯器
--
-- Author: ksqsf
-- License: GPLv3
-- Version: 0.2.0
--
-- 0.2.0: 重做。支持輔助碼下沉和諸多新的自定義選項。
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

-- 一些音節需要較多預取
local BIG_SYLLABLES = {
   ["ji"] = 200,
   ["ui"] = 200,
   ["yi"] = 200,
   ["ii"] = 200,
}

function Module.init(env)
   env.aux_table = moran.load_zrmdb()
   env.translator = Component.Translator(env.engine, "", "script_translator@translator")
   env.prefetch_threshold = env.engine.schema.config:get_int("moran/prefetch") or -1

   -- 詞組和單字優先情況
   env.word_over_char_tolerance = env.engine.schema.config:get_int("moran/word_over_char_tolerance") or 3
   env.word_over_char_adaptive = moran.get_config_bool(env, "moran/word_over_char_adaptive", true)
   env.performance_hack = true

   -- 固定句子爲首選
   env.is_sentence_priority = moran.get_config_bool(env, "moran/sentence_priority", true)
   env.sentence_priority_length = env.engine.schema.config:get_int("moran/sentence_priority_length") or 4

   -- 输入辅助码首选后移
   env.is_aux_priority = moran.get_config_bool(env, "moran/aux_priority", true)
   env.aux_priority_defer = env.engine.schema.config:get_int("moran/aux_priority_defer") or 3
   env.aux_priority_length = env.engine.schema.config:get_int("moran/aux_priority_length") or 1

   -- 輔助碼作用位置
   local aux_position = env.engine.schema.config:get_string("moran/aux_position") or "any"
   if aux_position == "first" then
      env.is_aux_for_first = true
   elseif aux_position == "last" then
      env.is_aux_for_last = true
   else
      env.is_aux_for_any = true
   end

   -- ----------------
   -- 讓全相關邏輯
   -- ----------------
   local previous_word = ""
   local previous_word_aux = ""
   local before_cb = function(index, cand)
      if index > 0 and cand.comment == "" then
         return nil
      end
      local should_defer =
         -- 尊重 aux_priority_length
         #cand.comment == env.aux_priority_length and
         -- 輸入比之前多一位輔碼
         #previous_word_aux + 1 == #cand.comment and
         -- 內容一致
         cand.text == previous_word and
         previous_word_aux == cand.comment:sub(1, #previous_word_aux)
      if should_defer then
         return env.aux_priority_defer
      else
         return nil
      end
   end
   local after_cb = function(index, cand)
      if index == 0 then
         previous_word = cand.text
         previous_word_aux = cand.comment
      end
   end
   if env.is_aux_priority then
      env.y = moran.Yielder.new(before_cb, after_cb)
   else
      env.y = moran.Yielder.new(nil, nil)
   end

   -- ------------------------------------
   -- 上屏邏輯（清空輔助碼和其他內部狀態）
   -- ------------------------------------
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

   -- 在自帶的 OnSelect 之後生效
   local function on_select_post(ctx)
      if aux_length then
         ctx.input = ctx.input:sub(1, #ctx.input - aux_length)
         if ctx.composition:has_finished_composition() then
            ctx:commit()
         end
      end
      aux_length = nil
      previous_word = ""
      previous_word_aux = ""
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
   env.y:reset()

   -- 每 10% 的翻譯觸發一次 GC
   if math.random() < 0.1 then
      collectgarbage()
   end

   local input_len = utf8.len(input) or 0
   if input_len <= 2 then
      env.y:yield_all(Module.translate_without_aux(env, seg, input))
   elseif input_len % 2 == 1 then
      Module.TranslateOdd(env, seg, input, input_len)
   else
      Module.TranslateEven(env, seg, input, input_len)
   end

   env.y:clear()
end

--- 應對輸入長度爲奇數的情況。
--- 輸入長度爲奇數時，input 的末碼爲輔碼，其餘部分爲雙拼。
---
--- @param env table
--- @param seg Segment
--- @param input string 當前輸入段對應的原始輸入
--- @param input_len number 原始輸入的 Unicode 字符數
function Module.TranslateOdd(env, seg, input, input_len)
   local sp = input:sub(1, input_len - 1)
   local aux = input:sub(input_len, input_len)

   -- 要求首選是句子時，總是先輸出句子。
   -- 但是在輸入長度爲 3 時，總是不輸出句子。
   if env.is_sentence_priority and input_len > 3 then
      local nonaux_iter = moran.make_peekable(Module.translate_without_aux(env, seg, input))
      if nonaux_iter:peek() and utf8.len(nonaux_iter:peek().text) >= env.sentence_priority_length then
         env.y:yield(nonaux_iter())
      end
   end

   -- 若之前已經輸出了句子候選，則跳過此後一切句子。
   local aux_iter = moran.make_peekable(Module.translate_with_aux(env, seg, sp, aux))
   if env.y.index > 0 and aux_iter:peek() and aux_iter:peek().type == "sentence" then
      aux_iter:next()
   end

   -- 帶輔翻譯。
   for cand in aux_iter do
      if cand.type ~= "sentence" then
         env.y:yield(cand)
      end
   end
end

--- 應對輸入長度爲偶數的情況。
--- 輸入長度爲偶數時，input 可能被理解爲 (1) 末二碼爲輔 (2) 全雙拼。
---
--- @param env table
--- @param seg Segment
--- @param input string 當前輸入段對應的原始輸入
--- @param input_len number 原始輸入的 Unicode 字符數
function Module.TranslateEven(env, seg, input, input_len)
   local sp = input:sub(1, input_len - 2)
   local aux = input:sub(input_len - 1, input_len)
   local nonaux_iter = moran.make_peekable(Module.translate_with_aux(env, seg, input))
   local aux_iter = moran.make_peekable(Module.translate_with_aux(env, seg, sp, aux))

   if -- 要求首選固定是句子
      env.is_sentence_priority
   then
      local c = nonaux_iter:peek()
      local c_len = c and utf8.len(c.text) or 0
      if c and c.type == "sentence" and c_len >= env.sentence_priority_length then
         env.y:yield(nonaux_iter:next())
         -- 只輸出一個句子：如果 aux 的第一個候選也是句子，就跳過
         if aux_iter:peek() and aux_iter:peek().type == "sentence" then
            aux_iter:next()
         end
      end
   end

   -- 遵守 word_over_char_tolerance：取出 tol 個 nonaux 詞語，再把 aux 首選放進去。
   local pool = moran.peekable_iter_take_while_upto(
      nonaux_iter,
      env.word_over_char_tolerance,
      function(c)
         return utf8.len(c.text) == input_len / 2
      end)
   if aux_iter:peek() and #aux_iter:peek().comment > 0 then
      table.insert(pool, aux_iter())
   end
   -- 遵守調頻要求
   if env.word_over_char_adaptive then
      table.sort(pool, function(a, b) return a.quality > b.quality end)
   end
   -- 輸出前 tol+1 個候選。
   for _, c in pairs(pool) do
      env.y:yield(c)
   end

   -- 輸出被輔候選。
   for c in aux_iter do
      if #c.comment > 0 then
         env.y:yield(c)
      else
         -- 已經結束了！
         break
      end
   end

   -- 輸出其他非輔候選。
   env.y:yield_all(nonaux_iter)
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
   if utf8.len(word) > 1 then
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
   end
   return aux_list
end

return Module
