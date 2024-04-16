-- moran_semicolon_processor.lua
-- Synopsis: 選擇第二個首選項，但可用於跳過 emoji 濾鏡產生的候選
-- Author: ksqsf
-- License: MIT license
-- Version: 0.1.1

-- NOTE: This processor depends on, and thus should be placed before,
-- the built-in "selector" processor.

local moran = require("moran")

local kReject = 0
local kAccepted = 1
local kNoop = 2

local function processor(key_event, env)
   local context = env.engine.context

   if key_event.keycode ~= 0x3B or key_event:release() then
      return kNoop
   end

   local composition = context.composition
   if composition:empty() then
      return kNoop
   end

   local segment = composition:back()
   local menu = segment.menu

   -- If it is not the first page, simply send 2.
   local page_size = env.engine.schema.page_size
   local selected_index = segment.selected_index
   if selected_index >= page_size then
      env.engine:process_key(KeyEvent("2"))
      return kAccepted
   end

   -- First page: do something more sophisticated.
   local i = 1
   while i < page_size do
      local cand = menu:get_candidate_at(i)
      local cand_text = cand.text
      local codepoint = utf8.codepoint(cand_text, 1)
      if moran.unicode_code_point_is_chinese(codepoint) then
         env.engine:process_key(KeyEvent(tostring(i+1)))
         return kAccepted
      end
      i = i + 1
   end

   -- No good candidates found. Just select the second candidate.
   env.engine:process_key(KeyEvent("2"))
   return kAccepted
end

return processor
