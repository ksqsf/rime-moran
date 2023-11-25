local Module = {}

function Module.init(env)
   env.enable_aux_hint = env.engine.schema.config:get_bool("moran/enable_aux_hint")
   if env.enable_aux_hint then
      env.aux_hint_reverse = ReverseLookup('moran.chars')
   else
      env.aux_hint_reverse = nil
   end
end

function Module.fini(env)
   env.enable_aux_hint = false
   env.aux_hint_lookup = nil
end

function Module.func(translation, env)
   if (not env.enable_aux_hint) or env.aux_hint_reverse == nil then
      for cand in translation:iter() do
         yield(cand)
      end
      return
   end

   -- Retrieve aux codes from moran.chars dictionary
   for cand in translation:iter() do
      local cand_len = utf8.len(cand.text)
      if cand_len ~= 1 then
         yield(cand)
         goto continue
      end

      local codes = env.aux_hint_reverse:lookup(cand.text)
      local vis = {}
      local aux_codes = {}
      for aux_code in codes:gmatch(";([a-z][a-z])") do
         if not vis[aux_code] then
            table.insert(aux_codes, aux_code)
            vis[aux_code] = true
         end
      end

      cand:get_genuine().comment = table.concat(aux_codes, " ")
      yield(cand)

      ::continue::
   end
end

return Module
