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
   env.quick_code_indicator = env.engine.schema.config:get_string("moran/quick_code_indicator") or "⚡"
end

function Module.fini(env)
   env.quick_code_hint_reverse = nil
   collectgarbage()
end

function Module.func(translation, env)
   if (not env.enable_quick_code_hint) or env.quick_code_hint_reverse == nil then
      for cand in translation:iter() do
         yield(cand)
      end
      return
   end

   -- Look up if the "geniune" candidate is already in the qc dict
   for cand in translation:iter() do
      local gcand = cand:get_genuine()
      local word = gcand.text
      if utf8.len(word) == 1 and env.quick_code_hint_skip_chars then
         yield(cand)
      else
         local all_codes = env.quick_code_hint_reverse:lookup(word)
         local in_use = false
         if all_codes then
            local codes = {}
            for code in all_codes:gmatch("%S+") do
               if #code < 4 then
                  if code == cand.preedit then
                     in_use = true
                  else
                     table.insert(codes, code)
                  end
               end
            end
            if #codes == 0 and not in_use then
               goto continue
            end
            local codes_hint = table.concat(codes, " ")
            local comment = ""
            if gcand.comment == env.quick_code_indicator then
               -- Avoid double ⚡
               comment = gcand.comment .. codes_hint
            else
               comment = gcand.comment .. env.quick_code_indicator .. codes_hint
            end
            gcand.comment = comment
         end
         ::continue::
         yield(cand)
      end
   end
end

return Module
