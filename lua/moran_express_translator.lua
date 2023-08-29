-- Moran Translator (for Express Editor)
-- Copyright (c) 2023 ksqsf
--
-- Ver: 0.3.0
--
-- This file is part of Project Moran
-- Licensed under GPLv3
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
   env.rfixed = ReverseLookup('moran_fixed')
end

function top.fini(env)
end

function top.func(input, seg, env)
   local input_len = utf8.len(input)
   local fixed_triggered = false
   local flexible = env.engine.context:get_option("flexible")

   -- 用戶尚未選過字時，調用碼表。
   if (env.engine.context.input == input) then
      local fixed_res = env.fixed:query(input, seg)
      -- 如果輸入長度爲 4，只輸出 2 字詞。
      -- 僅在 not flexible （固詞模式）時才產生這些輸出。
      if fixed_res ~= nil then
         if (input_len == 4) then
            if (not flexible) then
               for cand in fixed_res:iter() do
                  local cand_len = utf8.len(cand.text)
                  if (cand_len == 2) then
                     cand.comment = "⚡️"
                     yield(cand)
                     fixed_triggered = true
                  end
               end
            end
         else
            for cand in fixed_res:iter() do
               cand.comment = "⚡️"
               yield(cand)
               fixed_triggered = true
            end
         end
      end
   end

   -- 出簡讓全。
   local ijrq_enabled = true
      and (env.engine.context.input == input)
      and ((input_len == 4) or (input_len == 5 and input:sub(5,5) == 'o'))
   local ijrq_deferred = {}

   -- smart 在 fixed 之後輸出。
   local smart_res = env.smart:query(input, seg)
   if smart_res ~= nil then
      for cand in smart_res:iter() do
         local defer = false
         -- 如果輸出有詞，說明在拼詞，用戶很可能要使用高頻字，故此時停止出簡讓全。
         if (ijrq_enabled and utf8.len(cand.text) > 1) then
            ijrq_enabled = false
         end
         if (ijrq_enabled and utf8.len(cand.text) == 1) then
            local fixed_codes = env.rfixed:lookup(cand.text)
            for code in fixed_codes:gmatch("%S+") do
               if (#code < 4 and string.sub(input, 1, #code) == code) then
                  defer = true
                  break
               end
            end
         end
         if (not defer) then
            yield(cand)
         else
            table.insert(ijrq_deferred, cand)
         end
      end
      for i, cand in ipairs(ijrq_deferred) do
         yield(cand)
      end
   end

   -- 如果 smart 輸出爲空，並且 fixed 之前沒有調用過，此時再嘗試調用一下
   if smart_res == nil and not fixed_triggered then
      local fixed_res = env.fixed:query(input, seg)
      if fixed_res ~= nil then
         for cand in fixed_res:iter() do
            local cand_len = utf8.len(cand.text)
            cand.comment = "⚡"
            yield(cand)
         end
      end
   end
end

return top
