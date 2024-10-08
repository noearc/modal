local types = require "types"
local ut = require "ut"
local theory = require "theory"
local notation = require "notation"
local pattern = {}

local bjork, getScale = theory.bjork, theory.getScale
local Event, Span, Time, TDef, ValueMap = types.Event, types.Span, types.Time, types.TDef, types.ValueMap

local unpack = unpack or rawget(table, "unpack")
local pairs = pairs
local ipairs = ipairs
local setmetatable = setmetatable
local tconcat = table.concat
local tremove = table.remove
local str_format = string.format
local sin = math.sin
local min = math.min
local max = math.max
local pi = math.pi
local floor = math.floor
local is_array = ut.is_array
local reduce = ut.reduce
local map = ut.map
local id = ut.id
local filter = ut.filter
local dump = ut.dump
local curry = ut.curry
local union = ut.union
local concat = ut.concat
local flip = ut.flip
local method_wrap = ut.method_wrap
local get_args = ut.get_args
local timeToRand = ut.timeToRand
local memoize = ut.memoize
local T = ut.T

local fast, pure, fastcat, slowcat, stack, silence, focus, range, rev, compress

local TYPES = {}
local op = {}

setmetatable(pattern, { __index = _G }) -- give mini access to global vars

local eval = notation.mini(pattern)
local reify = memoize(function(thing)
   local t = T(thing)
   if t == "string" then
      local res = eval(thing)
      return res and res or silence
   elseif t == "table" then
      if is_array(thing) then
         return fastcat(thing)
      else
         return pure(ValueMap(thing))
      end
   elseif t == "pattern" then
      return thing
   else
      return pure(thing)
   end
end)
pattern.reify = reify

local mt = { __class = "pattern" }

function mt:len()
   return #(self(0, 1))
end

function mt:__call(b, e, controls)
   local span = Span(b, e)
   span.controls = controls
   return setmetatable(self.query(span), {
      __tostring = function(t)
         return dump(t)
      end,
   })
end

function mt:__tostring()
   return dump(self(0, 1))
end

function mt:show()
   return tostring(self)
end

function mt:__eq(other)
   return self:__tostring() == other:__tostring()
end

function mt:__concat(other)
   return op["|>"](self, other)
end

function mt:__add(other)
   return op["|+"](self, other)
end

function mt:__sub(other)
   return op["|-"](self, other)
end

function mt:__mul(other)
   return op["|*"](self, other)
end

function mt:__div(other)
   return op["|/"](self, other)
end

function mt:__mod(other)
   return op["|%"](self, other)
end

function mt:__pow(other)
   return op["|^"](self, other)
end

mt.__index = mt

---@class Pattern
local function Pattern(query)
   query = query or function()
      return {}
   end
   return setmetatable({ query = query }, mt)
end
pattern.Pattern = Pattern

local function filterEvents(pat, func)
   local query = function(span)
      local events = pat.query(span)
      return filter(func, events)
   end
   return Pattern(query)
end
mt.filterEvents = filterEvents

local function filterValues(pat, condf)
   local query = function(span)
      local events = pat.query(span)
      local f = function(event)
         return condf(event.value)
      end
      return filter(f, events)
   end
   return Pattern(query)
end
mt.filterValues = filterValues

local function removeNils(pat)
   return filterValues(pat, function(v)
      return v ~= nil
   end)
end
mt.removeNils = removeNils

