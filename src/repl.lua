local function repl()
   local socket = require "socket"
   local host = "localhost"
   local port = 9000
   local has_RL, RL = pcall(require, "readline")
   -- local modal = require "modal"
   -- local notation = require "modal.notation"
   local maxi = notation.maxi(modal)

   local keywords = {}
   for i, _ in pairs(modal) do
      keywords[#keywords + 1] = i
   end

   if has_RL then
      RL.set_complete_list(keywords)
      RL.set_options { keeplines = 1000, histfile = "~/.synopsis_history" }
      RL.set_readline_name "modal"
   end

   local ok, c = pcall(socket.connect, host, port)

   local optf = {
      ["?"] = function()
         return [[
:v  show _VERSION
:t  get type for lib func (TODO: for expression)
:q  quit repl ]]
      end,
      t = function(a)
         return tostring(modal.t[a])
      end,
      v = function()
         return modal._VERSION
      end,
      -- info = function(name)
      --    return dump(doc[name])
      -- end,
      q = function()
         if c then
            c:close()
         end
         os.exit()
      end,
   }

   -- TODO: see luaish, first run as lua with multiline? no ambiguiaty?>
   local eval = function(a)
      if a:sub(1, 1) == ":" then
         local name, param = a:match "(%a+)%s(%a*)"
         name = name and name or a:sub(2, #a)
         param = param and param or nil
         return optf[name](param)
      else
         local fn = modal.ut.dump(maxi(a))
         return fn
      end
   end

   local function readline(a)
      io.write(a)
      return io.read()
   end

   local read = has_RL and RL.readline or readline

   local line
   print "modal repl   :? for help"
   while true do
      line = read "> "
      if line == "exit" then
         if c then
            c:close()
         end
         break
      end

      if line ~= "" then
         local res = eval(line)
         if res then
            print(res)
         end
         if has_RL then
            RL.add_history(line)
            -- RL.save_history()
         end
         if c then
            c:send(line .. "\n")
         end
      end
   end

   c:close()
   os.exit()
end
modal.repl = repl

return repl
