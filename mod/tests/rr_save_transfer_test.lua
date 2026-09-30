package.path = "./?.lua;./?/init.lua;" .. package.path

local cartSlots = {
  { id = "slot1", exists = true, name = "RR" },
}
local activeCartSlot = "slot1"
local created = 1
local written = {}
local deleted = {}
local options = { modsByVersion = { firered = { radical_red_experience = true } } }

local SaveData = {}
function SaveData.loadOptions() return options end
function SaveData.modScope(version) return version end
function SaveData.modEnabled(opts, id, version)
  local b = opts.modsByVersion and opts.modsByVersion[version]
  return b and b[id]
end
function SaveData.listCartSlots(id)
  assert(id == "radical_red_4_1")
  return cartSlots
end
function SaveData.createCartSlot(id)
  assert(id == "radical_red_4_1")
  created = created + 1
  return "slot" .. created
end
function SaveData.setActiveCartSlot(id, slot)
  assert(id == "radical_red_4_1")
  activeCartSlot = slot
  return slot
end
function SaveData.writeCartSlot(id, slot, save)
  assert(id == "radical_red_4_1")
  if save and save.__writeFail then return false, "forced write failure" end
  written[slot] = save
  return true
end
function SaveData.readCartSlotSource(id, slot)
  local row = written[slot]
  if row and row.__readbackFail then return nil end
  return row and "return {}" or (slot == "slot1" and "return {}" or nil)
