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
   env.aux_table = nil
   collectgarbage()
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
   for cand in translation:iter() do
      if cand.type == "punct" then
         yield(cand)
      end

      local gcand = cand:get_genuine()
      local cand_text = cand.text
      local cand_len = utf8.len(cand_text)
      if cand_len ~= 1 then
         yield(cand)
         goto continue
      end

      local codes = env.aux_table[utf8.codepoint(cand_text)]
      if not codes then
         goto continue
      end
      local codes_str = table.concat(codes, " ")
      if codes and gcand.comment ~= codes_str then
         local comment = codes_str .. gcand.comment
         gcand.comment = comment
      end
      yield(cand)

      ::continue::
   end
end

return Module
