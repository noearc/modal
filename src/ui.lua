local pattern = require "pattern"
local stack, fastcat = pattern.stack, pattern.fastcat
local ut = require "ut"
local union = ut.union
local register = pattern.register

-- local P = require "modal.params"

local function juxBy(by, f, pat)
   by = by / 2
   local elem_or = function(dict, key, default)
      if dict[key] ~= nil then
         return dict[key]
      end
      return default
   end
   local left = pat:fmap(function(valmap)
      return union({ pan = elem_or(valmap, "pan", 0.5) - by }, valmap)
   end)
   local right = pat:fmap(function(valmap)
      return union({ pan = elem_or(valmap, "pan", 0.5) + by }, valmap)
   end)
   return stack(left, f(right))
end

local function striate(n, pat)
   local ranges = {}
   for i = 0, n - 1 do
      ranges[i] = { ["begin"] = i / n, ["end"] = (i + 1) / n }
   end
   local merge_sample = function(range)
      local f = function(v)
         return union(range, { sound = v.sound })
      end
      return pat:fmap(f)
   end
   local pats = {}
   for i = 1, n do
      pats[i] = merge_sample(ranges[i])
   end
   return fastcat(pats)
end

register(
   "juxBy :: Pattern Double -> (Pattern ValueMap -> Pattern ValueMap) -> Pattern ValueMap -> Pattern ValueMap",
   juxBy
)

-- return {
--    ["juxBy :: Pattern Double -> (Pattern ValueMap -> Pattern ValueMap) -> Pattern ValueMap -> Pattern ValueMap"] = juxBy,
--    -- {
--    --    -- "juxBy :: Pattern Double -> (Pattern ValueMap -> Pattern ValueMap) -> Pattern ValueMap -> Pattern ValueMap",
--    --    -- "juxBy :: Pattern Double -> f -> Pattern ValueMap -> Pattern ValueMap",
--    --    "",
--    --    juxBy,
--    -- },
--    -- {
--    --    -- "jux :: (Pattern ValueMap -> Pattern ValueMap) -> Pattern ValueMap -> Pattern ValueMap",
--    --    "",
--    --    function(f, pat)
--    --       return juxBy(0.5, f, pat)
--    --    end,
--    -- },
--    -- {
--    --    -- "striate :: Pattern Int -> ControlPattern -> ControlPattern",
--    --    "",
--    --    striate,
--    -- },
-- }

--
-- register("chop", function(n, pat)
--    local ranges
--    do
--       local _accum_0 = {}
--       local _len_0 = 1
--       for i = 0, n - 1 do
--          _accum_0[_len_0] = {
--             begin = i / n,
--             ["end"] = (i + 1) / n,
--          }
--          _len_0 = _len_0 + 1
--       end
--       ranges = _accum_0
--    end
--    local func
--    func = function(o)
--       local f
--       f = function(slice)
--          return union(slice, o)
--       end
--       return fastcat(map(f, ranges))
--    end
--    return pat:squeezeBind(func)
-- end)
--
-- register("slice", function(npat, ipat, opat)
--    return npat:innerBind(function(n)
--       return ipat:outerBind(function(i)
--          return opat:outerBind(function(o)
--             local begin
--             if type(n) == table then
--                begin = n[i]
--             else
--                begin = i / n
--             end
--             local _end
--             if type(n) == table then
--                _end = n[i + 1]
--             else
--                _end = (i + 1) / n
--             end
--             return pure(union(o, {
--                begin = begin,
--                ["end"] = _end,
--                _slices = n,
--             }))
--          end)
--       end)
--    end)
-- end)
--
-- register("splice", function(npat, ipat, opat)
--    local sliced = M.slice(npat, ipat, opat)
--    return sliced:withEvent(function(event)
--       return event:withValue(function(value)
--          local new_attri = {
--             speed = tofloat(tofrac(1) / tofrac(value._slices) / event.whole:duration()) * (value.speed or 1),
--             unit = "c",
--          }
--          return union(new_attri, value)
--       end)
--    end)
-- end)
--
-- register("_loopAt", function(factor, pat)
--    pat = pat .. P.speed(1 / factor) .. P.unit "c"
--    return slow(factor, pat)
-- end)
--
-- register("fit", function(pat)
--    return pat:withEvent(function(event)
--       return event:withValue(function(value)
--          return union(value, {
--             speed = tofrac(1) / event.whole:duration(),
--             unit = "c",
--          })
--       end)
--    end)
-- end)
--
-- register("legato", function(factor, pat)
--    factor = tofrac(factor)
--    return pat:withEventSpan(function(span)
--       return Span(span._begin, (span._begin + span:duration() * factor))
--    end)
-- end)

-- return M
