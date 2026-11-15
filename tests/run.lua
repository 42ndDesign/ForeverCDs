-- Offline tests for Spells.lua and Tracker.lua under Lua 5.1 with a stubbed WoW API.
-- Run from the repo root: lua tests/run.lua
local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function eq(a, b, msg)
  if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function near(a, b, tol, msg)
  if type(a) ~= "number" or math.abs(a - b) > (tol or 0.01) then
    error((msg or "") .. " expected ~" .. tostring(b) .. ", got " .. tostring(a), 2)
  end
end

---------------------------------------------------------------------------
-- WoW API stub
---------------------------------------------------------------------------
-- Any use of a secret other than issecretvalue, tostring or == raises, as in game.
local function boom() error("secret value used", 2) end
local SECRET = setmetatable({}, {
  __tostring = function() return "<secret>" end,
  __index = boom, __newindex = boom, __call = boom, __concat = boom, __len = boom,
  __lt = boom, __le = boom, __add = boom, __sub = boom, __mul = boom, __div = boom,
  __mod = boom, __pow = boom, __unm = boom,
})
local clock, wall = 1000, 1700000000
local units = {}      -- token -> { guid, name, class, level }
local raid = false
local auras = {}      -- token -> list of aura tables

function GetTime() return clock end
function time() return wall end
function issecretvalue(v) return v == SECRET end
function IsInRaid() return raid end
function IsInGroup() return raid or units.party1 ~= nil end
function GetNumGroupMembers() local n = 0; for k in pairs(units) do if k:match("^raid") then n = n + 1 end end; return n end
function GetNumSubgroupMembers() local n = 0; for k in pairs(units) do if k:match("^party") then n = n + 1 end end; return n end
function UnitGUID(u) return units[u] and units[u].guid end
function UnitName(u) return units[u] and units[u].name end
function UnitClass(u) local x = units[u]; if x then return x.class, x.class end end
function UnitLevel(u) return units[u] and units[u].level or 0 end
function UnitIsConnected(u) return units[u] and not units[u].offline end
function UnitIsDeadOrGhost(u) return units[u] and units[u].dead or false end
function IsPlayerSpell(id) return units.player and units.player.known and units.player.known[id] or false end
local spellNames = { [16190] = "Mana Tide Totem", [29166] = "Innervate", [20484] = "Rebirth", [99999] = "Innervate", [6346] = "Fear Ward" }
C_Spell = {
  GetSpellName = function(id) if id == SECRET then return SECRET end return spellNames[id] end,
  GetSpellCooldown = function() return nil end,
}
C_UnitAuras = { GetAuraDataByIndex = function(u, i) return auras[u] and auras[u][i] end }

local ns = {}
for _, f in ipairs({ "Util.lua", "Spells.lua", "Tracker.lua", "Talents.lua", "Sync.lua" }) do
  local chunk = assert(loadfile(f))
  chunk("ForeverCDs", ns)
end
ns.Print = function() end
local T, Spells = ns.Tracker, ns.Spells

local function freshDB()
  ns.db = { spells = {}, show = { self = true }, sync = true }
  Spells.FillPresets(ns.db.spells)
  Spells.ClearCache()
  T.Reset()
end

local function party(list)
  units = {}
  for token, u in pairs(list) do units[token] = u end
  raid = false
  T.RebuildRoster()
end

