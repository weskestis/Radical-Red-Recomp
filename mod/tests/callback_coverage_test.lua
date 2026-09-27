package.path = "./?.lua;./?/init.lua;" .. package.path

-- Every real callnative target recovered from the exact RR 4.1 script graph.
-- Keeping the contract here makes an accidentally dropped handler a release
-- failure without bundling any scripts or other ROM-derived content.
local expected = {
  0x0906E935,
  0x090772D1, 0x09077A19, 0x09077AD1, 0x09077B09, 0x09077B59,
  0x09077C45, 0x09077D4D, 0x09077D9D, 0x09077DED, 0x09077E3D,
  0x09077F75, 0x09077FD1, 0x09078085, 0x090790C9, 0x09079289,
  0x09079301, 0x0907C9E1, 0x0907CA2D, 0x0907CC55, 0x0907CCDD,
  0x0907CE21, 0x0908F21D, 0x090950A5,
  0x090964B1, 0x09096501, 0x09096DF5, 0x09096EAD, 0x090988E5,
  0x0909921D, 0x090992E5, 0x09099421, 0x09099431, 0x090995D5,
  0x09099621, 0x0909971D, 0x090997B5, 0x09099835, 0x090B0939,
  0x090B18C1, 0x090B18CB, 0x090B18D5, 0x090B18DF, 0x090B18E9,
  0x090B18F3, 0x090B18FD, 0x090B1907, 0x090B1911, 0x090B191B,
  0x090B1925, 0x090B192F, 0x090B1939, 0x090B1943, 0x090B194D,
  0x090B1957, 0x090B1961, 0x090B196B, 0x090B1975, 0x090B197F,
  0x090B1989, 0x090B5CDD, 0x090B5EF9, 0x090B5F8D, 0x090B6005,
  0x090B8201, 0x090BB1A9, 0x090BB2A1, 0x090BBD3D,
  0x090C18A1, 0x090C1935, 0x090C19B5, 0x090C19E9,
}

local roots = {
  assert(loadfile("mods/radical_red_experience/lib/rr_mechanics.lua"))().ADDR,
  assert(loadfile("mods/radical_red_experience/lib/rr_facilities.lua"))().ADDR,
  assert(loadfile("mods/radical_red_experience/lib/rr_raids.lua"))().ADDR,
  assert(loadfile("mods/radical_red_experience/lib/rr_story.lua"))().ADDR,
  assert(loadfile("mods/radical_red_experience/lib/rr_natives.lua"))().NATURE_NATIVES,
}

local covered = {}
for _, registry in ipairs(roots) do
  for key, value in pairs(registry) do
    local address = type(key) == "number" and key or value
    assert(type(address) == "number", "non-numeric native address")
    assert(not covered[address], ("native callback registered twice: 0x%08X"):format(address))
    covered[address] = true
  end
end

local expectedSet = {}
for _, address in ipairs(expected) do
  assert(not expectedSet[address], ("duplicate expected callback: 0x%08X"):format(address))
  expectedSet[address] = true
  assert(covered[address], ("missing RR callnative handler: 0x%08X"):format(address))
end
for address in pairs(covered) do
  assert(expectedSet[address], ("unreviewed callnative handler: 0x%08X"):format(address))
end

assert(#expected == 72)
print("PASS callback_coverage_test: all 72 real RR 4.1 callnative targets are handled")
