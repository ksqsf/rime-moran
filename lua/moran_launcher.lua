--[[
   通過特定命令啓動外部程序。
   by ksqsf for Project Moran
   license: LGPLv3

   ※ 添加 lua_processor@launcher 到 engine/processors 中，置于默認 selector 之前
   ※ rime.lua 中添加 launch = require("moran/launcher")
--]]

local function generic_open(dest)
   if os.execute('start "" ' .. dest) then
      return true
   elseif os.execute('open ' .. dest) then
      return true
   elseif os.execute('xdg-open ' .. dest) then
      return true
   end
end

local function launch(key, env)
   local context = env.engine.context
   local kNoop = 2
   local input = context.input
   if (input == "ogrwh" or input == 'omorj') then
      generic_open("https://github.com/ksqsf/rime-moran")
      context:clear()
   end
   return kNoop
end

return launch
