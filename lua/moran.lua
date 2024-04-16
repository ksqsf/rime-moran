local Module = {}

-- |Load zrmdb.txt bundled with the standard Moran distribution.
function Module.load_zrmdb()
   local aux_table = {}
   local path = rime_api.get_user_data_dir() .. "/lua/zrmdb.txt"
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

return Module
