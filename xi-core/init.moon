pattern = require "xi.pattern"
pattern_factory = require "xi.pattern_factory"
import C from require "xi.pattern"
import drawline from require "xi.drawline"

xi = {
  _VERSION: "xi dev-1"
	_URL: "https://github.com/noearc/xi"
	_DESCRIPTION: "A language for algorithmic pattern. Tidalcycles for moonscript"
}

xi.drawline = drawline

for name, func in pairs pattern
  if i != "C" and i != "Pattern"
    xi[name] = func

for name, func in pairs pattern_factory
  xi[name] = func

for name, func in pairs C
  xi[name] = func

return xi