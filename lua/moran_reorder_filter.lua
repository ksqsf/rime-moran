-- Moran Reorder Filter
-- Copyright (c) 2023, 2024 ksqsf
--
-- Ver: 0.1.5
--
-- This file is part of Project Moran
-- Licensed under GPLv3
--
-- 0.1.5: 少許性能優化。
--
-- 0.1.4: 配合 moran_pin。
--
-- 0.1.3: 修復一個導致候選重複輸出的 bug。
--
-- 0.1.2: 配合 show_chars_anyway 設置。從 show_chars_anyway 設置起，
-- fixed 輸出有可能出現在 script 之後！此情況只覆寫 comment 而不做重排。
--
-- 0.1.1: 要求候選項合併時 preedit 也匹配，以防禦一種邊角情況（掛接某
-- 些第三方碼表時可能出現）。
--
-- 0.1.0: 本文件的主要作用是用 script 候選覆蓋對應的 table 候選，從而
-- 解決字頻維護問題。例如：原本用 mau 輸入三簡字「碼」時，該候選是從
-- table 輸出的，不會增加 script 翻譯器用戶詞典的「碼」字的字頻。而長
-- 期使用時，很有可能會使用 mau 鍵入「禡」等較生僻的字，而這些生僻字反
-- 而是從 script 翻譯器輸出的，會增加這些字的字頻。這個問題會導致在長
-- 期使用後，組詞時會導致常用的「碼」反而排在其他生僻字後面。該 filter
-- 的主要作用就是重排 table 和 script 翻譯器輸出，讓簡碼對應的候選也變
-- 成 script 候選，從而解決字頻問題。
--
-- 必須與 moran_express_translator v0.5.0 以上版本聯用。

local Top = {}

function Top.init(env)
   -- At most THRESHOLD smart candidates are subject to reordering,
   -- for performance's sake.
   env.reorder_threshold = 50
   env.quick_code_indicator = env.engine.schema.config:get_string("moran/quick_code_indicator") or "⚡️"
   env.pin_indicator = env.engine.schema.config:get_string("moran/pin/indicator") or "📌"
end

function Top.fini(env)
end

function Top.func(t_input, env)
   local fixed_list = {}
   local smart_list = {}
   local delay_slot = {}
   local pin_set = {}
   -- the candidates we receive are:
   --   [pinned]* [fixed1]* smart1{1} [fixed2]* smart2+
   -- phase 0: pinned, fixed1, and smart1 cands not yet all handled
   -- phase 1: found the first smart2 candidate
   -- phase 2: done reordering
   local reorder_phase = 0
   local threshold = env.reorder_threshold
   local additional_check = 0  -- max length of the delay slot
   for cand in t_input:iter() do
      if cand:get_genuine().type == "punct" then
         yield(cand)
         goto continue
      end

      if reorder_phase == 0 then
         if cand.comment == '`F' then
            if not pin_set[cand.text] then
               table.insert(fixed_list, cand)
            end
         elseif cand.type == 'pinned' then
            table.insert(fixed_list, cand)
            pin_set[cand.text] = true
            -- Need to check an extra candidate if pinned candidates are
            -- found to ensure all fixed candidates are included.
            additional_check = 1
         elseif additional_check > 0 then
            -- Smart1 case: just record it and possibly merge it later
            -- in Phase 1.
            table.insert(delay_slot, cand)
            additional_check = additional_check - 1
         elseif #delay_slot == 0 then
            -- Smart2 case, where no smart1 found.
            -- Logically equivalent to goto the branch of reorder_phase=1.
            reorder_phase = 1
            threshold = threshold - 1
            reorder_phase = Top.DoPhase1(env, fixed_list, smart_list, cand)
         elseif #delay_slot > 0 then
            -- Smart2 case, where some smart1 candidates in the delay slot.
            for _, c in ipairs(delay_slot) do
               threshold = threshold - 1
               reorder_phase = Top.DoPhase1(env, fixed_list, smart_list, c)
            end
            if reorder_phase == 2 then
               -- all done. Yield current and future candidates directly.
               yield(cand)
            else
               -- not done! Proceed to phase1.
               threshold = threshold - 1
               reorder_phase = Top.DoPhase1(env, fixed_list, smart_list, cand)
            end
         end
      elseif reorder_phase == 1 then
         threshold = threshold - 1
         reorder_phase = Top.DoPhase1(env, fixed_list, smart_list, cand)
         if threshold < 0 then
            Top.ClearEntries(env, reorder_phase, fixed_list, smart_list, delay_slot)
            reorder_phase = 2
         end
      else
         -- All candidates are either from the script translator, or
         -- injected secondary candidates.
         if cand.comment == "`F" then
            cand.comment = env.quick_code_indicator
         end
         yield(cand)
      end

      ::continue::
   end

   Top.ClearEntries(env, reorder_phase, fixed_list, smart_list, delay_slot)
end

function Top.CandidateMatch(scand, fcand)
   -- Additionally check preedits.  This check defends against the
   -- case where the scand is NOT really a complete candidate (for
   -- example, only "qt" is translated by the script translator when
   -- the input is actually "qty".)
   return scand.text == fcand.text and
      ((#scand.preedit == #fcand.preedit and scand.preedit == fcand.preedit)
         -- Special-case two-char word
         or (#scand.preedit == 5 and #fcand.preedit == 4 and (scand.preedit:sub(1,2) .. scand.preedit:sub(4,5)) == fcand.preedit))
end

local function reorderable(cand)
   return not (utf8.len(cand.text) > 1 and #cand.preedit <= 3)
end

-- Return 2 if fixed_list is handled completely.
-- Otherwise, return 1.
function Top.DoPhase1(env, fixed_list, smart_list, cand)
   table.insert(smart_list, cand)
   while #fixed_list > 0 and #smart_list > 0 do
      local scand = smart_list[#smart_list]
      local fcand = fixed_list[1]
      if not reorderable(fcand) then
         if fcand.comment == "`F" then
            fcand.comment = env.quick_code_indicator
         end
         yield(fcand)
         table.remove(fixed_list, 1)
      elseif Top.CandidateMatch(scand, fcand) then
         if fcand.comment == "`F" then
            scand.comment = env.quick_code_indicator
         elseif fcand.type == "pinned" then
            scand.comment = env.pin_indicator
         end
         yield(scand)
         table.remove(smart_list, #smart_list)
         table.remove(fixed_list, 1)
      else
         break
      end
   end
   if #fixed_list == 0 then
      for key, cand in ipairs(smart_list) do
         yield(cand)
         smart_list[key] = nil
      end
      return 2
   else
      return 1
   end
end

function Top.ClearEntries(env, reorder_phase, fixed_list, smart_list, delay_slot)
   for i, cand in ipairs(fixed_list) do
      if cand.comment == "`F" then
         cand.comment = env.quick_code_indicator
      end
      yield(cand)
      fixed_list[i] = nil
   end
   for i, cand in ipairs(delay_slot) do
      yield(cand)
      delay_slot[i] = nil
   end
   for i, cand in ipairs(smart_list) do
      if cand.comment == "`F" then
         cand.comment = env.quick_code_indicator
      end
      yield(cand)
      smart_list[i] = nil
   end
end

return Top
