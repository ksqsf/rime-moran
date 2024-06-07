local Module = {}

---Load zrmdb.txt bundled with the standard Moran distribution.
---@return table<integer,table<string>>
function Module.load_zrmdb()
   if Module.aux_table then
      return Module.aux_table
   end
   local aux_table = {}
   local pathsep = (package.config or '/'):sub(1, 1)
   local path = rime_api.get_user_data_dir() .. pathsep .. "lua" .. pathsep .. "zrmdb.txt"
   for line in io.open(path):lines() do
      line = line:match("[^\r\n]+")
      local key, value = line:match("(.+) (.+)")
      key = utf8.codepoint(key)
      if key and value then
         if aux_table[key] == nil then
            aux_table[key] = {}
         end
         table.insert(aux_table[key], value)
      end
   end
   Module.aux_table = aux_table
   return Module.aux_table
end

function Module.iter_translation(xlation)
   local nxt, thisobj = xlation:iter()
   return function()
      local cand = nxt(thisobj)
      if cand == nil then
         return nil
      end
      return cand
   end
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

---Check if a Unicode codepoint is a Chinese character. Up to Unicode 15.1.
---@param codepoint integer
---@return boolean
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

---Get a stateful iterator of each unicode character in a string.
---@param word string
---@return function():string?
function Module.chars(word)
   local f, s, i = utf8.codes(word)
   local value = nil
   return function()
      i, value = f(s, i)
      if i then
         return i, utf8.char(value)
      else
         return nil
      end
   end
end

---Take elements from a stateful iterator, until the predicate returns true, or reaches the limit.
---@generic T
---@param iter function():T?
---@param pred function(T):boolean
---@param limit integer
---@return table<T>,T? 
function Module.iter_take_until_upto(iter, pred, limit)
   local stash = {}
   for _ in 1, limit do
      local cur = iter()
      if cur == nil or pred(cur) then
         return stash, cur
      else
         table.insert(stash, cur)
      end
   end
   return stash, nil
end

---Create a singleton stateful iterator.
---@generic T
---@param x T
---@return function():T the stateful singleton iterator
function Module.iter_singleton(x)
   local taken = false
   return function()
      if not taken then
         taken = true
         return x
      else
         return nil
      end
   end
end

---Compose two stateful iterators. The first iterator is not assumed to be always giving nil after the final element.
---@generic T
---@param it1 function():T? the first stateful iterator
---@param it2 function():T? the second stateful iterator
---@return function():T? the composition
function Module.iter_compose(it1, it2)
   local it1_done = false
   return function()
      if it1_done then
         return it2()
      else
         local x = it1()
         if x ~= nil then
            return x
         else
            it1_done = true
            return it2()
         end
      end
   end
end

---Map over each element of an iterator, which is not assumed to always give nil after completion.
---@generic T
---@param it function():T?
---@param f function(T):T
---@return function():T? a new iterator with each element mapped
function Module.iter_map(it, f)
   local done = false
   return function()
      if done then
         return nil
      end
      local cur = it()
      if cur then
         return f(cur)
      else
         done = true
         return nil
      end
   end
end

---Create a stateful iterator for all values in a table.
---@generic K
---@generic V
---@param tbl table<K,V>
---@return function():V the stateful iterator
function Module.iter_table_values(tbl)
    local cur = next(tbl, nil)
    return function()
        if cur == nil then
            return nil
        else
            local ret = cur
            cur = next(tbl, cur)
            return ret
        end
    end
end

---Peek an element from an iterator
---@generic T
---@param iter function():T?
---@return T?,function():T? the (possibly) first element in iter, and a new iterator that returns the same sequence as if iter was never peeked
function Module.iter_peek(iter)
    local el = iter()
    local done = false
    return el, function()
        if not done then
            done = true
            return el
        else
            return iter()
        end
    end
end

---Yield all candidates in an iterator.
---@param iter function():Candidate a stateful iterator
function Module.yield_all(iter)
    for c in iter do
        yield(c)
    end
end

return Module
