-- Please see also moran_aux_hint.lua

local Module = {}

function Module.init(env)
   env.enable_quick_code_hint = env.engine.schema.config:get_bool("moran/enable_quick_code_hint")
   if env.enable_quick_code_hint then
      -- The user might have changed it.
      local dict = env.engine.schema.config:get_string("fixed/dictionary")
      env.quick_code_hint_reverse = ReverseLookup(dict)
      env.quick_code_hint_skip_chars = env.engine.schema.config:get_bool("moran/quick_code_hint_skip_chars") or false
   else
      env.quick_code_hint_reverse = nil
   end

   env.quick_code_indicator = env.engine.schema.config:get_string("moran/quick_code_indicator")
   env.enable_aux_hint = env.engine.schema.config:get_bool("moran/enable_aux_hint")
end

function Module.fini(env)
   env.quick_code_hint_reverse = nil
end

function Module.func(translation, env)
   if (not env.enable_quick_code_hint) or env.quick_code_hint_reverse == nil then
      for cand in translation:iter() do
         yield(cand)
      end
      return
   end

   local separator = "⚡"
   if env.quick_code_indicator ~= nil and env.quick_code_indicator ~= "" then
      separator = ""
   end

   -- Look up if the "geniune" candidate is already in the qc dict
   for cand in translation:iter() do
      local gcand = cand:get_genuine()
      local word = gcand.text
      if utf8.len(word) == 1 and env.quick_code_hint_skip_chars then
         yield(cand)
      else
         local all_codes = env.quick_code_hint_reverse:lookup(word)
         if all_codes then
            local codes = {}
            for code in all_codes:gmatch("%S+") do
               if #code < 4 -- and code ~= cand.preedit
               then
                  table.insert(codes, code)
               end
            end
            if #codes == 0 then
               goto continue
            end
            local codes_hint = table.concat(codes, " ")
            if env.enable_aux_hint then
               local comment = codes_hint .. separator .. gcand.comment
               cand = ShadowCandidate(gcand, cand.type, word, comment)
            else
               local comment = gcand.comment .. codes_hint
               cand = ShadowCandidate(gcand, cand.type, word, comment)
            end
         end
         ::continue::
         yield(cand)
      end
   end
end

return Module
