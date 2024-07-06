-- moran_ijrq_filter.lua 詞語級出簡讓全
--
-- Part of Project Moran
-- License: GPLv3
-- Version: 0.1.0

local moran = require("moran")
local Module = {}

function Module.init(env)
   env.enabled = env.engine.schema.config:get_bool("moran/ijrq/enable_word")
end

function Module.fini(env)
end

function Module.func(t_input, env)
   if not env.enabled then
      for cand in t_input:iter() do
         yield(cand)
      end
      return
   end

   local context = env.engine.context
   local input = context.input
   local input_len = utf8.len(input)
   local iter = moran.iter_translation(t_input)

   -- The idea is to save the first cand when we first reach len=4.
   -- 1) lmjx 1. 鏈接
   -- 2) lmjxf 鏈接 -- same as lmjx, so postpone it -> 1. 連接 2. 鏈接
   -- 3) lmjxfxxx -- write something more
   -- 4) lmjxf -- remove xxx and get lmjxf again, we should keep the candidate list stable

   -- but we can only postpone inside the same GROUP
   -- e.g. uixmw should output 實現, as there is no other words have the same code
   -- a GROUP can be defined as (1) same text length (2) same code length

   if input_len == 4 or input_len == 6 or input_len == 8 then
      local first_cand = iter()
      if not first_cand then
         return
      end
      env.last_input = input
      env.last_first_cand = first_cand:get_genuine().text
      yield(first_cand)
      moran.yield_all(iter)
   elseif input_len == 5 or input_len == 7 or input_len == 9 then
      if input:sub(1,input_len-1) ~= env.last_input then
         moran.yield_all(iter)
         return
      end

      local postpone = false
      local pset = {}
      local real_first_cand = nil  -- actually, it is only REAL if it is in the same GROUP
      for c in iter do
         -- a genuine cand may generate multiple cands
         local g = c:get_genuine()
         if g.text == env.last_first_cand then
            table.insert(pset, c)
         else
            real_first_cand = c
            break
         end
      end

      if real_first_cand then
         if utf8.len(real_first_cand.text) == utf8.len(env.last_first_cand) then
            -- same group!
            postpone = true
         else
            postpone = false
         end
      end

      if postpone then
         if real_first_cand then yield(real_first_cand) end
         for _,c in pairs(pset) do yield(c) end
         for c in iter do yield(c) end
      else
         for _,c in pairs(pset) do yield(c) end
         if real_first_cand then yield(real_first_cand) end
         for c in iter do yield(c) end
      end
   else
      moran.yield_all(iter)
   end
end

return Module