end
function SaveData.deleteCartSlot(id, slot)
  assert(id == "radical_red_4_1")
  deleted[#deleted + 1] = slot
  written[slot] = nil
  return true
end
function SaveData.renameCartSlot(id, slot, name)
  assert(id == "radical_red_4_1")
  SaveData.renamed = { slot, name }
  return true
end
package.loaded["src.core.SaveData"] = SaveData

local SaveSerializer = {}
function SaveSerializer.decode(bytes)
  local function marked(name)
    return type(bytes) == "string" and bytes:find(name, 1, true) ~= nil
  end
  if marked("BAD") then return nil, "bad" end
  local version = marked("LEGACY") and "radical_red_runtime"
    or marked("WRONG") and "emerald" or "firered"
  return {
    version = version, generation = 3, engine = "game3",
    party = {}, meta = {}, name = "RED",
    registeredItem = marked("ZERO_REGISTERED") and 0 or nil,
    __writeFail = marked("WRITE_FAIL") or nil,
    __readbackFail = marked("READBACK_FAIL") or nil,
  }
end
package.loaded["src.core.SaveSerializer"] = SaveSerializer

local GameVersion = { current = "firered", setCalls = 0 }
function GameVersion.get() return GameVersion.current end
function GameVersion.set(id)
  GameVersion.setCalls = GameVersion.setCalls + 1
  GameVersion.current = id
  error("RR save bridge must not switch the launcher game version")
end
package.loaded["src.core.GameVersion"] = GameVersion

local exportArgs
local SaveFileIO = {}
function SaveFileIO.exportLuaSlot(version, slotId, cartId)
  exportArgs = { version, slotId, cartId }
  return true, "ok.lua"
end
function SaveFileIO.exportActiveSlot(version)
  return true, "base.sav"
end
package.loaded["src.import.SaveFileIO"] = SaveFileIO

local RomImporter = {}
function RomImporter.new(_, opts)
  return setmetatable({
    onEditSave = opts and opts.onEditSave,
    tab = "firered",
    slots = {}, activeSlot = {}, slotScroll = {}, saveNotice = {},
    workState = "idle",
  }, { __index = RomImporter })
end
function RomImporter:_refreshSlots(scope)
  self.slots[scope] = { { id = "base" } }
  self.activeSlot[scope] = "base"
end
function RomImporter:_selectSlot(scope, id) self.activeSlot[scope] = id end
function RomImporter:_newSlot(scope) self.activeSlot[scope] = "base-new" end
function RomImporter:_deleteSlot() self.baseDelete = true end
function RomImporter:_commitRename() self.baseRename = true end
function RomImporter:_importSave() self.baseImport = true end
package.loaded["src.import.RomImporter"] = RomImporter

local Runtime = assert(loadfile("lib/rr_runtime.lua"))()
local Profile = {
  ID = "radical_red_4_1",
  SHA1 = "964f951a0fdaf209e4ea1344883ef0d557bb3a80",
}
assert(Runtime._installSaveTransferBridge(Profile) == true)

local imp = RomImporter.new(nil, { onEditSave = function() error("must not open stock editor") end })
imp:_refreshSlots("firered")
assert(imp.slots.firered == cartSlots and imp.activeSlot.firered == "slot1",
  "FireRed save card did not stay on Radical Red's private slots")

imp:_selectSlot("firered", "slot1")
assert(activeCartSlot == "slot1")
imp:_newSlot("firered")
assert(activeCartSlot == "slot2" and imp.activeSlot.firered == "slot2")

imp._rename = { version = "firered", id = "slot2", text = "RUN" }
imp:_commitRename()
assert(SaveData.renamed[1] == "slot2" and SaveData.renamed[2] == "RUN")

imp:_importSave("firered", "return { version='firered' }")
assert(imp.activeSlot.firered == "slot3" and written.slot3
    and written.slot3.meta.cartId == Profile.ID
    and written.slot3.version == "firered",
  "RR .lua import did not land in the private cart scope")
assert(imp.tab == "firered" and GameVersion.current == "firered"
    and GameVersion.setCalls == 0,
  "RR import changed the launcher game instead of only changing save scope")

-- Accept the bad v0.5.18 private-runtime stamp once, but normalize it back to
-- the public FireRed game identity before the imported slot is persisted.
imp:_importSave("firered", "return { fixture='LEGACY' }")
assert(imp.activeSlot.firered == "slot4" and written.slot4
    and written.slot4.version == "firered"
    and written.slot4.meta.cartId == Profile.ID,
  "legacy radical_red_runtime save was not normalized into FireRed context")
assert(imp.tab == "firered" and GameVersion.current == "firered"
    and GameVersion.setCalls == 0,
  "legacy RR import switched launcher game context")

-- ITEM_NONE can be serialized as numeric zero by older/original save paths.
-- Normalize it during import so field SELECT does not treat item 0 as a real
-- registered key item.
imp:_importSave("firered", "return { fixture='ZERO_REGISTERED' }")
assert(imp.activeSlot.firered == "slot5" and written.slot5
    and written.slot5.registeredItem == nil,
  "RR import preserved registeredItem=0 instead of ITEM_NONE")

-- A failed write/readback must remove the newly allocated private slot rather
-- than leaving a broken save entry behind.
imp:_importSave("firered", "return { fixture='WRITE_FAIL' }")
assert(deleted[#deleted] == "slot6" and written.slot6 == nil
    and imp.saveNotice.firered and imp.saveNotice.firered.ok == false,
  "failed RR save write did not roll back its private slot")
imp:_importSave("firered", "return { fixture='READBACK_FAIL' }")
assert(deleted[#deleted] == "slot7" and written.slot7 == nil
    and imp.saveNotice.firered and imp.saveNotice.firered.ok == false,
  "failed RR save readback did not roll back its private slot")

local createdBeforeWrong = created
imp:_importSave("firered", "return { fixture='WRONG' }")
assert(created == createdBeforeWrong
    and imp.saveNotice.firered and imp.saveNotice.firered.ok == false,
  "non-FireRed save reached Radical Red private slot allocation")
assert(imp.tab == "firered" and GameVersion.current == "firered"
    and GameVersion.setCalls == 0,
  "failed RR import changed launcher game context")

assert(SaveFileIO.exportLuaSlot("firered", "slot4") == true)
assert(exportArgs[1] == "firered" and exportArgs[2] == "slot4"
    and exportArgs[3] == Profile.ID,
  "RR .lua export changed game context instead of selecting the private save scope")
assert(imp.tab == "firered" and GameVersion.current == "firered"
    and GameVersion.setCalls == 0,
  "RR export changed the launcher game")
local ok, err = SaveFileIO.exportActiveSlot("firered")
assert(ok == false and tostring(err):find("Original save", 1, true),
  "RR raw .sav export was not safely refused")

GameVersion.current = "firered"
imp.onEditSave("firered", "slot3")
assert(GameVersion.current == "firered"
    and imp.saveNotice.firered
    and imp.saveNotice.firered.text:find("disabled", 1, true),
  "save management changed the active launcher game")

options.modsByVersion.firered.radical_red_experience = false
imp:_refreshSlots("firered")
assert(imp.slots.firered[1].id == "base",
  "disabling Radical Red did not restore FireRed's ordinary save card")
assert(SaveFileIO.exportLuaSlot("firered", "base") == true
    and exportArgs[1] == "firered" and exportArgs[2] == "base"
    and exportArgs[3] == nil,
  "disabled RR bridge still redirected ordinary FireRed export into the private cart")
assert(imp.tab == "firered" and GameVersion.current == "firered"
    and GameVersion.setCalls == 0,
  "disabling RR save redirection changed launcher game context")

print("PASS rr_save_transfer_test: RR import/export preserves FireRed launcher context")
