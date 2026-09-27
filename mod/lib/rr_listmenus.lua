-- Radical Red v4.1 custom list-menu tables.
--
-- RR replaces FireRed's badge-list special with a table-driven 16-menu
-- implementation.  Keep the labels private by decoding them from the
-- launcher-validated ROM into the mod cache on first boot.

local RRListMenus = {}

RRListMenus.TABLE_OFFSET = 0x1148C78
RRListMenus.MENU_COUNT = 16
RRListMenus.CACHE_FILE = "scripts/rr_listmenus.lua"

local function readText(rom, pointer)
  local offset = assert(rom:ptrOffset(pointer),
    ("Radical Red list label is not a ROM pointer (0x%08X)"):format(pointer))
  local bytes = {}
  for i = 0, 255 do
    local byte = rom:get(offset + i)
    bytes[#bytes + 1] = byte
    if byte == 0xFF then break end
  end
  assert(bytes[#bytes] == 0xFF,
    ("Radical Red list label at 0x%08X has no terminator"):format(pointer))
  local TextIR = require("src.core.game3.scripting.text_ir")
  local label = TextIR.toPlain(TextIR.decode(bytes), {})
  -- ROM labels intentionally use internal padding for aligned nature stats.
  -- Remove only terminal whitespace introduced before EOS.
  return (label:gsub("%s+$", ""))
end

function RRListMenus.extract(rom)
  assert(rom and rom.u32 and rom.ptrOffset,
    "Radical Red list-menu extraction needs a ROM reader")
  local lists = {}
  for id = 0, RRListMenus.MENU_COUNT - 1 do
    local row = RRListMenus.TABLE_OFFSET + id * 8
    local pointers = assert(rom:ptrOffset(rom:u32(row)),
      ("Radical Red list %d has an invalid pointer table"):format(id))
    local count = rom:u32(row + 4)
    assert(count >= 1 and count <= 64,
      ("Radical Red list %d has invalid count %s"):format(id, tostring(count)))
    local labels = {}
    for index = 0, count - 1 do
      local label = readText(rom, rom:u32(pointers + index * 4))
      assert(label ~= "", ("Radical Red list %d label %d is empty"):format(id, index))
      labels[#labels + 1] = label
    end
    lists[id] = { count = count, labels = labels }
  end

  -- These signatures make a wrong ROM revision/table address fail extraction
  -- instead of quietly presenting unrelated text at runtime.
  assert(lists[6].labels[1]:match("^Adamant"),
    "Radical Red nature list signature changed")
  assert(table.concat(lists[12].labels, ",")
      == "Johto,Hoenn,Sinnoh,Unova,Kalos,Alola,Galar,Paldea",
    "Radical Red starter-region list signature changed")
  return { version = 1, count = RRListMenus.MENU_COUNT, lists = lists }
end

local function quote(value)
  return string.format("%q", tostring(value))
end

function RRListMenus.serialize(data)
  local lines = {
    "-- Generated from the player's exact Radical Red v4.1 ROM.",
    "return { version = 1, count = 16, lists = {",
  }
  for id = 0, RRListMenus.MENU_COUNT - 1 do
    local entry = assert(data.lists[id], "missing Radical Red list " .. id)
    lines[#lines + 1] = ("  [%d] = { count = %d, labels = {"):format(id, entry.count)
    for _, label in ipairs(entry.labels) do
      lines[#lines + 1] = "    " .. quote(label) .. ","
    end
    lines[#lines + 1] = "  } },"
  end
  lines[#lines + 1] = "} }"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

function RRListMenus.write(cache, root, rom)
  local data = RRListMenus.extract(rom)
  local rel = root .. "/" .. RRListMenus.CACHE_FILE
  local ok, err = cache:write(rel, RRListMenus.serialize(data))
  assert(ok ~= false and ok ~= nil,
    "could not write Radical Red custom lists: " .. tostring(err))
  return data, rel
end

return RRListMenus
