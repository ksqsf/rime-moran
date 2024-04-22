local Module = {}

-- |Load zrmdb.txt bundled with the standard Moran distribution.
function Module.load_zrmdb()
   local aux_table = {}
   local pathsep = package.config:sub(1, 1)
   local path = rime_api.get_user_data_dir() .. pathsep .. "lua" .. pathsep .. "zrmdb.txt"
   for line in io.open(path):lines() do
      line = line:match("[^\r\n]+")
      local key, value = line:match("(.+) (.+)")
      if key and value then
         if aux_table[key] == nil then
            aux_table[key] = {}
         end
         table.insert(aux_table[key], value)
      end
   end
   return aux_table
end

-- |Returns a stateful iterator of Candidates.
--
-- 'transform' can be optionally provided to do post-process.
function Module.query_translation(translator, input, seg, transform)
   local xlation = translator:query(input, seg)
   if xlation == nil then
      return function() return nil end
   end
   local nxt, thisobj = xlation:iter()
   return function()
      local cand = nxt(thisobj)
      if cand == nil then
         return nil
      end
      if transform == nil then
         return cand
      else
         return transform(cand)
      end
   end
end

-- |Returns a list of Candidates.
function Module.drain_translation(translator, input, seg, transform)
   local results = {}
   for cand in Module.query_translation(translator, input, seg, transform) do
      table.insert(results, cand)
   end
   return results
end

function Module.unicode_code_point_is_chinese(codepoint)
   return (codepoint >= 0x4E00 and codepoint <= 0x9FFF)   -- basic
      or (codepoint >= 0x3400 and codepoint <= 0x4DBF)    -- ext a
      or (codepoint >= 0x20000 and codepoint <= 0x2A6DF)  -- ext b
      or (codepoint >= 0x2A700 and codepoint <= 0x2B73F)  -- ext c
      or (codepoint >= 0x2B740 and codepoint <= 0x2B81F)  -- ext d
      or (codepoint >= 0x2B820 and codepoint <= 0x2CEAF)  -- ext e
      or (codepoint >= 0x2CEB0 and codepoint <= 0x2EBE0)  -- ext f
      or (codepoint >= 0x30000 and codepoint <= 0x3134A)  -- ext g
      or (codepoint >= 0x31350 and codepoint <= 0x323AF)  -- ext h
      or (codepoint >= 0x2EBF0 and codepoint <= 0x2EE5F)  -- ext i
end

-- | Returns a stateful iterator of each char in word.
function Module.chars(word)
   local f, s, i = utf8.codes(word)
   return function()
      i, value = f(s, i)
      if i then
         return i, utf8.char(value)
      else
         return nil
      end
   end
end

return Module
