local moran = require("moran")
local Top = {}

function Top.init(env)
   env.charset = ReverseLookup("moran_charset")
   env.memo = {}
end

function Top.fini(env)
   env.charset = nil
   env.memo = nil
   collectgarbage()
end

function Top.func(t_input, env)
   local extended = env.engine.context:get_option("extended_charset")

   if extended or env.charset == nil or Top.IsReverseLookup(env) then
      for cand in t_input:iter() do
         yield(cand)
      end
   else
      for cand in t_input:iter() do
         if Top.InCharset(env, cand.text) then
            --log.error("passed " .. cand.text)
            yield(cand)
         else
            --log.error("filtered " .. cand.text)
         end
      end
   end
end

-- For each Chinese char in text, if it is not in charset, return false.
function Top.InCharset(env, text)
   for i, codepoint in moran.codepoints(text) do
      if not Top.CodepointInCharset(env, codepoint) then
         return false
      end
   end
   return true
end

function Top.CodepointInCharset(env, codepoint)
   if env.memo[codepoint] ~= nil then
      return env.memo[codepoint]
   end
   local res = not moran.unicode_code_point_is_chinese(codepoint) or env.charset:lookup(utf8.char(codepoint)) ~= ""
   env.memo[codepoint] = res
   return res
end

function Top.IsReverseLookup(env)
   local seg = env.engine.context.composition:back()
   if not seg then
      return false
   end
   return seg:has_tag("reverse_tiger")
      or seg:has_tag("reverse_zrlf")
      or seg:has_tag("reverse_cangjie5")
      or seg:has_tag("reverse_stroke")
      or seg:has_tag("reverse_tick")

   -- 所有反查都不過濾：
   -- for tag, _ in pairs(seg.tags) do
   --    if tag:match("^reverse_") then
   --       return true
   --    end
   -- end
   -- return false
end

return Top
