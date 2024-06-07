local moran = require("moran")
local Module = {}

function Module.init(env)
   env.enable_aux_hint = env.engine.schema.config:get_bool("moran/enable_aux_hint")
   if env.enable_aux_hint then
      env.aux_table = moran.load_zrmdb()
   else
      env.aux_table = nil
   end
end

function Module.fini(env)
   env.enable_aux_hint = false
   env.aux_hint_lookup = nil
end

function Module.func(translation, env)
   if (not env.enable_aux_hint) or env.aux_table == nil then
      for cand in translation:iter() do
         yield(cand)
      end
      return
   end

   -- Retrieve aux codes from aux_table
   -- We use the 'genuine' candidate (before simplifier) here
   for gcand in translation:iter() do
      local cand_text = gcand:get_genuine().text
      local cand_len = utf8.len(cand_text)
      if cand_len ~= 1 then
         yield(gcand)
         goto continue
      end

      local codes = env.aux_table[cand_text]
      if codes ~= nil then
         local comment = table.concat(codes, " ") .. gcand.comment
         local cand = ShadowCandidate(gcand, gcand.type, cand_text, comment)
         yield(cand)
      else
         yield(gcand)
      end

      ::continue::
   end
end

return Module
