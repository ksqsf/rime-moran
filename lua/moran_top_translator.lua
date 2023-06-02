-- Moran's Top Translator
-- Copyright (c) 2023 ksqsf
--
-- Ver: 0.1.0
--
-- This file is part of Project Moran
-- Licensed under GPLv3
--
-- 本翻譯器用於解決 Rime 原生的翻譯流程中，多翻譯器會互相干擾、導致造
-- 詞機能受損的問題。以「驚了」造詞爲例：用戶輸入 jym le，選擇第一個字
-- 「驚」後，再選「了」字，這時候將無法造出「驚了」這個詞。這是因爲
-- 「了」是從碼表翻譯器輸出的，在 script 翻譯器的視角看來，並不知道用
-- 戶輸出了「驚了」兩個字，所以造不出詞。
--
-- 目前版本的解決方法是：用戶選過字後，臨時禁用 table 翻譯器，使得
-- script 可以看到所有輸入，從而解決造詞問題。

local top = {}
local fixed = nil
local smart = nil

function top.init(env)
   fixed = Component.Translator(env.engine, "", "table_translator@fixed")
   smart = Component.Translator(env.engine, "", "script_translator@smart")
end

function top.fini(env)
end

function top.func(input, seg, env)
   if (env.engine.context.input == input) then
      local fixed_res = fixed:query(input, seg)
      for cand in fixed_res:iter() do
         yield(cand)
      end
   end

   local smart_res = smart:query(input, seg)
   for cand in smart_res:iter() do
      yield(cand)
   end
end

return top
