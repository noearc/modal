local header = [[
#! /usr/bin/lua5.1
local modal = {}
local ut = {}
local pattern = {}
local params = {}
local types = {}
local theory = {}
local notation = {}
local a2s = {}
local factory = {}
local has_lpeg, lpeg = pcall(require, "lpeg")
lpeg = has_lpeg and lpeg or require("lulpeg"):register(not _ENV and _G)
local socket = require "socket"
local al = require "abletonlink"
local losc = require "losc"
local plugin = require "losc.plugins.udp-socket"
_G.struct = nil
local has_RL, RL = pcall(require, "readline")
local Clock
]]

-- path = "../src/core/"

files = {}

local fs = {
   dir = function(path)
      local listing = io.popen("ls " .. path):read "*all"
      local files = {}
      for file in listing:gmatch "[^\n]+" do
         files[file] = true
      end
      return next, files
   end,
   attributes = function()
      return {}
   end,
}

local function scandir(root)
   -- adapted from http://keplerproject.github.com/luafilesystem/examples.html
   local hndl
   for f in fs.dir(root) do
      if f:find "%.lua$" then
         hndl = f:gsub("%.lua$", ""):gsub("^[/\\]", ""):gsub("/", "."):gsub("\\", ".")
         files[hndl] = io.open(root .. f)
      end
   end
end

scandir "src/"

local function get_content(name, file)
   local contents = {}
   for i in file:lines() do
      if not i:find "require" and not i:match(("local %s = {}"):format(name)) then
         contents[#contents + 1] = i
      end
   end
   contents[#contents] = nil
   local str = table.concat(contents, "\n")
   return str
end

local function wrap(name, file)
   local format = [[
do
   %s
end
   ]]
   return format:format(get_content(name, file))
end

function load(name)
   header = header .. "\n" .. wrap(name, files[name])
end

-- BUG: parseChord??
load "ut"
load "types"
load "a2s"
load "notation"
load "theory"
load "clock"
load "factory"
load "pattern"
load "params"
header = header .. "\n" .. get_content("init", files["init"])
load "repl"
header = header .. "\n" .. "modal.ut = ut"
header = header .. "\n" .. "return modal"

print(header)

-- TODO: lfs
-- TODO: stylua the result if avaliable