local ME = { guid = "Player-1-ME", name = "Me", class = "PRIEST", level = 60 }
local DRU = { guid = "Player-1-DRU", name = "Leaf", class = "DRUID", level = 60 }
local FERAL = { guid = "Player-1-FER", name = "Claw", class = "DRUID", level = 45 }
local LOW = { guid = "Player-1-LOW", name = "Sprout", class = "DRUID", level = 20 }

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------
test("default list tracks Innervate only", function()
  freshDB()
  local enabled = {}
  for k, s in pairs(ns.db.spells) do if s.enabled then enabled[#enabled + 1] = k end end
  eq(#enabled, 1); eq(enabled[1], "innervate")
end)

test("rank matching by id and by name", function()
  freshDB()
  local inn = ns.db.spells.innervate
  eq(Spells.Matches(29166, inn), true, "known id")
  eq(Spells.Matches(99999, inn), true, "unknown rank matched by name")
  eq(Spells.Matches(6346, inn), false, "other spell")
  eq(Spells.Matches(nil, inn, "Innervate"), true, "name only")
end)

test("presets never overwrite user edits", function()
  freshDB()
  ns.db.spells.innervate.cdOverride = 300
  ns.db.spells.innervate.enabled = false
  ns.db.spells.fearward.enabled = true
  Spells.FillPresets(ns.db.spells)
  eq(ns.db.spells.innervate.cdOverride, 300)
  eq(ns.db.spells.innervate.enabled, false)
  eq(ns.db.spells.fearward.enabled, true)
end)

test("cooldown length: override > base > preset", function()
  freshDB()
  local inn = ns.db.spells.innervate
  eq(Spells.Cooldown(inn), 360)
  GetSpellBaseCooldown = function() return 180000 end
  eq(Spells.Cooldown(inn), 180)
  inn.cdOverride = 200
  eq(Spells.Cooldown(inn), 200)
  GetSpellBaseCooldown = function() return SECRET end
  inn.cdOverride = nil
  eq(Spells.Cooldown(inn), 360, "secret base falls back to preset")
  GetSpellBaseCooldown = nil
end)

---------------------------------------------------------------------------
-- Roster and eligibility
---------------------------------------------------------------------------
test("every druid at minLevel shows, any spec", function()
  freshDB()
  party({ player = ME, party1 = DRU, party2 = FERAL, party3 = LOW })
  local list = T.Eligible(ns.db.spells.innervate)
  table.sort(list)
  eq(#list, 2)
  eq(list[1], DRU.guid); eq(list[2], FERAL.guid)
end)

test("raid roster uses raid tokens", function()
  freshDB()
  units = { player = ME, raid1 = ME, raid2 = DRU }
  raid = true
  T.RebuildRoster()
  eq(ns.roster[DRU.guid].unit, "raid2")
  eq(T.GUIDForUnit("player"), ME.guid)
end)

---------------------------------------------------------------------------
-- Casts and state transitions
---------------------------------------------------------------------------
test("assumed -> cooldown -> ready", function()
  freshDB()
  party({ player = ME, party1 = DRU })
  eq(T.GetState(DRU.guid, "innervate"), "assumed")
  T.OnCast("party1", "cast-1", 29166)
  local st, rem = T.GetState(DRU.guid, "innervate")
  eq(st, "cooldown"); near(rem, 360)
  clock = clock + 100
  st, rem = T.GetState(DRU.guid, "innervate")
  eq(st, "cooldown"); near(rem, 260)
  clock = clock + 261
  eq(T.GetState(DRU.guid, "innervate"), "ready")
end)

test("non-group tokens are ignored", function()
  freshDB()
  party({ player = ME, party1 = DRU })
  units.target = DRU
  T.OnCast("target", "c", 29166)
  eq(T.GetState(DRU.guid, "innervate"), "assumed")
end)

test("duplicate events within 0.75 s count once", function()
  freshDB()
  party({ player = ME, party1 = DRU })
  T.OnCast("party1", "c", 29166)
  local start = ns.cds[DRU.guid].innervate.start
  clock = clock + 0.5
  T.OnCast("party1", "c", 29166)
  eq(ns.cds[DRU.guid].innervate.start, start, "dedupe kept first")
  clock = clock + 1
  T.OnCast("party1", "c2", 29166)
  eq(ns.cds[DRU.guid].innervate.start, clock, "later cast replaces")
end)

test("secret spell id with secret name changes nothing", function()
  freshDB()
  party({ player = ME, party1 = DRU })
  T.OnCast("party1", "c", SECRET)
  eq(T.GetState(DRU.guid, "innervate"), "assumed")
end)

test("secret guid changes nothing", function()
  freshDB()
  party({ player = ME, party1 = DRU })
  T.unitGUID.party1 = nil
  local saved = UnitGUID
  UnitGUID = function() return SECRET end
  T.OnCast("party1", "c", 29166)
  UnitGUID = saved
  eq(T.GetState(DRU.guid, "innervate"), "assumed")
end)

test("disabled spells are not tracked", function()
  freshDB()
  party({ player = ME, party1 = DRU })
  T.OnCast("party1", "c", 20484)
  eq(ns.cds[DRU.guid], nil)
end)

test("dead or offline is unavailable, timer keeps running", function()
  freshDB()
  party({ player = ME, party1 = DRU })
  T.OnCast("party1", "c", 29166)
  DRU.dead = true
  T.RefreshAllStatus()
  local st, _, _, unavailable = T.GetState(DRU.guid, "innervate")
  eq(st, "cooldown"); eq(unavailable, true)
  DRU.dead = nil
end)

---------------------------------------------------------------------------
-- Source priority
---------------------------------------------------------------------------
test("aura only fills an empty slot", function()
  freshDB()
  party({ player = ME, party1 = DRU })
  auras.player = { { spellId = 29166, name = "Innervate", sourceUnit = "party1", expirationTime = clock + 15, duration = 20 } }
  T.ScanAuras("player")
  local rec = ns.cds[DRU.guid].innervate
  eq(rec.source, "aura"); near(rec.start, clock - 5)
  T.OnCast("party1", "c", 29166)
  eq(ns.cds[DRU.guid].innervate.source, "cast")
  T.ScanAuras("player")
  eq(ns.cds[DRU.guid].innervate.source, "cast", "aura did not replace cast")
  auras = {}
end)

test("secret aura fields are skipped", function()
  freshDB()
  party({ player = ME, party1 = DRU })
  auras.player = { { spellId = SECRET, name = SECRET, sourceUnit = "party1", expirationTime = clock + 15, duration = 20 } }
  T.ScanAuras("player")
  eq(ns.cds[DRU.guid], nil)
  auras = {}
end)

test("sync beats an assumption and an aura, never a cast", function()
  freshDB()
  party({ player = ME, party1 = DRU })
  eq(T.OnSync(DRU.guid, "innervate", 100), true)
  eq(ns.cds[DRU.guid].innervate.source, "sync")
  near(select(2, T.GetState(DRU.guid, "innervate")), 100)
  clock = clock + 1
  T.OnCast("party1", "c", 29166)
  eq(T.OnSync(DRU.guid, "innervate", 50), false)
  eq(ns.cds[DRU.guid].innervate.source, "cast")
end)

test("sync messages parse and validate", function()
  local key, rem = ns.Sync.Parse("C|innervate|120")
  eq(key, "innervate"); eq(rem, 120)
  eq(ns.Sync.Parse("C|innervate|-5"), nil)
  eq(ns.Sync.Parse("X|innervate|5"), nil)
  eq(ns.Sync.Parse("C|inn ervate|5"), nil)
end)

---------------------------------------------------------------------------
-- Own cooldown
---------------------------------------------------------------------------
test("own cooldown: GCD and secret ignored, real cooldown applied", function()
  freshDB()
  local meDru = { guid = "Player-1-ME", name = "Me", class = "DRUID", level = 60 }
  party({ player = meDru })
  local inn = ns.db.spells.innervate
  T.ApplySelfCooldown(meDru.guid, inn, { startTime = clock, duration = 1.5, isOnGCD = true }, clock)
  eq(ns.cds[meDru.guid], nil, "gcd ignored")
  T.ApplySelfCooldown(meDru.guid, inn, SECRET, clock)
  eq(ns.cds[meDru.guid], nil, "secret ignored")
  T.ApplySelfCooldown(meDru.guid, inn, { startTime = clock - 10, duration = 360, isOnGCD = false }, clock)
  eq(ns.cds[meDru.guid].innervate.source, "self")
  near(select(2, T.GetState(meDru.guid, "innervate")), 350)
  -- client says ready: confirmed ready
  T.ApplySelfCooldown(meDru.guid, inn, { startTime = 0, duration = 0, isOnGCD = false }, clock + 5)
  eq(T.GetState(meDru.guid, "innervate", clock + 5), "ready")
end)

test("own client 'no cooldown' right after a cast is ignored", function()
  freshDB()
  local meDru = { guid = "Player-1-ME", name = "Me", class = "DRUID", level = 60 }
  party({ player = meDru })
  T.OnCast("player", "c", 29166)
  T.ApplySelfCooldown(meDru.guid, ns.db.spells.innervate, { startTime = 0, duration = 0 }, clock + 0.2)
  eq(T.GetState(meDru.guid, "innervate"), "cooldown")
end)

---------------------------------------------------------------------------
-- Persistence and leaving the group
---------------------------------------------------------------------------
test("persistence round trip across sessions", function()
  freshDB()
  party({ player = ME, party1 = DRU })
  T.OnCast("party1", "c", 29166)
  clock = clock + 60
  local db = {}
  T.Save(db)
  near(db.saved[DRU.guid].innervate.endsAt, wall + 300)
  -- New session: GetTime restarts, wall clock moves 100 s.
  T.Reset()
  clock, wall = 50, wall + 100
  T.Restore(db)
  party({ player = ME, party1 = DRU })
  local st, rem = T.GetState(DRU.guid, "innervate")
  eq(st, "cooldown"); near(rem, 200)
end)

test("expired saved records are dropped", function()
  freshDB()
  local db = { saved = { [DRU.guid] = { innervate = { endsAt = wall - 1, duration = 360, source = "cast" } } } }
  T.Restore(db)
  eq(ns.cds[DRU.guid], nil)
end)

test("a departed player's running cooldown outlives the 30-minute retention", function()
  freshDB()
  ns.db.spells.layonhands.enabled = true
  local PAL = { guid = "Player-1-PAL", name = "Holy", class = "PALADIN", level = 60 }
  party({ player = ME, party1 = PAL })
  T.Start(PAL.guid, "layonhands", clock, 3600, "cast")
  party({ player = ME })
  clock = clock + 1801
  T.RebuildRoster()
  eq(ns.cds[PAL.guid] ~= nil, true, "still running, kept")
  party({ player = ME, party1 = PAL })
  local st, rem = T.GetState(PAL.guid, "layonhands")
  eq(st, "cooldown"); near(rem, 1799)
  party({ player = ME })
  clock = clock + 1801
  T.RebuildRoster()
  eq(ns.cds[PAL.guid], nil, "purged once expired and past retention")
end)

test("sync sender: full name wins, an ambiguous short name matches nobody", function()
  freshDB()
  local A = { guid = "Player-1-A", name = "Bob", class = "DRUID", level = 60 }
  local B = { guid = "Player-2-B", name = "Bob", class = "DRUID", level = 60 }
  party({ player = ME, party1 = A, party2 = B })
  ns.roster[B.guid].fullName = "Bob-Other"
  eq(T.GUIDByName("Bob"), A.guid, "same-realm full name")
  eq(T.GUIDByName("Bob-Other"), B.guid, "cross-realm full name")
  eq(T.GUIDByName("Bob-Third"), nil, "short name shared by two")
  eq(T.GUIDByName("Leaf-Elsewhere"), nil, "not grouped")
end)

test("sync rejects oversized numbers before formatting", function()
  eq(ns.Sync.Parse("C|innervate|7200"), "innervate")
  eq(ns.Sync.Parse("C|innervate|7201"), nil)
  eq(ns.Sync.Parse("C|innervate|99999999999999999999"), nil)
  freshDB()
  party({ player = ME, party1 = DRU })
  ns.Sync.OnMessage("FCDS", "C|innervate|99999999999999999999", "PARTY", "Leaf")
  eq(ns.cds[DRU.guid], nil)
  ns.Sync.OnMessage("FCDS", "C|innervate|100", "PARTY", "Leaf")
  near(select(2, T.GetState(DRU.guid, "innervate")), 100)
end)

test("records kept 30 minutes after leaving", function()
  freshDB()
  party({ player = ME, party1 = DRU })
  T.OnCast("party1", "c", 29166)
  party({ player = ME })
  eq(ns.roster[DRU.guid], nil)
  T.RebuildRoster()
  eq(ns.cds[DRU.guid] ~= nil, true, "kept")
  clock = clock + 1801
  T.RebuildRoster()
  eq(ns.cds[DRU.guid], nil, "purged")
end)

test("spell icon from C_Spell.GetSpellTexture's two return values", function()
  freshDB()
  local saved = C_Spell.GetSpellTexture
  C_Spell.GetSpellTexture = function(id) return 136048, 136048 end   -- iconID, originalIconID
  eq(Spells.IconOf(ns.db.spells.innervate), 136048)
  C_Spell.GetSpellTexture = saved
  Spells.ClearCache()
end)

test("panel order and cooldown source", function()
  freshDB()
  ns.db.spells.zzcustom = { key = "zzcustom", name = "Aaa Custom", class = "MAGE", ids = { 1 }, cd = 10 }
  local list = Spells.Sorted(ns.db.spells)
  eq(list[1].key, "innervate"); eq(list[#list].key, "zzcustom")
  eq(Spells.CooldownSource(ns.db.spells.innervate), "preset")
  ns.db.spells.innervate.cdOverride = 100
  eq(Spells.CooldownSource(ns.db.spells.innervate), "override")
  eq(ns.db.spells.powerinfusion.talent, true)
end)

test("time text", function()
  eq(ns.TimeText(125), "2:05")
  eq(ns.TimeText(59.2), "60")
  eq(ns.TimeText(9.1), "10")
  eq(ns.TimeText(0), "")
end)

---------------------------------------------------------------------------
-- Talents
---------------------------------------------------------------------------
-- Stub trait API: inspectTalents[guid] = { {spellID, name, ranks}, ... }
local inspectTalents, inspected = {}, nil
local notified = {}
Constants = { TraitConsts = { INSPECT_TRAIT_CONFIG_ID = -1 } }
C_Traits = {
  GetConfigInfo = function(cid) return { treeIDs = { 1 } } end,
  GetTreeNodes = function() local t = {}; for i = 1, #(inspectTalents[inspected] or {}) do t[i] = i end; t[#t + 1] = 99; return t end,
  GetNodeInfo = function(cid, node)
    local x = (inspectTalents[inspected] or {})[node]
    if not x then return { ranksPurchased = 0 } end
    return { ranksPurchased = x[3] or 1, activeEntry = { entryID = node } }
  end,
  GetEntryInfo = function(cid, entry) return { definitionID = entry } end,
  GetDefinitionInfo = function(def) local x = inspectTalents[inspected][def]; return { spellID = x[1], overrideName = x[2] } end,
}
function NotifyInspect(u) notified[#notified + 1] = u end
function CanInspect() return true end
function ClearInspectPlayer() end
function InCombatLockdown() return false end
local TL = ns.Talents

local SHA = { guid = "Player-1-SHA", name = "Tide", class = "SHAMAN", level = 60 }
local SHB = { guid = "Player-1-SHB", name = "Storm", class = "SHAMAN", level = 60 }

local function talentDB()
  freshDB()
  ns.db.spells.manatidetotem.enabled = true
  ns.db.talents = {}
  TL.pending, TL.failed, TL.tries, TL.last, TL.paused = nil, {}, {}, -100, nil
  notified = {}
end

test("unchecked talent players stay listed", function()
  talentDB()
  party({ player = ME, party1 = SHA, party2 = SHB })
  eq(#T.Eligible(ns.db.spells.manatidetotem), 2)
  eq(TL.Has(SHA.guid, ns.db.spells.manatidetotem), nil)
end)

test("inspect queue requests, reads, hides players without the talent", function()
  talentDB()
  party({ player = ME, party1 = SHA, party2 = SHB })
  inspectTalents[SHA.guid] = { { 16190, "Mana Tide Totem" }, { 16180, "Healing Grace", 3 } }
  inspectTalents[SHB.guid] = { { 17364, "Stormstrike" } }
  TL.Tick()
  eq(#notified, 1, "one request")
  local first = TL.pending.guid
  TL.Tick()
  eq(#notified, 1, "waits for the reply")
  inspected = first; TL.OnInspectReady(first)
  eq(TL.pending, nil)
  clock = clock + 2.1
  TL.Tick()
  eq(#notified, 2, "second request after the interval")
  local second = TL.pending.guid
  inspected = second; TL.OnInspectReady(second)
  local mt = ns.db.spells.manatidetotem
  eq(TL.Has(SHA.guid, mt), true)
  eq(TL.Has(SHB.guid, mt), false)
  local list = T.Eligible(mt)
  eq(#list, 1); eq(list[1], SHA.guid)
  clock = clock + 2.1
  TL.Tick()
  eq(#notified, 2, "nothing left to inspect")
end)

test("talent match by name when the ID differs", function()
  talentDB()
  party({ player = ME, party1 = SHA })
  inspectTalents[SHA.guid] = { { 1234567, "Mana Tide Totem" } }
  TL.Tick(); inspected = SHA.guid; TL.OnInspectReady(SHA.guid)
  eq(TL.Has(SHA.guid, ns.db.spells.manatidetotem), true)
end)

test("no inspects in combat; timeouts back off", function()
  talentDB()
  party({ player = ME, party1 = SHA })
  InCombatLockdown = function() return true end
  TL.Tick()
  eq(#notified, 0, "combat")
  InCombatLockdown = function() return false end
  TL.Tick()
  eq(#notified, 1)
  clock = clock + 5
  TL.Tick()   -- times out
  eq(TL.pending, nil); eq(TL.failed[SHA.guid] ~= nil, true)
  clock = clock + 3
  TL.Tick()
  eq(#notified, 1, "backing off")
  clock = clock + 20
  TL.Tick()
  eq(#notified, 2, "retried")
end)

test("a seen cast proves the talent", function()
  talentDB()
  party({ player = ME, party1 = SHB })
  inspectTalents[SHB.guid] = { { 17364, "Stormstrike" } }
  TL.Tick(); inspected = SHB.guid; TL.OnInspectReady(SHB.guid)
  local mt = ns.db.spells.manatidetotem
  eq(#T.Eligible(mt), 0)
  T.OnCast("party1", "c", 16190)
  eq(TL.Has(SHB.guid, mt), true)
  eq(#T.Eligible(mt), 1)
end)

test("an expired record does not override a negative inspect", function()
  talentDB()
  party({ player = ME, party1 = SHB })
  inspectTalents[SHB.guid] = { { 17364, "Stormstrike" } }
  local mt = ns.db.spells.manatidetotem
  T.Start(SHB.guid, "manatidetotem", clock, 300, "sync")
  TL.Tick(); inspected = SHB.guid; TL.OnInspectReady(SHB.guid)
  eq(#T.Eligible(mt), 1, "running cooldown still shows")
  clock = clock + 301
  eq(#T.Eligible(mt), 0, "hidden once it has run out")
end)

test("a partial inspect never hides a player", function()
  talentDB()
  party({ player = ME, party1 = SHA })
  local mt = ns.db.spells.manatidetotem
  inspectTalents[SHA.guid] = { { 17364, "Stormstrike" } }
  local saved = C_Traits.GetNodeInfo
  C_Traits.GetNodeInfo = function(cid, node)
    if node == 99 then return { ranksPurchased = SECRET } end
    return saved(cid, node)
  end
  TL.Tick(); inspected = SHA.guid; TL.OnInspectReady(SHA.guid)
  C_Traits.GetNodeInfo = saved
  eq(TL.Has(SHA.guid, mt), nil, "unknown, not false")
  eq(#T.Eligible(mt), 1)
  eq(TL.failed[SHA.guid] ~= nil, true, "retried later")
end)

test("an inspect with no talents found is not a negative", function()
  talentDB()
  party({ player = ME, party1 = SHA })
  inspectTalents[SHA.guid] = {}
  TL.Tick(); inspected = SHA.guid; TL.OnInspectReady(SHA.guid)
  eq(TL.Has(SHA.guid, ns.db.spells.manatidetotem), nil)
end)

test("an unreadable inspect reply backs off instead of looping", function()
  talentDB()
  party({ player = ME, party1 = SHA, party2 = SHB })
  inspectTalents[SHB.guid] = { { 17364, "Stormstrike" } }
  local saved = C_Traits.GetConfigInfo
  C_Traits.GetConfigInfo = function() if inspected == SHA.guid then return nil end return saved() end
  local seen = {}
  for _ = 1, 4 do
    TL.Tick()
    local g = TL.pending and TL.pending.guid
    if g then seen[g] = (seen[g] or 0) + 1; inspected = g; TL.OnInspectReady(g) end
    clock = clock + 2.1
  end
  C_Traits.GetConfigInfo = saved
  eq(seen[SHA.guid], 1, "unreadable player asked once")
  eq(seen[SHB.guid], 1, "other player got their turn")
  eq(TL.tries[SHA.guid], 1)
end)

test("stale or dirty negatives become unknown", function()
  talentDB()
  party({ player = ME, party1 = SHB })
  inspectTalents[SHB.guid] = { { 17364, "Stormstrike" } }
  local mt = ns.db.spells.manatidetotem
  TL.Tick(); inspected = SHB.guid; TL.OnInspectReady(SHB.guid)
  eq(TL.Has(SHB.guid, mt), false)
  TL.MarkDirty(SHB.guid)
  eq(TL.Has(SHB.guid, mt), nil, "dirty")
  TL.Cache()[SHB.guid].dirty = nil
  wall = wall + TL.STALE + 1
  eq(TL.Has(SHB.guid, mt), nil, "stale")
end)

test("talent check off shows everyone", function()
  talentDB()
  party({ player = ME, party1 = SHB })
  inspectTalents[SHB.guid] = { { 17364, "Stormstrike" } }
  TL.Tick(); inspected = SHB.guid; TL.OnInspectReady(SHB.guid)
  ns.db.talentCheck = false
  eq(#T.Eligible(ns.db.spells.manatidetotem), 1)
end)

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
