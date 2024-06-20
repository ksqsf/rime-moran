-- moran_aux_translator -- 實現直接輔助碼篩選的翻譯器
--
-- Author: ksqsf
-- License: GPLv3
-- Version: 0.1.3
--
-- 0.1.3: 優化邏輯。
--
-- 0.1.2：句子優先，避免輸入過程中首選長度大幅波動。一定程度上提高性能。
--
-- 0.1.1：三碼優先單字。
--
-- 0.1.0: 實作。

-- Test cases:
-- 1. fal -> 乏了
-- 2. fan -> 姂
-- 3. mzhwr -> 美化
-- 4. vshwd -> 种花的

local moran = require("moran")
local Module = {}
Module.PREFETCH_THRESHOLD = 50

function Module.init(env)
   env.aux_table = moran.load_zrmdb()
   env.translator = Component.Translator(env.engine, "", "script_translator@translator")

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
      if cand.comment and cand.comment ~= "" then
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

   if input_len <= 2 then
      for cand, _ in Module.translate_without_aux(env, seg, input) do
         yield(cand)
      end
   elseif input_len == 3 then
      local sp = input:sub(1, input_len-1)
      local aux = input:sub(input_len, input_len)
      local iter = Module.translate_with_aux(env, seg, sp, aux)
      local char_cand = iter()
      if char_cand.comment ~= "" then
         yield(char_cand)
         for cand in iter do
            yield(cand)
         end
      else
         local second_iter = Module.translate_without_aux(env, seg, input)
         for cand in second_iter do
            yield(cand)
         end
      end
   elseif input_len % 2 == 0 then
      -- first_iter 对应于无辅助码的候选
      local first_iter = Module.translate_without_aux(env, seg, input)
      local first_cand = first_iter()
      if first_cand then
         -- 优先输出句子
         if first_cand.type == "sentence" then
            yield(first_cand)
            first_cand = first_iter()
         end
      end

      -- second_iter 对应于有辅助码的候选
      -- 当 input_len == 4 时，second_iter 里应该只有单字
      -- 这里只从里面取出匹配的候选（phrase or user_phrase），并前置
      local sp = input:sub(1, input_len-2)
      local aux = input:sub(input_len-1, input_len)
      local second_iter = Module.translate_with_aux(env, seg, sp, aux)
      local second_cand = second_iter()
      if second_cand and second_cand.type == "sentence" then
         -- 跳过句子，这个句子和 first_iter 的句子只差一个字
         second_cand = second_iter()
      end

      -- 從此開始，依 quality 輸出 first_iter 中的候選 和 second_iter 中匹配的候選
      while first_cand or second_cand
      do
         if (second_cand and second_cand.comment ~= "") and first_cand
         then
            if first_cand.quality > second_cand.quality then
               yield(first_cand)
               first_cand = first_iter()
            else
               yield(second_cand)
               second_cand = second_iter()
            end
         elseif first_cand then   -- second_iter done
            yield(first_cand)
            first_cand = first_iter()
         elseif second_cand then  -- first_iter done
            if second_cand.comment ~= "" then
               yield(second_cand)
               second_cand = second_iter()
            else
               -- 没有符合条件的候选了，不再继续探索
               second_cand = nil
            end
         end
      end
   else  -- input_len >= 5
      local first_iter = Module.translate_without_aux(env, seg, input)
      local first_cand = first_iter()

      local sp = input:sub(1, input_len-1)
      local aux = input:sub(input_len, input_len)
      local second_iter = Module.translate_with_aux(env, seg, sp, aux)
      local second_cand = second_iter()
      if second_cand then
         local typ = second_cand.type
         local second_len = utf8.len(second_cand.text)
         local second_is_lifted = second_cand.comment ~= ""
         -- this is a lifted word, drop first_cand then.
         if (typ == "phrase" or typ == "user_phrase") and second_len > 1 and second_is_lifted then
            yield(second_cand)
         else
            if first_cand then
               yield(first_cand)
            end
            if typ ~= "sentence" then
               yield(second_cand)
            end
         end
      else
         if first_cand then
            yield(first_cand)
         end
      end

      for cand in second_iter do
         yield(cand)
      end
   end
end

-- Returns a stateful iterator of <Candidate, String?>.
function Module.translate_with_aux(env, seg, sp, aux)
   local iter = Module.translate_without_aux(env, seg, sp)

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
      if n_matched + n_unmatched > Module.PREFETCH_THRESHOLD then
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
         return iter(), nil
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
   local char_list = {}
   local first = nil
   local last = nil

   -- Single char
   for i, c in utf8.codes(word) do
      if not first then first = c end
      last = c

      local c_aux_list = env.aux_table[c]
      if c_aux_list then
         for i, c_aux in pairs(c_aux_list) do
            table.insert(aux_list, c_aux:sub(1,1))
            table.insert(aux_list, c_aux)
         end
      end
   end

   -- First char & last char
   if utf8.len(word) >= 2 then
      local f_aux_list = env.aux_table[first]
      local l_aux_list = env.aux_table[last]

      for i, f_aux in pairs(f_aux_list) do
         for j, l_aux in pairs(l_aux_list) do
            table.insert(aux_list, f_aux:sub(1,1) .. l_aux:sub(1,1))
            table.insert(aux_list, l_aux:sub(1,1) .. f_aux:sub(1,1))
         end
      end
   end

   return aux_list
end

-- Not used currently. Kept for reservation.
--
-- function Module.merge_candidates(iter, jter)
--    local i, iaux = iter()
--    local j, jaux = jter()
--    local function advance_i(value)
--       --log.error("i " .. value.text .. "  " .. tostring(value:get_genuine().quality) .. " " .. value.comment)
--       i, iaux = iter()
--       return value
--    end
--    local function advance_j(value)
--       --log.error("j " .. value.text .. "  " .. tostring(value:get_genuine().quality) .. " " .. value.comment)
--       j, jaux = jter()
--       return value
--    end
--    return function()
--       if i == nil then return advance_j(j) end
--       if j == nil then return advance_i(i) end
--       if iaux ~= nil and jaux == nil then
--          if utf8.len(i.text) ~= 1 then
--             return advance_i(i)
--          else
--             if j:get_genuine().quality > i:get_genuine().quality then
--                return advance_j(j)
--             else
--                return advance_i(i)
--             end
--          end
--       elseif iaux == nil and jaux ~= nil then
--          if utf8.len(j.text) ~= 1 then
--             return advance_j(j)
--          else
--             if i:get_genuine().quality > j:get_genuine().quality then
--                return advance_i(i)
--             else
--                return advance_j(j)
--             end
--          end
--       elseif utf8.len(i:get_genuine().text) > utf8.len(j:get_genuine().text) then
--          return advance_i(i)
--       elseif utf8.len(j:get_genuine().text) > utf8.len(i:get_genuine().text) then
--          return advance_j(j)
--       elseif i:get_genuine().quality > j:get_genuine().quality then
--          return advance_i(i)
--       else
--          return advance_j(j)
--       end
--    end
-- end

return Module
