-- ForeverCDs: tracked spell presets, resolution and rank matching.
local _, ns = ...
local Spells = {}
ns.Spells = Spells

-- Preset table. Only Innervate is enabled by default. ids lists every known
-- rank; casts of an unknown rank still match by name (see Matches).
-- cd values are base cooldowns in seconds; GetSpellBaseCooldown wins when readable.
Spells.presets = {
  innervate          = { name = "Innervate",              class = "DRUID",   ids = { 29166 },                                   cd = 360,  minLevel = 40, enabled = true },
  rebirth            = { name = "Rebirth",                class = "DRUID",   ids = { 20484, 20739, 20742, 20747, 20748 },       cd = 1800, minLevel = 20 },
  tranquility        = { name = "Tranquility",            class = "DRUID",   ids = { 740, 8918, 9862, 9863 },                   cd = 300,  minLevel = 30 },
  manatidetotem      = { name = "Mana Tide Totem",        class = "SHAMAN",  ids = { 16190, 17354, 17359 },                     cd = 300,  minLevel = 40, talent = true },
  blessingofprotection = { name = "Blessing of Protection", class = "PALADIN", ids = { 1022, 5599, 10278 },                   cd = 300,  minLevel = 10 },
  layonhands         = { name = "Lay on Hands",           class = "PALADIN", ids = { 633, 2800, 10310 },                        cd = 3600, minLevel = 10 },
  divineintervention = { name = "Divine Intervention",    class = "PALADIN", ids = { 19752 },                                   cd = 3600, minLevel = 30 },
  fearward           = { name = "Fear Ward",              class = "PRIEST",  ids = { 6346 },                                    cd = 30,   minLevel = 20 },
  powerinfusion      = { name = "Power Infusion",         class = "PRIEST",  ids = { 10060 },                                   cd = 180,  minLevel = 40, talent = true },
  soulstoneresurrection = { name = "Soulstone Resurrection", class = "WARLOCK", ids = { 20707, 20762, 20763, 20764, 20765 },   cd = 1800, minLevel = 18 },
}

-- Display order in the options panel; custom spells follow, by name.
Spells.ORDER = {
  "innervate", "rebirth", "tranquility", "manatidetotem", "blessingofprotection",
  "layonhands", "divineintervention", "fearward", "powerinfusion", "soulstoneresurrection",
}

Spells.CLASS_NAMES = {
  DRUID = "Druid", PALADIN = "Paladin", PRIEST = "Priest", SHAMAN = "Shaman", WARLOCK = "Warlock",
  MAGE = "Mage", WARRIOR = "Warrior", ROGUE = "Rogue", HUNTER = "Hunter",
}

Spells.CLASSES = {
  DRUID = true, PALADIN = true, PRIEST = true, SHAMAN = true, WARLOCK = true,
  MAGE = true, WARRIOR = true, ROGUE = true, HUNTER = true,
}

local function copy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = copy(v) end
  return r
end
Spells.copy = copy

-- Fill missing preset fields into the saved spell table without touching user edits.
function Spells.FillPresets(spells)
  for key, p in pairs(Spells.presets) do
    local s = spells[key]
    if s == nil then
      s = copy(p)
      s.enabled = p.enabled and true or false
      spells[key] = s
    elseif type(s) == "table" then
      for k, v in pairs(p) do
        if s[k] == nil then s[k] = copy(v) end
      end
      if s.enabled == nil then s.enabled = false end
    end
  end
  for key, s in pairs(spells) do
    if type(s) == "table" then s.key = key end
  end
end

-- Localized spell name for an ID, or nil.
function Spells.NameOf(id)
  if type(id) ~= "number" then return nil end
  local name
  if C_Spell and C_Spell.GetSpellName then
    name = ns.plain(ns.safe(C_Spell.GetSpellName, id), "string")
  end
  if not name and GetSpellInfo then
    name = ns.plain(ns.safe(GetSpellInfo, id), "string")
  end
  return name
end

local iconCache = {}
function Spells.IconOf(spell)
  local id = spell and spell.ids and spell.ids[1]
  if not id then return 134400 end
  if iconCache[id] then return iconCache[id] end
  local tex
  if C_Spell and C_Spell.GetSpellTexture then
    -- Parentheses keep only the first return: it also returns originalIconID.
    tex = ns.plain((ns.safe(C_Spell.GetSpellTexture, id)))
  end
  if not tex and GetSpellTexture then tex = ns.plain((ns.safe(GetSpellTexture, id))) end
  if tex then iconCache[id] = tex end
  return tex or 134400
end

-- Name used for rank matching: the localized name of the first ID, else the saved name.
local nameCache = {}
function Spells.MatchName(spell)
  local id = spell.ids and spell.ids[1]
  if id and nameCache[id] then return nameCache[id] end
  local n = id and Spells.NameOf(id)
  if n then nameCache[id] = n; return n end
  return spell.name
