-- moran_aux_translator -- 實現直接輔助碼篩選的翻譯器
--
-- Author: ksqsf
-- License: GPLv3
-- Version: 0.1.0

local moran = require("moran")
local Module = {}
Module.PREFETCH_THRESHOLD = 50

function Module.init(env)
   collectgarbage("setpause", 110)
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
end

function Module.func(input, seg, env)
   local input_len = utf8.len(input)

   if input_len <= 2 then
      for cand, _ in Module.translate_without_aux(env, seg, input) do
         yield(cand)
      end
   elseif input_len % 2 == 0 then
      local first_iter = Module.translate_without_aux(env, seg, input)

      local sp = input:sub(1, input_len-2)
      local aux = input:sub(input_len-1, input_len)
      local second_iter = Module.translate_with_aux(env, seg, sp, aux)

      for cand in Module.merge_candidates(first_iter, second_iter) do
         yield(cand)
      end
   else
      local first_iter = Module.translate_without_aux(env, seg, input)

      local sp = input:sub(1, input_len-1)
      local aux = input:sub(input_len, input_len)
      local second_iter = Module.translate_with_aux(env, seg, sp, aux)

      for cand in Module.merge_candidates(first_iter, second_iter) do
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
   for i, c in moran.chars(word) do
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
   f_aux_list = env.aux_table[first]
   l_aux_list = env.aux_table[last]

   for i, f_aux in pairs(f_aux_list) do
      for j, l_aux in pairs(l_aux_list) do
         table.insert(aux_list, f_aux:sub(1,1) .. l_aux:sub(1,1))
         table.insert(aux_list, l_aux:sub(1,1) .. f_aux:sub(1,1))
      end
   end

   return aux_list
end

function Module.merge_candidates(iter, jter)
   local i, iaux = iter()
   local j, jaux = jter()
   local function advance_i(value)
      --log.error("i " .. value.text .. "  " .. tostring(value:get_genuine().quality) .. " " .. value.comment)
      i, iaux = iter()
      return value
   end
   local function advance_j(value)
      --log.error("j " .. value.text .. "  " .. tostring(value:get_genuine().quality) .. " " .. value.comment)
      j, jaux = jter()
      return value
   end
   return function()
      if i == nil then return advance_j(j) end
      if j == nil then return advance_i(i) end
      if iaux ~= nil and jaux == nil then
         if utf8.len(i.text) ~= 1 then
            return advance_i(i)
         else
            if j:get_genuine().quality > i:get_genuine().quality then
               return advance_j(j)
            else
               return advance_i(i)
            end
         end
      elseif iaux == nil and jaux ~= nil then
         if utf8.len(j.text) ~= 1 then
            return advance_j(j)
         else
            if i:get_genuine().quality > j:get_genuine().quality then
               return advance_i(i)
            else
               return advance_j(j)
            end
         end
      elseif utf8.len(i:get_genuine().text) > utf8.len(j:get_genuine().text) then
         return advance_i(i)
      elseif utf8.len(j:get_genuine().text) > utf8.len(i:get_genuine().text) then
         return advance_j(j)
      elseif i:get_genuine().quality > j:get_genuine().quality then
         return advance_i(i)
      else
         return advance_j(j)
      end
   end
end

return Module
