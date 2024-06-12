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

   if extended or env.charset == nil then
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
   for i, char in moran.chars(text) do
      if not Top.CharInCharset(env, char) then
         return false
      end
   end
   return true
end

function Top.CharInCharset(env, char)
   if env.memo[char] ~= nil then
      return env.memo[char]
   end
   local res = not moran.unicode_code_point_is_chinese(utf8.codepoint(char)) or env.charset:lookup(char) ~= ""
   env.memo[char] = res
   return res
end

return Top