end
function Spells.ClearCache() nameCache = {}; iconCache = {} end

-- Does a cast (spellID and/or name, either may be nil) match this spell?
function Spells.Matches(id, spell, name)
  if type(id) == "number" and spell.ids then
    for _, v in ipairs(spell.ids) do
      if v == id then return true end
    end
  end
  if name == nil and type(id) == "number" then name = Spells.NameOf(id) end
  if type(name) == "string" and name ~= "" then
    return name == Spells.MatchName(spell)
  end
  return false
end

-- First enabled tracked spell matching the cast, or nil.
function Spells.Find(spells, id, name)
  for _, s in pairs(spells) do
    if type(s) == "table" and s.enabled and Spells.Matches(id, s, name) then return s end
  end
  return nil
end

-- Find a tracked spell by key, name or ID typed by the user.
function Spells.Lookup(spells, text)
  if not text or text == "" then return nil end
  local key = ns.KeyFor(text)
  if spells[key] then return spells[key] end
  local num = tonumber(text)
  for _, s in pairs(spells) do
    if type(s) == "table" then
      if ns.KeyFor(s.name or "") == key then return s end
      if num then
        for _, v in ipairs(s.ids or {}) do if v == num then return s end end
      end
    end
  end
  return nil
end

-- Resolve a spell name or ID typed by the user into (id, name).
function Spells.Resolve(nameOrID)
  local num = tonumber(nameOrID)
  local query = num or nameOrID
  local info = C_Spell and C_Spell.GetSpellInfo and ns.safe(C_Spell.GetSpellInfo, query)
  if type(info) == "table" and not ns.isSecret(info) then
    local id = ns.field(info, "spellID", "number")
    local name = ns.field(info, "name", "string")
    if id and name then return id, name end
  end
  if GetSpellInfo then
    local name, _, _, _, _, _, id = ns.safe(GetSpellInfo, query)
    name, id = ns.plain(name, "string"), ns.plain(id, "number")
    if id and name then return id, name end
  end
  if num then return num, Spells.NameOf(num) end
  -- Not resolvable from the client: fall back to a preset with that name.
  local key = ns.KeyFor(nameOrID)
  for _, p in pairs(Spells.presets) do
    if ns.KeyFor(p.name) == key then return p.ids[1], p.name end
  end
  return nil
end

-- Class that can cast a spell, if a preset knows it.
function Spells.PresetFor(id, name)
  for key, p in pairs(Spells.presets) do
    for _, v in ipairs(p.ids) do if v == id then return key, p end end
    if name and ns.KeyFor(name) == key then return key, p end
  end
  return nil
end

-- Where Cooldown(spell) gets its value: "override" | "base" | "preset" | "unknown".
function Spells.CooldownSource(spell)
  if type(spell.cdOverride) == "number" and spell.cdOverride > 0 then return "override" end
  if GetSpellBaseCooldown and spell.ids then
    for _, id in ipairs(spell.ids) do
      local ms = ns.plain(ns.safe(GetSpellBaseCooldown, id), "number")
      if ms and ms > 0 then return "base" end
    end
  end
  if type(spell.cd) == "number" and spell.cd > 0 then return "preset" end
  return "unknown"
end

-- Spells in panel order.
function Spells.Sorted(spells)
  local list, seen = {}, {}
  for _, key in ipairs(Spells.ORDER) do
    if type(spells[key]) == "table" then list[#list + 1] = spells[key]; seen[key] = true end
  end
  local rest = {}
  for key, s in pairs(spells) do
    if type(s) == "table" and not seen[key] then rest[#rest + 1] = s end
  end
  table.sort(rest, function(a, b) return (a.name or a.key) < (b.name or b.key) end)
  for _, s in ipairs(rest) do list[#list + 1] = s end
  return list
end

-- Cooldown length in seconds: user override, else client base cooldown, else preset, else 0.
local warned = {}
function Spells.Cooldown(spell)
  if type(spell.cdOverride) == "number" and spell.cdOverride > 0 then return spell.cdOverride end
  if GetSpellBaseCooldown and spell.ids then
    for _, id in ipairs(spell.ids) do
      local ms = ns.plain(ns.safe(GetSpellBaseCooldown, id), "number")
      if ms and ms > 0 then return ms / 1000 end
    end
  end
  if type(spell.cd) == "number" and spell.cd > 0 then return spell.cd end
  if not warned[spell.key or spell.name] then
    warned[spell.key or spell.name] = true
    ns.Print(("No cooldown length known for %s. Set one with /fcds cd %s <seconds>."):format(
      tostring(spell.name), tostring(spell.key or spell.name)))
  end
  return 0
end
