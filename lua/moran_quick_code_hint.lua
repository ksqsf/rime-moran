local Module = {}

function Module.init(env)
   env.enable_quick_code_hint = env.engine.schema.config:get_bool("moran/enable_quick_code_hint")
   if env.enable_quick_code_hint then
      -- The user might have changed it.
      local dict = env.engine.schema.config:get_string("fixed/dictionary")
      env.quick_code_hint_reverse = ReverseLookup(dict)
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

   -- Look up if the "geniune" candidate is already in the qc dict
   local indicator = env.quick_code_indicator
   if env.enable_aux_hint and indicator == "" then
      indicator = "⚡"
   end
   for cand in translation:iter() do
      local gcand = cand:get_genuine()
      local word = gcand.text
      local all_codes = env.quick_code_hint_reverse:lookup(word)
      if all_codes then
         local codes = {}
         for code in all_codes:gmatch("%S+") do
            if #code < 4 then
               table.insert(codes, code)
            end
         end
         if #codes > 0 then
            -- do not show two indicators
            if gcand.comment == indicator then
               gcand.comment = gcand.comment .. table.concat(codes, " ")
            else
               gcand.comment = gcand.comment .. indicator .. table.concat(codes, " ")
            end
         end
      end
      yield(cand)
   end
end

return Module
