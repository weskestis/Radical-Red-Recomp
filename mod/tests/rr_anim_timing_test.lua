local Runtime = assert(loadfile("lib/rr_runtime.lua"))()

local calls = {}
local Anim = {
  _pack = { moves = { [1003] = {} } },
  update = function(dt) calls[#calls + 1] = dt end,
}

assert(Runtime._installBattleAnimTiming(Anim) == true)

Anim.update(1 / 30)
assert(#calls == 2, "30 FPS render must advance two 60 Hz RR animation ticks")
for _, dt in ipairs(calls) do
  assert(math.abs(dt - 1 / 60) < 1e-9,
    "RR animation catch-up did not use a 60 Hz fixed timestep")
end

calls = {}
Anim.update(1 / 120)
assert(#calls == 0,
  "120 FPS render should accumulate half a simulation tick")
Anim.update(1 / 120)
assert(#calls == 1,
  "two 120 FPS frames should advance one 60 Hz animation tick")

calls = {}
Anim.update(0.1)
assert(#calls == 4,
  "RR animation catch-up must cap overloaded frames at four ticks")

calls = {}
Anim._pack = { moves = { [354] = {} } }
Anim.update(1 / 30)
assert(#calls == 1 and math.abs(calls[1] - 1 / 30) < 1e-9,
  "vanilla animation packs must keep the stock update cadence")

assert(Runtime._installBattleAnimTiming(Anim) == true)
calls = {}
Anim._pack = { moves = { [1003] = {} } }
Anim.update(1 / 30)
assert(#calls == 2,
  "reinstalling RR animation timing double-wrapped the updater")

print("PASS rr_anim_timing_test: RR animations use fixed 60 Hz catch-up without affecting vanilla")
