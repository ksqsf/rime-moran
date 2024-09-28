-- Moran Fix Filter
-- Copyright (c) 2024 ksqsf
--
-- Ver: 0.1.0
--
-- This file is part of Project Moran
-- Licensed under GPLv3
--
-- 0.1.0: added.

local moran = require("moran")
local Top = {}

function Top.init(env)
   -- At most THRESHOLD smart candidates are subject to reordering,
   -- for performance's sake.
   env.reorder_threshold = 200
   env.quick_code_indicator = env.engine.schema.config:get_string("moran/quick_code_indicator") or "⚡️"
   env.cache = {}
end

function Top.fini(env)
   env.cache = nil
   collectgarbage()
end

function Top.func(t_input, env)
   local input = env.engine.context.input
   local input_len = utf8.len(input)

   -- 只支持一二簡
   if input_len > 2 then
      for cand in t_input:iter() do
         yield(cand)
      end
      return
   end

   local needle = Top.get_needle(env, input)
   if needle == nil or needle == "" then
      for cand in t_input:iter() do
         yield(cand)
      end
      return
   end

   local threshold = env.reorder_threshold
   local stash = {}
   local iter = moran.iter_translation(t_input)
   local found = nil
   for cand in iter do
      if cand:get_genuine().type == "punct" then
         yield(cand)
         goto continue
      end

      if cand.text == needle then
         found = cand
         break
      elseif threshold > 0 then
         threshold = threshold - 1
         table.insert(stash, cand)
      else
         table.insert(stash, cand)
         break
      end

      ::continue::
   end

   if found then
      found:get_genuine().comment = env.quick_code_indicator
      yield(found)
   end

   for i, cand in pairs(stash) do
      yield(cand)
   end

   for cand in iter do
      yield(cand)
   end
end

function Top.get_needle(env, input)
   if env.cache[input] then
      return env.cache[input]
   end
   if input:find("/") then
      return nil
   end
   local val = env.engine.schema.config:get_string("moran/fix/" .. input)
   env.cache[input] = val
   return val
end

return Top
