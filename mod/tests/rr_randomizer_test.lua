package.path = "./?.lua;./?/init.lua;" .. package.path

local Randomizer = assert(loadfile("lib/rr_randomizer.lua"))()

for _, trainerClass in ipairs({ 81, 89 }) do
  assert(Randomizer.isFixedRival(trainerClass, 0),
    "rival class was not protected: " .. trainerClass)
end

for _, trainerId in ipairs({
  26, 44, 50, 55, 57, 61,
  438, 439, 440, 739, 740, 741,
}) do
  assert(Randomizer.isFixedRival(1, trainerId),
    "rival trainer id was not protected: " .. trainerId)
end

assert(not Randomizer.isFixedRival(1, 19),
  "ordinary Pokemon Trainer was mistaken for a rival")
assert(not Randomizer.isFixedRival(90, 100),
  "Champion class was protected too broadly")
assert(not Randomizer.isFixedRival(nil, nil),
  "missing trainer identity was mistaken for a rival")

local Trainers = {}
function Trainers.get(id)
  local rows = {
    [414] = { name = "BROCK", className = "LEADER" },
    [410] = { name = "LORELEI", className = "ELITE FOUR" },
    [999] = { name = "GIOVANNI", className = "BOSS" },
    [19] = { name = "YOUNGSTER", className = "YOUNGSTER" },
  }
  return rows[id]
end
package.loaded["src.core.game3.scripting.trainers"] = Trainers

assert(Randomizer.isFixedBoss(84, 414), "Brock was not protected as a boss")
assert(Randomizer.isFixedBoss(87, 410), "Elite Four battle was not protected")
assert(Randomizer.isFixedBoss(1, 999), "Giovanni was not protected by live trainer metadata")
assert(not Randomizer.isFixedBoss(1, 19), "ordinary trainer was mistaken for a boss")

print("PASS rr_randomizer_test: RR rivals and authored bosses bypass randomization")
