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

return Module
