local pattern = require "modal.pattern"
local ut = require "modal.utils"
local params = require "modal.params"
local pattern_factory = require "modal.pattern_factory"
local ui = require "modal.ui"
local P = require "modal.params"
local drawline = require "modal.drawline"
local lib = require "modal.lib"

local modal = {
   _VERSION = "modal dev-1",
   _URL = "https://github.com/noearc/modal",
   _DESCRIPTION = "A language for algorithmic pattern. Tidalcycles for moonscript",
}

modal.drawline = drawline
for name, func in pairs(pattern) do
   if name ~= "Pattern" then
      modal[name] = func
   end
end

for name, func in pairs(pattern_factory) do
   modal[name] = func
end

for name, pat in pairs(lib) do
   modal[name] = modal.reify(pat)
end

for name, func in pairs(ui) do
   modal[name] = func
end

for name, func in pairs(params) do
   modal[name] = func
end

local base = pattern.base
local Pattern = pattern.Pattern

for name, func in pairs(P) do
   modal[name] = func
   base[name] = function(self, ...)
      return self .. func(...)
   end
end

setmetatable(Pattern, {
   __index = base,
   __call = function(cls, ...)
      local _self_0 = setmetatable({}, base)
      cls.__init(_self_0, ...)
      return _self_0
   end,
})

base.__class = Pattern

if jit then
   local reify = modal.reify
   getmetatable("").__add = function(a, b)
      return reify(a) + reify(b)
   end

   getmetatable("").__mul = function(a, b)
      return reify(a) * reify(b)
   end

   getmetatable("").__div = function(a, b)
      return reify(a) / reify(b)
   end

   getmetatable("").__sub = function(a, b)
      return reify(a) - reify(b)
   end

   getmetatable("").__pow = function(a, b)
      return reify(a) ^ reify(b)
   end

   getmetatable("").__mod = function(a, b)
      return reify(a) % reify(b)
   end

   getmetatable("").__concat = function(a, b)
      return reify(a) .. reify(b)
   end

   getmetatable("").__index = function(a, b)
      return reify(a)[b]
   end
end

setmetatable(modal, {
   __call = function(t, override)
      for k, v in pairs(t) do
         if _G[k] ~= nil then
            local msg = "function " .. k .. " already exists in global scope."
            if override then
               _G[k] = v
               print("WARNING: " .. msg .. " Overwritten.")
            end
         else
            _G[k] = v
         end
      end
   end,
})

return modal
