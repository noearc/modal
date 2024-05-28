local M = require("modal.utils")
local describe = require("busted").describe
local it = require("busted").it
local assert = require("busted").assert

describe("compare", function()
   return it("should deeply compare table values", function()
      local table1 = { first = "red fish", second = { low = 5 } }
      local table2 = { first = "red fish", second = { low = 5 } }
      local table3 = { first = "blue fish", second = { low = 5 } }
      local table4 = { first = "red fish", second = { low = 6 } }
      local table5 = {}
      local table6 = {}
      assert.is_true(M.compare(table1, table2))
      assert.is_true(M.compare(table5, table6))
      assert.is_false(M.compare(table1, table3))
      assert.is_False(M.compare(table1, table4))
      return assert.is_False(M.compare(table1, table5))
   end)
end)

describe("compare", function()
   it("should split list by index", function()
      local fst, lst = M.splitAt(3, { 1, 2, 3, 4, 5, 6 })
      assert.same({ 1, 2, 3 }, fst)
      assert.same({ 4, 5, 6 }, lst)
   end)
end)

describe("rotate", function()
   it("should split list by index", function()
      local res = M.rotate(3, { 1, 2, 3, 4, 5, 6 })
      assert.same({ 4, 5, 6, 1, 2, 3 }, res)
   end)
end)

describe("union", function()
   it("should union 2 map", function()
      local res = M.union({ s = "bd", room = 0.3 }, { delay = 0.3 })
      assert.same({ s = "bd", room = 0.3, delay = 0.3 }, res)
   end)
end)

describe("concat", function()
   it("should concat 2 lists", function()
      local res = M.concat({ "bd", 0.3 }, { 0.4 })
      assert.same({ "bd", 0.3, 0.4 }, res)
   end)
end)

describe("flatten", function()
   it("should flatten 2 lists", function()
      local res = M.flatten({ { { 1 }, 2, 3 }, 4 })
      assert.same({ 1, 2, 3, 4 }, res)
   end)
end)