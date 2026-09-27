local scriptsPath = assert(arg[1], "usage: luajit tools/audit_callbacks.lua <scripts.lua> [native-hex]")
local scripts = assert(loadfile(scriptsPath))()
local wanted = arg[2] and tonumber(arg[2])

local function describe(row)
  local fields = { row.op or "?" }
  for _, key in ipairs({ "var", "value", "dest", "id", "fn", "species", "level",
      "item", "quantity", "target", "text", "std", "flag", "localId" }) do
    local value = row[key]
    if value ~= nil then
      if type(value) == "number" and (key == "fn" or key == "id") then
        value = ("0x%X"):format(value)
      end
      fields[#fields + 1] = key .. "=" .. tostring(value)
    end
  end
  return table.concat(fields, " ")
end

local found = {}
for scriptKey, rows in pairs(scripts) do
  for index, row in ipairs(rows) do
    if row.op == "callnative" then
      local address = tonumber(row.fn or row[1]) or 0
      if not wanted or wanted == address then
        local entry = found[address] or { count = 0, contexts = {} }
        found[address] = entry
        entry.count = entry.count + 1
        if #entry.contexts < 5 then
          local context = { script = scriptKey, index = index, rows = {} }
          for at = math.max(1, index - 6), math.min(#rows, index + 6) do
            context.rows[#context.rows + 1] = {
              marker = at == index and ">" or " ",
              index = at,
              text = describe(rows[at]),
            }
          end
          entry.contexts[#entry.contexts + 1] = context
        end
      end
    end
  end
end

local addresses = {}
for address in pairs(found) do addresses[#addresses + 1] = address end
table.sort(addresses)
for _, address in ipairs(addresses) do
  local entry = found[address]
  print(("NATIVE 0x%08X uses=%d"):format(address, entry.count))
  for _, context in ipairs(entry.contexts) do
    print(("  SCRIPT %s @%d"):format(context.script, context.index))
    for _, row in ipairs(context.rows) do
      print(("  %s %d %s"):format(row.marker, row.index, row.text))
    end
  end
end
