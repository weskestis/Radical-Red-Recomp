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

print("PASS rr_randomizer_test: all RR v4.1 rival branches bypass randomization")
