local Clock = require "modal.clock"
local Stream = require "modal.stream"
local M = require "modal.pattern_factory"
local pure = require("modal.pattern").pure
local describe = require("busted").describe
local it = require("busted").it
local assert = require("busted").assert

local DefaultClock = M.DefaultClock
local hush = M.hush
local p = M.p

describe("p", function()
   it("register stream of patterns to clock", function()
      local pat = p(pure "helloooo", 1)
      local mystream = Stream(DefaultClock.sendf)
      mystream.pattern = pure "helloooo"
      assert.same(mystream, DefaultClock.subscribers[1])
      assert.same(pure "helloooo"(0, 1), DefaultClock.subscribers[1].pattern(0, 1))
   end)
   it("register new pattern to existing stream", function()
      local pat = p(pure "new hellooo", 1)
      assert.same(pure "new hellooo"(0, 1), DefaultClock.subscribers[1].pattern(0, 1))
   end)
end)

describe("hush", function()
   it("clear all streams", function()
      hush()
      assert.same({}, DefaultClock.subscribers)
   end)
end)