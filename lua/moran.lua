---@dependency zrmdb.txt

local Module = {}

---Load zrmdb.txt bundled with the standard Moran distribution.
---@return table<integer,table<string>>
function Module.load_zrmdb()
   if Module.aux_table then
      return Module.aux_table
   end
   local aux_table = {}
   local pathsep = (package.config or '/'):sub(1, 1)
   local filename = 'zrmdb.txt'
   local path = rime_api.get_user_data_dir() .. pathsep .. "lua" .. pathsep .. filename
   local file = io.open(path) or io.open("/rime/lua/" .. filename)
   if not file then
      log.error("moran: failed to open aux file at path " .. path)
      return
   end
   for line in file:lines() do
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
   file:close()
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
---@return function():(number,string)?
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

---Get a stateful iterator of each unicode codepoint in a string
---@param word string
---@return function():number?
function Module.codepoints(word)
    local f, s, i = utf8.codes(word)
    local value = nil
    return function()
        i, value = f(s, i)
        if i then
            return i, value
        else
            return nil
        end
    end
end

---Return true if @str is purely Chinese.
---@param str str
---@return boolean
function Module.str_is_chinese(str)
   for _, cp in Module.codepoints(str) do
      if not Module.unicode_code_point_is_chinese(cp) then
         return false
      end
   end
   return true
end

---Take_while but with a limit.
---@generic T
---@param iter function():T?
---@param pred function(T):boolean
---@param limit integer
---@return table<T>
function Module.peekable_iter_take_while_upto(iter, limit, pred)
   local ret = {}
   for _ = 1, limit do
      if iter:peek() and pred(iter:peek()) then
         table.insert(ret, iter())
      else
         break
      end
   end
   return ret
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

---Yield all candidates in an iterator.
---@param iter function():Candidate a stateful iterator
function Module.yield_all(iter)
   for c in iter do
      yield(c)
   end
end

local Yielder = {}
Yielder.__index = Yielder

function Yielder.new(before_cb, after_cb)
   local instance = {
      stash = {}, -- map<Index, list<Candidate>>
      index = 0,
      before_cb = before_cb, -- function(number,Cand): number?, 在準備 yield 前讓用戶檢查一次，如果不應該此時 yield，則返回一個 defer 數字
      after_cb = after_cb  -- 真正 yield 後通知用戶
   }
   setmetatable(instance, Yielder)
   return instance
end

---原始輸出函數
---@param value Candidate
---@return table 新得到的應該輸出的 deferred value
function Yielder:__yield(value)
   local last_minute_defer = self.before_cb and self.before_cb(self.index, value)
   if last_minute_defer == nil or last_minute_defer <= 0 then
      yield(value)
      if self.after_cb then
         self.after_cb(self.index, value)
      end
      self.index = self.index + 1
      local retval = self.stash[self.index]
      self.stash[self.index] = nil
      return retval
   else
      self:yield_defer(value, last_minute_defer)
   end
end

-- 在翻譯開始時重置內部狀態。
function Yielder:reset()
   self.stash = {}
   self.index = 0
end

---輸出 value，同時可能會輸出之前被延遲的value，導致輸出不止一個結果。
---@param value Candidate
function Yielder:yield(value)
   local worklist = {value}
   local i = 1
   while i <= #worklist do
      local new_yields = self:__yield(worklist[i])
      if new_yields then
         for j = 1, #new_yields do
            worklist[#worklist + 1] = new_yields[j]
         end
      end
      i = i + 1
   end
end

function Yielder:yield_defer(value, delta)
   if delta <= 0 then
      self:yield(value)
   else
      local index = self.index + delta
      if self.stash[index] == nil then
         self.stash[index] = { value }
      else
         table.insert(self.stash[index], value)
      end
   end
end

function Yielder:yield_all(iter)
   for c in iter do
      self:yield(c)
   end
end

--- 依次輸出所有被延遲的value，並清空它們。
function Yielder:clear()
   for _, deferred_list in pairs(self.stash) do
      for _, elem in pairs(deferred_list) do
         yield(elem)
      end
   end
   self.stash = {}
end

Module.Yielder = Yielder

---Make a function-based stateful iterator peekable.
---Returns a callable object that has two methods 'peek' and 'next'.
---Calling the object is equivalent to call 'next' on it.
function Module.make_peekable(f)
   local it = {
      peeked = false,
      peek_val = nil,
   }
   function it:peek()
      if self.peeked then
         return self.peek_val
      else
         self.peek_val = f()
         self.peeked = true
         return self.peek_val
      end
   end

   function it:next()
      return it()
   end

   local mt = {
      __call = function(self)
         if self.peeked then
            self.peeked = false
            local ret = self.peek_val
            self.peek_val = nil
            return ret
         else
            return f()
         end
      end
   }
   setmetatable(it, mt)
   return it
end

---Get a bool-typed config value with default value.
---Due to nil and false both being falsy, 'or' shouldn't be used.
function Module.get_config_bool(env, key, deflt)
   local val = env.engine.schema.config:get_bool(key)
   if val == nil then
      return deflt
   end
   return val
end

function Module.map(tbl, f)
    local ret = {}
    for k, v in pairs(tbl) do
        ret[k] = f(v)
    end
    return ret
end

function Module.rstrip(s, suffix)
   if s:sub(-#suffix) == suffix then
      return s:sub(1, -#suffix - 1)
   else
      return s
   end
end

return Module