local function splitQueries(pat)
   local query = function(span)
      local cycles = span:spanCycles()
      local res = {}
      for i = 1, #cycles do
         local evs = pat.query(cycles[i])
         for j = 1, #evs do
            res[#res + 1] = evs[j]
         end
      end
      return res
   end
   return Pattern(query)
end
mt.splitQueries = splitQueries

local function withValue(pat, f)
   local query = function(span)
      local events = pat.query(span)
      for i = 1, #events do
         events[i] = events[i]:withValue(f)
      end
      return events
   end
   return Pattern(query)
end
mt.withValue = withValue

local fmap = withValue
mt.fmap = fmap

local function withQuerySpan(pat, f)
   local query = function(span)
      return pat.query(f(span))
   end
   return Pattern(query)
end
mt.withQuerySpan = withQuerySpan

local function withQueryTime(pat, f)
   return withQuerySpan(pat, function(span)
      return span:withTime(f)
   end)
end
mt.withQueryTime = withQueryTime

local function withEvents(pat, f)
   return Pattern(function(span)
      return f(pat.query(span))
   end)
end
mt.withEvents = withEvents

local function withEvent(pat, f)
   return withEvents(pat, function(events)
      for i = 1, #events do
         events[i] = f(events[i])
      end
      return events
   end)
end
mt.withEvent = withEvent

local function withEventSpan(pat, f)
   local query = function(span)
      local events = pat.query(span)
      for i = 1, #events do
         events[i] = events[i]:withSpan(f)
      end
      return events
   end
   return Pattern(query)
end
mt.withEventSpan = withEventSpan

local function withEventTime(pat, f)
   local query = function(span)
      local events = pat.query(span)
      local time_func = function(sp)
         return sp:withTime(f)
      end
      local event_func = function(event)
         return event:withSpan(time_func)
      end
      for i = 1, #events do
         events[i] = event_func(events[i])
      end
      return events
   end
   return Pattern(query)
end
mt.withEventTime = withEventTime

local function withTime(pat, qf, ef)
   local query = withQueryTime(pat, qf)
   return withEventTime(query, ef)
end
mt.withTime = withTime

local function onsetsOnly(pat)
   return filterEvents(pat, function(event)
      return event:hasOnset()
   end)
end
mt.onsetsOnly = onsetsOnly

local function discreteOnly(pat)
   return filterEvents(pat, function(event)
      return event.whole
   end)
end
mt.discreteOnly = discreteOnly

local function appWhole(pat, whole_func, pat_val)
   local query = function(span)
      local event_funcs = pat.query(span)
      local event_vals = pat_val.query(span)
      local apply = function(event_func, event_val)
         local new_part = event_func.part:sect(event_val.part)
         if not new_part then
            return
         end
         return Event(whole_func(event_func.whole, event_val.whole), new_part, event_func.value(event_val.value))
      end
      local events = {}
      for _, ef in pairs(event_funcs) do
         for _, ev in ipairs(event_vals) do
            events[#events + 1] = apply(ef, ev)
         end
      end
      return events
   end
   return Pattern(query)
end
mt.appWhole = appWhole

-- Tidal's <*>
local function appBoth(pat, pat_val)
   local whole_func = function(span_a, span_b)
      if not span_a or not span_b then
         return
      end
      return span_a:sect(span_b)
   end
   return appWhole(pat, whole_func, pat_val)
end
mt.appBoth = appBoth

-- Tidal's <*
local function appLeft(pat, pat_val)
   local query = function(span)
      local events = {}
      local event_funcs = pat.query(span)
      for _, event_func in ipairs(event_funcs) do
         local whole = event_func:wholeOrPart()
         local event_vals = pat_val.query(whole)
         for _, event_val in ipairs(event_vals) do
            local new_whole = event_func.whole
            local new_part = event_func.part:sect(event_val.part)
            if new_part then
               local new_value = event_func.value(event_val.value)
               events[#events + 1] = Event(new_whole, new_part, new_value)
            end
         end
      end
      return events
   end
   return Pattern(query)
end
mt.appLeft = appLeft

-- Tidal's *>
local function appRight(pat, pat_val)
   local query = function(span)
      local events = {}
      local event_vals = pat_val.query(span)
      for _, event_val in ipairs(event_vals) do
         local whole = event_val:wholeOrPart()
         local event_funcs = pat.query(whole)
         for _, event_func in ipairs(event_funcs) do
            local new_whole = event_val.whole
            local new_part = event_func.part:sect(event_val.part)
            if new_part then
               local new_value = event_func.value(event_val.value)
               events[#events + 1] = Event(new_whole, new_part, new_value)
            end
         end
      end
      return events
   end
   return Pattern(query)
end
mt.appRight = appRight

local function bindWhole(pat, choose_whole, func)
   local query = function(span)
      local events = pat.query(span)
      local res = {}
      for _, a in ipairs(events) do
         local evs = func(a.value).query(a.part)
         for _, b in ipairs(evs) do
            res[#res + 1] = Event(choose_whole(a.whole, b.whole), b.part, b.value)
         end
      end
      return res
   end
   return Pattern(query)
end

local function bind(pat, func)
   local whole_func = function(a, b)
      if a == nil or b == nil then
         return nil
      end
      return a:sect(b)
   end
   return bindWhole(pat, whole_func, func)
end

local function join(pat)
   return bind(pat, id)
end

local function outerBind(pat, func)
   return bindWhole(pat, function(a, _)
      return a
   end, func)
end

local function innerBind(pat, func)
   return bindWhole(pat, function(_, b)
      return b
   end, func)
end

local function outerJoin(pat)
   return outerBind(pat, id)
end

local function innerJoin(pat)
   return innerBind(pat, id)
end

local function squeezeJoin(pat)
   local query = function(span)
      local events = discreteOnly(pat).query(span)
      local flatEvent = function(outerEvent)
         local n_span = outerEvent:wholeOrPart()
         local innerPat = pattern.focus(n_span.start, n_span.stop, outerEvent.value)
         local innerEvents = innerPat.query(outerEvent.part)
         local munge = function(outer, inner)
            local whole = nil
            if inner.whole and outer.whole then
               whole = inner.whole:sect(outer.whole)
               if not whole then
                  return nil
               end
            end
            local part = inner.part:sect(outer.part)
            if not part then
               return nil
            end
            return Event(whole, part, inner.value)
         end
         for i = 1, #innerEvents do
            innerEvents[i] = munge(outerEvent, innerEvents[i])
         end
         return innerEvents
      end
      local result = {}
      for i = 1, #events do
         local evs = flatEvent(events[i])
         for j = 1, #evs do
            result[#result + 1] = evs[j]
         end
      end
      return filter(function(x)
         return x
      end, result)
   end
   return Pattern(query)
end

local function squeezeBind(pat, func)
   return squeezeJoin(fmap(pat, func))
end

local _op = {}
function _op.In(f)
   return function(a, b)
      a, b = fmap(reify(a), curry(f, 2)), reify(b)
      return appLeft(a, b):removeNils()
   end
end

function _op.Out(f)
   return function(a, b)
      a, b = fmap(reify(a), curry(f, 2)), reify(b)
      return appRight(a, b):removeNils()
   end
end

function _op.Mix(f)
   return function(a, b)
      a, b = fmap(reify(a), curry(f, 2)), reify(b)
      return appBoth(a, b):removeNils()
   end
end

function _op.Squeeze(f)
   return function(a, b)
      return squeezeJoin(fmap(reify(a), function(c)
         return fmap(reify(b), function(d)
            return f(c, d)
         end)
      end)):removeNils()
   end
end

function _op.SqueezeOut(f)
   return function(a, b)
      return squeezeJoin(fmap(reify(b), function(c)
         return fmap(reify(a), function(d)
            return f(d, c)
         end)
      end)):removeNils()
   end
end

-- stylua: ignore start
local ops = {
   set = function(_, b) return b end,
   add = function(a, b) return a + b end,
   sub = function(a, b) return a - b end,
   mul = function(a, b) return a * b end,
   div = function(a, b) return a / b end,
   mod = function(a, b) return a % b end,
   pow = function(a, b) return a ^ b end,
   concat = function(a, b) return a .. b end,
   keepif = function(a, b)
      if b == 0 then b = false end
      return b and a or nil
   end,
   uni = function(a, b) return union(a, b) end,
   funi = function(a, b) return flip(union)(a, b) end,
}
-- stylua: ignore end

-- local hows = { "In", "Out", "Mix", "Squeeze", "Squeezeout", "Trig", "Trigzero" }
local hows = { "In", "Out", "Mix", "Squeeze", "SqueezeOut" }
local op_set = {
   add = "+",
   sub = "-",
   mul = "*",
   div = "/",
   mod = "%",
   pow = "^",
   keepif = "?",
   concat = "..", -- ?
   uni = ">",
   funi = "<",
}

local how_format = {
   In = "|%s",
   Out = "%s|",
   Mix = "|%s|",
   Squeeze = "||%s",
   SqueezeOut = "%s||",
}

for k, f in pairs(ops) do
   op[k] = {}
   for _, v in ipairs(hows) do
      op[k][v] = _op[v](f)
      if op_set[k] and how_format[v] then
         local symb = str_format(how_format[v], op_set[k])
         op[symb] = _op[v](f)
      end
   end
end
op["#"] = op["|>"]

silence = Pattern()
pattern.silence = silence

function pure(value)
   return Pattern(function(span)
      local cycles = span:spanCycles()
      for i, v in ipairs(cycles) do
         cycles[i] = Event(v.start:wholeCycle(), v, value)
      end
      return cycles
   end)
end

pattern.pure = pure

local function purify(value)
   if T(value) == "pattern" then
      return value
   else
      return pure(value)
   end
end

moon = require "moon"

local function patternify(arity, func)
   return function(...)
      local pats = { ... }
      local pat = pats[#pats]
      if arity == 1 then
         return func(pat)
      end
      local left = tremove(pats, 1)
      -- print(left)
      -- for i, v in ipairs(pats) do
      --    print(v)
      -- end
      -- print(pats[1])
      -- local mapFn = function(...)
      --    local args = { ... }
      --    args[#args + 1] = pat
      --    return func(unpack(args))
      -- end
      func = curry(func, arity)
      -- return func(left, unpack(pats))
      return func(...)

      -- return innerJoin(reduce(appLeft, fmap(left, func), pats))
   end
end

local function patternify(arity, func)
   return function(...)
      local pats = { ... }
      local pat = tremove(pats, #pats)
      if arity == 1 then
         return func(pat)
      end
      local left = tremove(pats, 1)
      local mapFn = function(...)
         local args = { ... }
         args[#args + 1] = pat
         return func(unpack(args))
      end
      mapFn = curry(mapFn, arity - 1)
      return innerJoin(reduce(appLeft, fmap(left, mapFn), pats))
   end
end

local function type_wrap(f, name)
   local sig = TYPES[name]
   return function(...)
      local args = { ... }
      for i, v in ipairs(args) do
         local t = sig[i]
         local tc, tvar, istable = t.constructor, t[1], t.istable
         if istable then
            for j, vv in ipairs(v) do
               if tc then
                  if tc == "Pattern" then
                     v[j] = purify(vv) -- for fastcat and slowcat ...
                  end
               end
            end
         else
            if tvar == "Time" then
               v = Time(v)
            end
            if tc then
               -- if tc == "Pattern" and tvar == "f" and type(v) == "string" then
               --    v = reify("(" .. v .. ")")
               if tc == "Pattern" then
                  v = reify(v)
               end
            end
            args[i] = v
         end
      end
      return f(unpack(args))
   end
end

local function register(type_sig, f, nify)
   local tdef, name = TDef(type_sig)
   if T(nify) == "nil" then
      nify = true
   end
   local arg_names = get_args(f)
   local arity = #arg_names
   for i, v in pairs(arg_names) do
      tdef[i].name = v
   end
   if nify then
      TYPES[name] = tdef
      local f_p = patternify(arity, f)
      local f_p_t = type_wrap(f_p, name)
      local f_c_p_t = curry(f_p_t, arity)
      pattern[name] = f_c_p_t
      rawset(mt, name, method_wrap(f_p_t))
   else
      TYPES[name] = tdef
      local f_t = type_wrap(f, name)
      local f_t_c = curry(f_t, arity)
      pattern[name] = f_t_c
      rawset(mt, name, method_wrap(f_t))
   end
end
pattern.register = register

local function overlay(a, b)
   local query = function(st)
      return concat(a.query(st), b.query(st))
   end
   return Pattern(query)
end
register("overlay :: Pattern a -> Pattern a -> Pattern a", overlay, false)

function stack(pats)
   return reduce(overlay, silence, pats)
end

register("stack :: [Pattern a] -> Pattern a", stack, false)

function pattern.polymeter(pats, steps)
   steps = steps or pats[1]:len()
   for i, pat in ipairs(pats) do
      pat = reify(pat)
      pats[i] = pattern.fast(steps / pat:len(), pat)
   end
   return stack(pats)
end

pattern.pm = pattern.polymeter
-- register("polymeter :: Pattern Int -> [Pattern a] -> Pattern a", polymeter, false)

function slowcat(pats)
   local query = function(span)
      local cyc = span.start:sam():asFloat()
      local n = #pats
      local i = cyc % n
      local pat = pats[i + 1]
      if not pat then
         return {}
      end
      local offset = cyc - (cyc - i) / n
      return withEventTime(pat, function(t)
         return t + offset
      end).query(span:withTime(function(t)
         return t - offset
      end))
   end
   return splitQueries(Pattern(query))
end

register("slowcat :: [Pattern a] -> Pattern a", slowcat, false)

function fastcat(pats)
   return pattern.fast(#pats, pattern.slowcat(pats))
end

register("fastcat :: [Pattern a] -> Pattern a", fastcat, false)

function mt:slowcat(...)
   local pats = { self }
   for i = 1, select("#", ...) do
      pats[i + 1] = select(i, ...)
   end
   return slowcat(pats)
end

function mt:fastcat(...)
   local pats = { self }
   for i = 1, select("#", ...) do
      pats[i + 1] = select(i, ...)
   end
   return fastcat(pats)
end

function mt:stack(...)
   local pats = { self }
   for i = 1, select("#", ...) do
      pats[i + 1] = select(i, ...)
   end
   return stack(pats)
end

local function timecat(tups)
   local total = 0
   for i, v in ipairs(tups) do
      if i % 2 == 1 then
         total = total + v
      end
   end
   local accum = Time(0)
   local pats = {}
   local time, pat, b, e
   for i = 1, #tups, 2 do
      time, pat = tups[i], reify(tups[i + 1])
      b, e = accum / total, (accum + time) / total
      pats[#pats + 1] = compress(b, e, pat)
      accum = accum + time
   end
   return stack(pats)
end
pattern.timecat = timecat

local function arrange(tups)
   local total = 0
   for i, v in ipairs(tups) do
      if i % 2 == 1 then
         total = total + v
      end
   end
   local cycles, pat
   for i = 1, #tups, 2 do
      cycles, pat = tups[i], reify(tups[i + 1])
      tups[i + 1] = pattern.fast(cycles, pat)
   end
   return slow(total, timecat(tups))
end
pattern.arrange = arrange

local function superimpose(f, pat)
   return overlay(pat, f(pat))
end
register("superimpose :: (Pattern a -> Pattern a) -> Pattern a -> Pattern a", superimpose, false)

local function layer(tf, pat)
   for i, f in ipairs(tf) do
      tf[i] = f(pat)
   end
   return stack(tf)
end
register("layer :: [(Pattern a -> Pattern b)] -> Pattern a -> Pattern b", layer, false) -- a little ugly lol layer

function fast(factor, pat)
   if factor:eq(0) then
      return silence
   elseif factor:lt(0) then
      return rev(fast(-factor, pat))
   else
      return withTime(pat, function(t)
         return t * factor
      end, function(t)
         return t / factor
      end)
   end
end

register("fast :: Pattern Time -> Pattern a -> Pattern a", fast)

local function slow(factor, pat)
   if factor:eq(0) then
      return silence
   else
      return fast(factor:reverse(), pat)
   end
end
register("slow :: Pattern Time -> Pattern a -> Pattern a", slow)

-- rotL
local function early(offset, pat)
   return withTime(pat, function(t)
      return t + offset
   end, function(t)
      return t - offset
   end)
end
register("early :: Time -> Pattern a -> Pattern a", early, false) -- HACK: why not patternify TIME??

-- rotR
local function late(offset, pat)
   return early(-offset, pat)
end
register("late :: Time -> Pattern a -> Pattern a", late, false)

local function inside(np, f, pat)
   local function _inside(n)
      return fast(n, f(slow(n, pat)))
   end
   return innerJoin(fmap(np, _inside))
end
register("inside :: Pattern Time -> (Pattern b -> Pattern a) -> Pattern b -> Pattern a", inside, false)

local function outside(factor, f, pat)
   return inside(1 / factor, f, pat)
end
register("outside :: Pattern Time -> (Pattern b -> Pattern a) -> Pattern b -> Pattern a", outside, false)

local function ply(n, pat)
   pat = fmap(pat, function(x)
      return fast(n, pure(x))
   end)
   return squeezeJoin(pat)
end
register("ply :: Pattern Time -> Pattern a -> Pattern a", ply)

local function fastgap(factor, pat)
   if factor:lte(0) then
      return silence
   end
   factor = factor:max(1)
   local mungeQuery = function(t)
      return t:sam() + ((t - t:sam()) * factor):min(1)
   end
   local eventSpanFunc = function(span)
      local b = span.start:sam() + (span.start - span.start:sam()) / factor
      local e = span.start:sam() + (span.stop - span.start:sam()) / factor
      return Span(b, e)
   end
   local query = function(span)
      local new_span = Span(mungeQuery(span.start), mungeQuery(span.stop))
      if new_span.start == new_span.start:nextSam() then
         return {}
      end
      local events = pat.query(new_span)
      for i = 1, #events do
         events[i] = events[i]:withSpan(eventSpanFunc)
      end
      return events
   end
   return splitQueries(Pattern(query))
end
register("fastgap :: Pattern Time -> Pattern a -> Pattern a", fastgap)

function compress(b, e, pat)
   if b:gt(e) or e:gt(1) or b:gt(1) or b:lt(0) or e:lt(0) then
      return silence
   end
   local fasted = fastgap((e - b):reverse(), pat)
   return late(b, fasted)
end

register("compress :: Time -> Time -> Pattern a -> Pattern a", compress, false)

function focus(b, e, pat)
   local fasted = fast((e - b):reverse(), pat)
   return late(b:cyclePos(), fasted)
end

register("focus :: Time -> Time -> Pattern a -> Pattern a", focus, false)

local function zoom(s, e, pat)
   local dur = e - s
   local qf = function(span)
      return span:withCycle(function(t)
         return t * dur + s
      end)
   end
   local ef = function(span)
      return span:withCycle(function(t)
         return (t - s) / dur
      end)
   end
   return splitQueries(withEventSpan(withQuerySpan(pat, qf), ef))
end
register("zoom :: Time -> Time -> Pattern a -> Pattern a", zoom, false)

local _run = function(n)
   local list = {}
   for i = 1, n do
      list[i] = i - 1
   end
   return fastcat(list)
end

local function run(n)
   return join(fmap(n, _run))
end
register("run :: Pattern Int -> Pattern Int", run, false)

local _scan = function(n)
   local res = {}
   for i = 1, n do
      res[i] = run(pure(i))
   end
   return slowcat(res)
end

local function scan(n)
   return join(fmap(n, _scan))
end
register("scan :: Pattern Int -> Pattern Int", scan, false)

local function segment(n, pat)
   return appLeft(fast(n, pure(id)), pat)
end
register("segment :: Pattern Time -> Pattern a -> Pattern a", segment)

function range(mi, ma, pat)
   return pat * (ma - mi) + mi
end

register("range :: Pattern number -> Pattern number -> Pattern number -> Pattern a", range)

local waveform = function(func)
   local query = function(span)
      return { Event(nil, span, func(span:midpoint())) }
   end

   return Pattern(query)
end

pattern.steady = function(value)
   return Pattern(function(span)
      return { Event(nil, span, value) }
   end)
end
local toBipolar = function(pat)
   return pat * 2 - 1
end

local fromBipolar = function(pat)
   return (pat + 1) / 2
end

local sine2 = waveform(function(t)
   return sin(t:asFloat() * pi * 2)
end)
local sine = fromBipolar(sine2)
local cosine2 = late(1 / 4, sine2)
local cosine = fromBipolar(cosine2)
local square = waveform(function(t)
   return floor((t * 2) % 2)
end)
local square2 = toBipolar(square)
local isaw = waveform(function(t)
   return -(t % 1) + 1
end)
local isaw2 = toBipolar(isaw)
local saw = waveform(function(t)
   return t % 1
end)
local saw2 = toBipolar(saw)
local tri = fastcat { isaw, saw }
local tri2 = fastcat { isaw2, saw2 }
local time = waveform(id)
local rand = waveform(timeToRand)

local function _irand(i)
   return fmap(rand, function(x)
      return floor(x * i)
   end)
end

local function irand(ipat)
   return innerJoin(fmap(ipat, _irand))
end
register("irand :: Pattern Num -> Pattern Num", irand)

local function _chooseWith(pat, vals)
   if #vals == 0 then
      return silence
   end
   return fmap(range(1, #vals + 1, pat), function(i)
      local key = min(max(floor(i), 0), #vals)
      return vals[key]
   end)
end

local function chooseWith(pat, ...)
   return outerJoin(_chooseWith(pat, ...))
end

local function chooseInWith(pat, vals)
   return innerJoin(_chooseWith(pat, vals))
end

local function choose(vals)
   return chooseInWith(rand, vals)
end

local function randcat(pats)
   return pattern.segment(1, choose(pats))
end
register("randcat :: [Pattern a] -> Pattern a", randcat, false)

local function degradeByWith(prand, by, pat)
   if T(by) == "time" then
      by = by:asFloat()
   end
   local f = function(v)
      return v > by
   end
   return appLeft(
      fmap(pat, function(val)
         return function(_)
            return val
         end
      end),
      filterValues(prand, f)
   )
end
register("degradeByWith :: Pattern Double -> Double -> Pattern a -> Pattern a", degradeByWith)

local function degradeBy(by, pat)
   return degradeByWith(rand, by, pat)
end
register("degradeBy :: Pattern Double -> Pattern a -> Pattern a", degradeBy)

local function undegradeBy(by, pat)
   return degradeByWith(
      fmap(rand, function(r)
         return 1 - r
      end),
      by,
      pat
   )
end
register("undegradeBy :: Pattern Double -> Pattern a -> Pattern a", undegradeBy)

local function degrade(pat)
   return degradeBy(0.5, pat)
end
register("degrade :: Pattern a -> Pattern a", degrade)

local function undegrade(pat)
   return undegradeBy(0.5, pat)
end
register("undegrade :: Pattern a -> Pattern a", undegrade)

local function sometimesBy(by, func, pat)
   local f = function()
      return overlay(degradeBy(by, pat), func(undegradeBy(1 - by, pat)))
   end
   return innerJoin(fmap(by, f))
end
register("sometimesBy :: Pattern Double -> (Pattern a -> Pattern a) -> Pattern a -> Pattern a", sometimesBy)

local function sometimes(func, pat)
   return sometimesBy(0.5, func, pat)
end
register("sometimes :: (Pattern a -> Pattern a) -> Pattern a -> Pattern a", sometimes)

local function struct(boolpat, pat)
   return op.keepif.Out(pat, boolpat)
end
register("struct :: [Pattern bool] -> Pattern a -> Pattern a", struct, false)

local function mask(boolpat, pat)
   return op.keepif.In(pat, boolpat)
end
register("mask :: [Pattern bool] -> Pattern a -> Pattern a", mask, false)

local function euclid(n, k, pat)
   return struct(bjork(n, k, 0), pat)
end
register("euclid :: Pattern Int -> Pattern Int -> Pattern a -> Pattern a", euclid)

local function euclidRot(n, k, rot, pat)
   return struct(bjork(n, k, rot), pat)
end
register("euclidRot :: Pattern Int -> Pattern Int -> Pattern Int -> Pattern a -> Pattern a", euclidRot)

function rev(pat)
   local query = function(span)
      local cycle = span.start:sam()
      local nextCycle = span.start:nextSam()
      local reflect = function(to_reflect)
         local reflected = to_reflect:withTime(function(t)
            return cycle + (nextCycle - t)
         end)
         local tmp = reflected.start
         reflected.start = reflected.stop
         reflected.stop = tmp
         return reflected
      end
      local events = pat.query(reflect(span))
      for i = 1, #events do
         events[i] = events[i]:withSpan(reflect)
      end
      return events
   end
   return Pattern(query)
end

register("rev :: Pattern a -> Pattern a", rev)

local function iter(n, pat)
   local acc = {}
   for i = 1, n do
      acc[i] = early((i - 1) / n, pat)
   end
   return slowcat(acc)
end
register("iter :: Pattern Int -> Pattern a -> Pattern a", iter)

local function reviter(n, pat)
   local acc = {}
   for i = 1, n do
      acc[i] = late((i - 1) / n, pat)
   end
   return slowcat(acc)
end
register("reviter :: Pattern Int -> Pattern a -> Pattern a", reviter)

local function echoWith(times, tim, f, pat)
   local acc = {}
   for i = 0, times - 1 do
      acc[i] = f(pattern.late(tim * i, pat))
   end
   return stack(acc)
end
register("echoWith :: Pattern Int -> Pattern Int -> Pattern f -> Pattern a -> Pattern a", echoWith)

local function when(test, f, pat)
   local query = function(span)
      local cycle_idx = span.start:sam()
      if test(cycle_idx) then
         return f(pat).query(span)
      else
         return pat.query(span)
      end
   end
   return splitQueries(Pattern(query))
end
register("when :: (Int -> Bool) -> (Pattern a -> Pattern a) ->  Pattern a -> Pattern a", when)

local slowcatPrime = function(pats)
   local query = function(span)
      local index = span.start:sam():asFloat() % #pats + 1
      local pat = pats[index]
      return pat.query(span)
   end
   return splitQueries(Pattern(query))
end

local function every(n, f, pat)
   -- print(n, f, pat)
   local acc = {}
   for i = 1, n do
      acc[i] = (i == 1) and f(pat) or pat
   end
   return slowcatPrime(acc)
end
-- nicer to write than f as ( -> ), just reify f
-- register("every :: Pattern Int -> Pattern (a -> a) -> Pattern a -> Pattern a", every)
register("every :: Pattern Int -> Pattern f -> Pattern a -> Pattern a", every)

local function off(tp, f, pat)
   return overlay(f(late(tp, pat)), pat)
end
-- HACK:
register("off :: Pattern Time -> Pattern b -> Pattern a -> Pattern a", off)

local function scale(name, pat)
   return fmap(pat, getScale(name))
end
-- TODO: "Pattern String -> Pattern a -> Pattern a",
register("scale :: String -> Pattern a -> Pattern a", scale, false)

local function chain(pat, other)
   return fmap(pat, function(a)
      return function(b)
         if T(a) == "table" then
            a[#a + 1] = b
            return a
         end
         return { a, b }
      end
   end):appLeft(other)
end
register("chain :: Pattern ValueMap -> Pattern ValueMap -> Pattern ValueMap", chain, false)

-- CONTROLS
local function juxBy(n, f, pat)
   n = n / 2
   local left = pat + { pan = 0.5 - n }
   local right = pat + { pan = 0.5 + n }
   -- print("right", right)
   -- print("left", left)
   -- print("right f", f(right))
   -- print("f", f { pan = 0.75, s = "bd" })
   return overlay(left, f(right))
end
-- "juxBy :: Pattern Double -> (Pattern ValueMap -> Pattern ValueMap) -> Pattern ValueMap -> Pattern ValueMap",
register("juxBy :: Pattern Double -> Pattern f -> Pattern ValueMap -> Pattern ValueMap", juxBy)

local function striate(n, pat)
   local pats = {}
   for i = 1, n do
      pats[i] = pat .. { ["begin"] = (i - 1) / n, ["end"] = i / n }
   end
   return fastcat(pats)
end
register("striate :: Pattern Int -> Pattern ValueMap -> Pattern ValueMap", striate)

local function chop(n, pat)
   local func = function(p)
      local acc = {}
      for i = 1, n do
         acc[i] = union({ begin = (i - 1) / n, ["end"] = i / n }, p)
      end
      return fastcat(acc)
   end
   return squeezeBind(pat, func)
end
register("chop :: Pattern Int -> Pattern ValueMap -> Pattern ValueMap", chop)

local function slice(npat, ipat, opat)
   return innerBind(npat, function(n)
      return outerBind(ipat, function(i)
         return outerBind(opat, function(o)
            o = (type(o) == "table") and o or { s = o }
            if type(n) == "table" then
               o["begin"] = n[i]
               o["end"] = n[i + 1]
            else
               o["begin"] = i / n
               o["end"] = (i + 1) / n
            end
            return pure(o)
         end)
      end)
   end)
end
register("slice :: Pattern b -> Pattern b -> Pattern a -> Pattern a", slice, false)

local function splice(npat, ipat, opat)
   return innerJoin(fmap(npat, function(n)
      local sliced = slice(pure(n), ipat, opat)
      return withEvent(sliced, function(event)
         return event:withValue(function(v)
            local new_attri = {
               -- TODO: cps
               speed = 1 / n / event.whole:duration():asFloat() * (v.speed or 1),
               unit = "c",
            }
            return union(new_attri, v)
         end)
      end)
   end))
end
register("splice :: Pattern b -> Pattern b -> Pattern a -> Pattern a", splice, false)

local function loopAt(factor, pat)
   pat = pat .. pattern.speed(factor:reverse():asFloat()) .. pattern.unit "c"
   return slow(factor, pat)
end
register("loopAt :: Pattern Time -> Pattern ValueMap -> Pattern ValueMap", loopAt)

local function fit(pat)
   return withEvent(pat, function(event)
      return event:withValue(function(value)
         return union(value, {
            speed = event.whole:duration():reverse():asFloat(),
            unit = "c",
         })
      end)
   end)
end
register("fit :: Pattern ValueMap -> Pattern ValueMap", fit)

-- TODO: clashes with the control name ... should there be control(2) ??
local function legato(factor, pat)
   return withEventSpan(pat, function(span)
      return Span(span.start, (span.start + span:duration() * factor))
   end)
end
register("legato :: Pattern Time -> Pattern a -> Pattern a", legato)

local gcd_reduce = function(tab)
   return reduce(function(acc, value)
      return acc:gcd(value)
   end, tab[1], tab)
end

local function drawLine(pat, chars)
   chars = chars or 60
   pat = reify(pat)
   local cycle = 0
   local pos = Time(0)
   local lines = { "" }
   local emptyLine = ""
   while #lines[1] < chars do
      local events = pat(cycle, cycle + 1)
      local events_with_onset = filter(function(event)
         return event:hasOnset()
      end, events)
      local durations = map(function(ev)
         return ev:duration()
      end, events_with_onset)
      local charFraction = gcd_reduce(durations)
      local totalSlots = charFraction:reverse()
      lines = map(function(line)
         return line .. "|"
      end, lines)
      emptyLine = emptyLine .. "|"
      for _ = 1, totalSlots:asFloat() do
         local start, stop = pos, pos + charFraction
         local matches = filter(function(event)
            return event.whole.start <= start and event.whole.stop >= stop
         end, events)
         local missingLines = #matches - #lines
         if missingLines > 0 then
            for _ = 1, missingLines do
               lines = lines .. missingLines
            end
         end
         lines = map(function(line, index)
            local event = matches[index]
            if event ~= nil then
               local isOnset = event.whole.start == start
               local char = nil
               if isOnset then
                  char = event.value
               else
                  char = "-"
               end
               return line .. char
            end
            return line .. "."
         end, lines)
         emptyLine = emptyLine .. "."
         pos = pos + charFraction
      end
      cycle = cycle + 1
   end
   return tconcat(lines)
end
mt.drawLine = drawLine
pattern.drawLine = drawLine

---CONTROLS
local parseChord = theory.parseChord
local control = require "control"
local genericParams, aliasParams = control.genericParams, control.aliasParams

---@param name string
local create = function(name)
   local withVal, f
   if type(name) == "table" then
      withVal = function(xs)
         if type(xs) == "table" then
            local acc = {}
            for i, x in ipairs(xs) do
               acc[name[i]] = x
            end
            return ValueMap(acc)
         else
            return ValueMap { [name] = xs }
         end
      end
      f = function(args)
         return reify(args):fmap(withVal)
      end
      name = name[1]
   else
      f = function(arg)
         return reify(arg):fmap(function(a)
            return { [name] = a }
         end)
      end
   end
   pattern[name] = f
   mt[name] = function(self, arg)
      return self .. f(arg)
   end
end

for _, param in ipairs(genericParams) do
   create(param)
   if aliasParams[param] ~= nil then
      local alias = aliasParams[param]
      if type(alias) == "table" then
         for _, al in ipairs(alias) do
            pattern[al] = pattern[param]
            mt[al] = mt[param]
         end
      else
         pattern[alias] = pattern[param]
         mt[alias] = mt[param]
      end
   end
end

pattern.note = function(pat, arp)
   local function chordToStack(thing)
      if type(thing) == "string" then
         if type(parseChord(thing)) == "table" then
            local notes = parseChord(thing)
            return arp and fastcat(notes) or stack(notes) -- arp function
         end
         return reify(thing)
      elseif T(thing) == "pattern" then
         return outerJoin(thing:fmap(function(chord)
            local notes = parseChord(chord)
            return arp and fastcat(notes) or stack(notes)
         end))
      else
         return reify(thing)
      end
   end
   local withVal = function(v)
      return ValueMap { note = v }
   end
   return fmap(chordToStack(pat), withVal)
end

---@param d number
---@param s string | number
---@return Pattern
local function cF(d, s)
   -- print(s)
   s = tonumber(s) and tonumber(s) or s
   local query = function(span)
      if not span.controls then
         return silence
      end
      local val = span.controls[s]
      -- print(val)
      local pat = pure(val or d)
      -- print(pat.query(span))
      return pat.query(span)
   end
   return Pattern(query)
end
pattern.cF = cF

pattern.n = pattern.note
mt.note = function(self, arg)
   return self .. pattern.note(arg)
end
mt.n = mt.note

pattern.op = op
pattern.id = id
pattern.T = T
pattern.pipe = ut.pipe
pattern.dump = ut.dump
pattern.t = TYPES
pattern.mt = mt
pattern.tri2 = tri2
pattern.tri = tri
pattern.saw2 = saw2
pattern.saw = saw
pattern.isaw = isaw
pattern.isaw2 = isaw2
pattern.square2 = square2
pattern.square = square
pattern.cosine = cosine
pattern.cosine2 = cosine2
pattern.sine = sine
pattern.sine2 = sine2
pattern.rand = rand
pattern.time = time

pattern.squeezeJoin = squeezeJoin

return pattern
