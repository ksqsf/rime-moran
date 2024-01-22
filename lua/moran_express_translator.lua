-- Moran Translator (for Express Editor)
-- Copyright (c) 2023 ksqsf
--
-- Ver: 0.5.0
--
-- This file is part of Project Moran
-- Licensed under GPLv3
--
-- 0.5.0: 修復詞庫維護問題。使用簡碼鍵入的字的字頻，不會被增加到
-- script translator 的用戶詞庫中，導致長時間使用後，生僻字的字頻反而
-- 更高，構詞和整句會被干擾。
--
-- 在方案中引用時，需增加 @with_reorder 標記，並把
-- moran_reorder_filter 添加爲第一個 filter。
--
-- 0.4.2: 修復內存泄露。
--
-- 0.4.0: 增加詞輔功能。
--
-- 0.3.2: 允許用戶自定義出簡讓全的各項設置：是否啓用、延遲幾位候選、是
-- 否顯示簡快碼提示。
--
-- 0.3.1: 允許自定義簡快碼提示符。
--
-- 0.3.0: 增加單字輸出的出簡讓全。
--
-- 0.2.0: 增加固定二字詞模式。
--
-- 0.1.0: 本翻譯器用於解決 Rime 原生的翻譯流程中，多翻譯器會互相干擾、
-- 導致造詞機能受損的問題。以「驚了」造詞爲例：用戶輸入 jym le，選擇第
-- 一個字「驚」後，再選「了」字，這時候將無法造出「驚了」這個詞。這是
-- 因爲「了」是從碼表翻譯器輸出的，在 script 翻譯器的視角看來，並不知
-- 道用戶輸出了「驚了」兩個字，所以造不出詞。
--
-- 目前版本的解決方法是：用戶選過字後，臨時禁用 table 翻譯器，使得
-- script 可以看到所有輸入，從而解決造詞問題。

local top = {}

function top.init(env)
   env.fixed = Component.Translator(env.engine, "", "table_translator@fixed")
   env.smart = Component.Translator(env.engine, "", "script_translator@translator")
   env.rfixed = ReverseLookup(env.engine.schema.config:get_string("fixed/dictionary") or "moran_fixed")
   env.quick_code_indicator = env.engine.schema.config:get_string("moran/quick_code_indicator") or "⚡️"
   if env.name_space == 'with_reorder' then
      env.quick_code_indicator = '`F'
   end
   env.ijrq_enable = env.engine.schema.config:get_bool("moran/ijrq/enable")
   env.ijrq_defer = env.engine.schema.config:get_int("moran/ijrq/defer") or env.engine.schema.config:get_int("menu/page_size") or 5
   env.ijrq_hint = env.engine.schema.config:get_bool("moran/ijrq/show_hint")
   env.ijrq_suffix = env.engine.schema.config:get_string("moran/ijrq/suffix") or 'o'
   env.enable_word_filter = env.engine.schema.config:get_bool("moran/enable_word_filter")

   -- 默認情況下 Lua GC 過於保守
   collectgarbage("setpause", 110)
end

function top.fini(env)
end

function top.func(input, seg, env)
   -- 每 10% 的翻譯觸發一次 GC
   if math.random() < 0.1 then
      collectgarbage()
   end

   local input_len = utf8.len(input)
   local fixed_triggered = false
   local inflexible = env.engine.context:get_option("inflexible")
   local indicator = env.quick_code_indicator

   -- 用戶尚未選過字時，調用碼表。
   if (env.engine.context.input == input) then
      local fixed_res = env.fixed:query(input, seg)
      -- 如果輸入長度爲 4，只輸出 2 字詞。
      -- 僅在 inflexible （固詞模式）時才產生這些輸出。
      if fixed_res ~= nil then
         if (input_len == 4) then
            if inflexible then
               for cand in fixed_res:iter() do
                  local cand_len = utf8.len(cand.text)
                  if (cand_len == 2) then
                     cand.comment = indicator
                     yield(cand)
                     fixed_triggered = true
                  end
               end
            end
         else
            for cand in fixed_res:iter() do
               cand.comment = indicator
               yield(cand)
               fixed_triggered = true
            end
         end
      end
   end

   -- 詞輔在正常輸出之前，以提高其優先級
   if env.enable_word_filter and (input_len == 5 or input_len == 7) then
      local real_input = input:sub(1, input_len - 1)
      local user_ac = input:sub(input_len, input_len)
      local iter = top.raw_query_smart(env, real_input, seg, true)
      for cand in iter do
         idx = cand.comment:find(user_ac)
         if idx ~= nil and ((input_len == 5) or (input_len == 7 and idx ~= 1)) then
            cand._end = cand._end + 1
            cand.preedit = input
            yield(cand)
         end
      end
   end

   -- smart 在 fixed 之後輸出。
   local smart_iter = top.raw_query_smart(env, input, seg, false)
   if smart_iter ~= nil then
      if not env.ijrq_enable then
         -- 不啓用出簡讓全時
         for cand in smart_iter do
            yield(cand)
         end
      else
         -- 啓用出簡讓全時
         local ijrq_enabled = true
            and (env.engine.context.input == input)
            and ((input_len == 4) or (input_len == 5 and input:sub(5,5) == env.ijrq_suffix))
         local immediate_set = {}
         local deferred_set = {}
         for cand in smart_iter do
            local defer = false
            -- 如果輸出有詞，說明在拼詞，用戶很可能要使用高頻字，故此時停止出簡讓全。
            if (ijrq_enabled and utf8.len(cand.text) > 1) then
               ijrq_enabled = false
            end
            if (ijrq_enabled and utf8.len(cand.text) == 1) then
               local fixed_codes = env.rfixed:lookup(cand.text)
               for code in fixed_codes:gmatch("%S+") do
                  if #code < 4
                     and string.sub(input, 1, #code) == code
                  then
                     defer = true
                     if env.ijrq_hint and cand.preedit:sub(1,4) == input:sub(1,4) then
                        cand.comment = code
                     end
                     break
                  end
               end
            end
            if (not defer) then
               table.insert(immediate_set, cand)
            else
               table.insert(deferred_set, cand)
            end
         end
         for i = 1, math.min(env.ijrq_defer, #immediate_set) do
            yield(immediate_set[i])
         end
         for i = 1, #deferred_set do
            yield(deferred_set[i])
         end
         for i = math.min(env.ijrq_defer, #immediate_set) + 1, #immediate_set do
            yield(immediate_set[i])
         end
      end
   end

   -- 如果 smart 輸出爲空，並且 fixed 之前沒有調用過，此時再嘗試調用一下
   if smart_iter == nil and not fixed_triggered then
      local fixed_res = env.fixed:query(input, seg)
      if fixed_res ~= nil then
         for cand in fixed_res:iter() do
            local cand_len = utf8.len(cand.text)
            cand.comment = indicator
            yield(cand)
         end
      end
   end
end

-- | Query the smart translator for input, and transform the comment
-- | for candidates whose length is 2 or 3 characters long.
function top.raw_query_smart(env, input, seg, with_comment)
   local translation = env.smart:query(input, seg)
   if translation == nil then
      return nil
   end
   local nxt, thisobj = translation:iter()
   return function()
      local cand = nxt(thisobj)
      if cand == nil then
         return nil
      end
      local cand_len = utf8.len(cand.text)
      if cand_len == 2 or cand_len == 3 then
         if with_comment then
            cand:get_genuine().comment = cand.comment:gsub("[a-z]+;([a-z])[a-z] ?", "%1")
         else
            cand:get_genuine().comment = ""
         end
      else
         cand:get_genuine().comment = ""
      end
      return cand
   end
end

return top
