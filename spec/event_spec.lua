local Fraction
Fraction = require("modal.fraction").Fraction
local Span, Event
do
  local _obj_0 = require("modal.types")
  Span, Event = _obj_0.Span, _obj_0.Event
end
return describe("Event", function()
  describe("constructors", function()
    it("shoud new with default values", function()
      local event = Event()
      assert.is_nil(event.whole)
      assert.are.same(event.part, Span())
      assert.is_nil(event.value)
      assert.are.same(event.context, { })
      return assert.are.same(event.stateful, false)
    end)
    return it('should new with arguments', function()
      local expectedWhole = Span(1 / 2, 1)
      local expectedPart = Span(1 / 2, 3 / 4)
      local expectedContext = {
        field = "thing"
      }
      local expectedValue = 5
      local event = Event(expectedWhole, expectedPart, expectedValue, expectedContext, false)
      assert.are.equals(event.whole, expectedWhole)
      assert.are.Equals(event.part, expectedPart)
      assert.are.Equals(event.value, expectedValue)
      assert.are.Equals(event.context, expectedContext)
      assert.is_false(event.stateful)
      return assert.has_error(function()
        return Event(expectedWhole, expectedPart, expectedValue, expectedContext, true)
      end)
    end)
  end)
  describe("duration", function()
    it("should return duration of event in cycles", function()
      local whole = Span(1 / 2, 1)
      local part = Span(1 / 2, 3 / 4)
      local event = Event(whole, part, 5, { }, false)
      return assert.are.equals(Fraction(1, 2), event:duration())
    end)
    describe("wholeOrPart", function()
      it("should return whole if defined", function()
        local whole = Span(1 / 2, 1)
        local part = Span(1 / 2, 3 / 4)
        local event = Event(whole, part, 5, { }, false)
        return assert.are.equals(whole, event:wholeOrPart())
      end)
      return it("should return part if whole is not defined", function()
        local part = Span(1 / 2, 3 / 4)
        local event = Event(nil, part, 5, { }, false)
        return assert.are.equals(part, event:wholeOrPart())
      end)
    end)
    return describe("hasOnset", function()
      return it("should report onset true if part and whole begin together", function()
        local whole = Span(1 / 2, 1)
        local part = Span(1 / 2, 3 / 4)
        local event = Event(whole, part, 5, { }, false)
        assert.is_true(event:hasOnset())
        whole = Span(1 / 2, 1)
        part = Span(2 / 3, 1)
        event = Event(whole, part, 5, { }, false)
        assert.is_false(event:hasOnset())
        whole = Span(1 / 2, 1)
        part = Span(2 / 3, 3 / 4)
        event = Event(whole, part, 5, { }, false)
        assert.is_false(event:hasOnset())
        part = Span(2 / 3, 3 / 4)
        event = Event(nil, part, 5, { }, false)
        return assert.is_false(event:hasOnset())
      end)
    end)
  end)
  describe("withSpan", function()
    return it("should return new event with modified span", function()
      local oldPart = Span(2 / 3, 6 / 5)
      local oldWhole = Span(1 / 2, 7 / 5)
      local newPartAndWhole = Span(1 / 2, 3 / 4)
      local changeSpan
      changeSpan = function()
        return newPartAndWhole
      end
      local event = Event(oldWhole, oldPart, 5, { }, false)
      local newEvent = event:withSpan(changeSpan)
      assert.are.equals(newPartAndWhole, newEvent.part)
      assert.are.equals(newPartAndWhole, newEvent.whole)
      assert.are.equals(oldPart, event.part)
      event = Event(nil, oldPart, 5, { }, false)
      newEvent = event:withSpan(changeSpan)
      assert.are.equals(newPartAndWhole, newEvent.part)
      assert.is_nil(newEvent.whole)
      return assert.are.equals(oldPart, event.part)
    end)
  end)
  describe("show", function()
    return it("should produce string representation of event times", function()
      local event = Event(Span(1 / 2, 2), Span(1 / 2, 1), 5)
      assert.are.equals(event:show(), "[(1/2 → 1/1) ⇝ | 5]")
      event = Event(Span(1 / 2, 1), Span(1 / 2, 1), 6)
      assert.are.equals(event:show(), "[1/2 → 1/1 | 6]")
      event = Event(Span(1 / 2, 1), Span(3 / 4, 1), 6)
      return assert.are.equals(event:show(), "[(3/4 → 1/1) ⇜ | 6]")
    end)
  end)
  describe("withValue", function()
    return it("should return new event with modified value", function()
      local oldValue = 5
      local add1
      add1 = function(v)
        return v + 1
      end
      local event = Event(nil, Span(1 / 2, 1), oldValue)
      local newEvent = event:withValue(add1)
      return assert.are.equals(newEvent.value, 6)
    end)
  end)
  describe("spanEquals", function()
    return it("should report if events share a part", function()
      local event1 = Event(Span(1 / 2, 1), Span(1 / 2, 1), 5)
      local event2 = Event(Span(1 / 2, 1), Span(3 / 4, 1), 5)
      assert.is_true(event1:spanEquals(event2))
      local event3 = Event(Span(0, 1), Span(1 / 2, 1), 5)
      assert.is_false(event1:spanEquals(event3))
      local event4 = Event(nil, Span(1 / 2, 1), 5)
      assert.is_false(event1:spanEquals(event4))
      local event5 = Event(nil, Span(3 / 4, 1), 6)
      return assert.is_true(event4:spanEquals(event5))
    end)
  end)
  describe("equals", function()
    return it("should compare all properties", function()
      local event1 = Event(Span(1 / 2, 1), Span(1 / 2, 1), 5, { }, false)
      local event2 = Event(Span(1 / 2, 1), Span(1 / 2, 1), 5, { }, false)
      assert.is_true(event1 == event2)
      local event3 = Event(Span(1 / 2, 1), Span(1 / 2, 1), 6, { }, false)
      local event4 = Event(Span(1 / 2, 1), Span(3 / 4, 1), 5, { }, false)
      assert.is_false(event1 == event3)
      assert.is_false(event1 == event4)
      local event5 = Event(Span(3 / 4, 1), Span(1 / 2, 1), 5, { }, false)
      return assert.is_false(event1 == event5)
    end)
  end)
  describe("combineContext", function()
    return it("should return new event with merged context tables", function()
      local event1 = Event(Span(1 / 2, 1), Span(1 / 2, 1), 5, {
        thing1 = "something",
        thing2 = 5,
        locations = {
          1,
          2,
          3
        }
      }, false)
      local event2 = Event(Span(1 / 2, 1), Span(1 / 2, 1), 6, {
        thing1 = "something else",
        thing3 = "more cowbell",
        locations = {
          4,
          5,
          6
        }
      }, false)
      local expectedContext = {
        thing1 = "something else",
        thing2 = 5,
        thing3 = "more cowbell",
        locations = {
          1,
          2,
          3,
          4,
          5,
          6
        }
      }
      assert.are.same(expectedContext, event1:combineContext(event2))
      event1 = Event(Span(1 / 2, 1), Span(1 / 2, 1), 5, {
        thing1 = "something",
        thing2 = 5,
        locations = {
          1,
          2,
          3
        }
      }, false)
      event2 = Event(Span(1 / 2, 1), Span(1 / 2, 1), 6, {
        thing1 = "something else",
        thing3 = "more cowbell"
      }, false)
      expectedContext = {
        thing1 = "something else",
        thing2 = 5,
        thing3 = "more cowbell",
        locations = {
          1,
          2,
          3
        }
      }
      return assert.are.same(expectedContext, event1:combineContext(event2))
    end)
  end)
  return describe("setContext", function()
    return it("should return new event with specified context", function()
      local event = Event(Span(1 / 2, 1), Span(1 / 2, 1), 5, {
        thing = "something"
      }, false)
      local newContext = {
        thing2 = "something else"
      }
      local expectedEvent = Event(Span(1 / 2, 1), Span(1 / 2, 1), 5, newContext, false)
      local actualEvent = event:setContext(newContext)
      return assert.are.same(expectedEvent, actualEvent)
    end)
  end)
end)
