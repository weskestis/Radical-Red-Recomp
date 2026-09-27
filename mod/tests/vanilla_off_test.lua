-- A fresh stock process with the mod disabled must retain Gen III behavior.
package.path = "./?.lua;./?/init.lua;" .. package.path

local Types = require("src.core.game3.battle.types")
assert(Types.ID.FAIRY == nil)
assert(Types.isPhysical(7) == true)      -- Ghost is physical in Gen III.
assert(Types.isPhysical(17) == false)    -- Dark is special in Gen III.
assert(Types.effectiveness(17, 8) == 0.5)
assert(Types.effectiveness(7, 8) == 0.5)

print("PASS vanilla_off_test: disabled mod leaves stock FireRed battle behavior untouched")
