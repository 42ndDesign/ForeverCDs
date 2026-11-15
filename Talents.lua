-- ForeverCDs: talent checks for spells marked talent = true (Mana Tide Totem,
-- Power Infusion). Forever stores talents as a trait tree; other players are
-- read through NotifyInspect + INSPECT_READY, which needs no click and works
-- out of combat within inspect range. No UI code here (tested offline).
--
-- Has(guid, spell) answers true / false / nil. nil means "not checked yet":
-- the spell stays shown as assumed ready until an inspect says otherwise.
local _, ns = ...
local TL = {}
ns.Talents = TL

TL.INTERVAL = 2      -- seconds between our inspect requests
TL.TIMEOUT = 4       -- give up on a request after this long (out of range, etc.)
TL.RETRY = 20        -- wait this long before retrying someone who timed out
TL.STALE = 1800      -- re-inspect after 30 minutes (wall clock)
TL.KEEP = 7 * 86400  -- forget players not seen for a week

TL.pending = nil     -- { guid, unit, t } for our outstanding request
TL.failed = {}       -- [guid] = Now() of the last failed attempt
TL.tries = {}        -- [guid] = failed attempts in a row; the wait doubles each time
TL.last = -100       -- Now() of our last request

local function cache()
  if not ns.db then return {} end
  if type(ns.db.talents) ~= "table" then ns.db.talents = {} end
  return ns.db.talents
end
TL.Cache = cache

local function fail(guid, now)
  TL.failed[guid] = now
  TL.tries[guid] = (TL.tries[guid] or 0) + 1
end

local function backoff(guid)
  return math.min(TL.RETRY * 2 ^ ((TL.tries[guid] or 1) - 1), TL.STALE)
end

function TL.Enabled()
  return not ns.db or ns.db.talentCheck ~= false
end

-- Classes that have an enabled talent spell, as a set.
function TL.NeededClasses()
  local set, any = {}, false
  for _, s in pairs((ns.db and ns.db.spells) or {}) do
    if type(s) == "table" and s.enabled and s.talent and s.class then set[s.class] = true; any = true end
  end
  return set, any
end

---------------------------------------------------------------------------
-- Reading a trait config
---------------------------------------------------------------------------
-- Purchased talents of a trait config as { names = {[name]=rank}, ids = {[spellID]=rank}, n, complete },
-- or nil when nothing could be read. complete is false when any tree, node, rank or
-- purchased talent could not be read, or when no talent at all was found (the data
-- is often not loaded yet): such a result proves what it found, never an absence.
function TL.ReadConfig(configID)
  if not configID or not C_Traits then return nil end
  local cfg = ns.safe(C_Traits.GetConfigInfo, configID)
  local trees = ns.field(cfg, "treeIDs", "table")
  if not trees then return nil end
  local res, readable, complete = { names = {}, ids = {}, n = 0 }, 0, true
  for _, treeID in ipairs(trees) do
    local nodes = ns.safe(C_Traits.GetTreeNodes, treeID)
    if type(nodes) == "table" and not ns.isSecret(nodes) then
      for _, nodeID in ipairs(nodes) do
        local info = ns.safe(C_Traits.GetNodeInfo, configID, nodeID)
        local ranks = ns.field(info, "ranksPurchased", "number") or ns.field(info, "currentRank", "number")
        if not ranks then
          complete = false
        else
          readable = readable + 1
          local active = ns.field(info, "activeEntry", "table")
          local entryID = active and ns.field(active, "entryID", "number")
          if ranks > 0 and entryID then
            local e = ns.safe(C_Traits.GetEntryInfo, configID, entryID)
            local defID = ns.field(e, "definitionID", "number")
            local d = defID and ns.safe(C_Traits.GetDefinitionInfo, defID)
            local sid = ns.field(d, "spellID", "number") or ns.field(d, "overriddenSpellID", "number")
            local name = ns.field(d, "overrideName", "string") or (sid and ns.Spells.NameOf(sid))
            if sid then res.ids[sid] = ranks end
            if name then res.names[name] = ranks end
            if sid or name then res.n = res.n + 1 else complete = false end
          elseif ranks > 0 then
            complete = false
          end
        end
      end
    else
      complete = false
    end
  end
  if readable == 0 then return nil end
  res.complete = complete and res.n > 0
  return res
end

local function store(guid, res, spec)
  local c = cache()
  local old = c[guid]
  local e = { t = ns.Wall(), names = res.names, ids = res.ids, n = res.n, spec = spec, complete = res.complete }
  if not res.complete then
    -- Keep cast proof and retry soon; this read cannot rule anything out.
    e.forced = old and old.forced
    e.dirty = true
  end
  c[guid] = e
  -- Report a change only when a tracked talent answer flips.
  if not old then return true end
  for _, s in pairs((ns.db and ns.db.spells) or {}) do
    if type(s) == "table" and s.talent then
      local a = TL.HasIn(old, s)
      local b = TL.HasIn(c[guid], s)
      if a ~= b then return true end
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Answers
---------------------------------------------------------------------------
function TL.HasIn(entry, spell)
  if type(entry) ~= "table" then return nil end
  if entry.forced and entry.forced[spell.key] then return true end
  local ids, names = entry.ids or {}, entry.names or {}
  for _, id in ipairs(spell.ids or {}) do if ids[id] then return true end end
  local n = ns.Spells.MatchName(spell)
  if n and names[n] then return true end
  if spell.name and names[spell.name] then return true end
  -- Only a complete, current read says "no".
  if not entry.complete or entry.dirty then return nil end
  if (entry.t or 0) == 0 or ns.Wall() - entry.t > TL.STALE then return nil end
  return false
end

-- true / false / nil (unknown) for a talent spell; true for anything else.
function TL.Has(guid, spell)
  if not spell.talent then return true end
  if not TL.Enabled() then return nil end
  local c = cache()[guid]
  local r = TL.HasIn(c, spell)
  if r then return true end
  -- Our own spellbook is authoritative when it says yes.
  if guid == ns.Tracker.playerGUID and IsPlayerSpell then
    for _, id in ipairs(spell.ids or {}) do
      if ns.plain(ns.safe(IsPlayerSpell, id), "boolean") then return true end
    end
  end
  return r
end

-- Status text for tooltips and /fcds talents.
function TL.Describe(guid, spell)
  local h = TL.Has(guid, spell)
  if h == true then return "has the talent" end
  if h == false then return "no talent" end
  if TL.pending and TL.pending.guid == guid then return "checking..." end
  return "not checked yet"
end

-- A seen cast proves the talent; keep it until the next inspect.
function TL.NoteCast(guid, spell)
  if not spell.talent or not guid then return end
  local c = cache()
  local e = c[guid]
  if not e then e = { t = 0, names = {}, ids = {}, n = 0 }; c[guid] = e end
  e.forced = e.forced or {}
  e.cast = ns.Wall()
  if not e.forced[spell.key] then
    e.forced[spell.key] = true
    e.dirty = true
  end
end

function TL.MarkDirty(guid)
  local e = guid and cache()[guid]
  if e then e.dirty = true end
end

---------------------------------------------------------------------------
-- The player
---------------------------------------------------------------------------
function TL.ReadSelf()
  local me = ns.Tracker.playerGUID or ns.UnitGUIDSafe("player")
  if not me or not C_ClassTalents then return false end
  local cid = ns.plain(ns.safe(C_ClassTalents.GetActiveConfigID), "number")
  local res = cid and TL.ReadConfig(cid)
  if not res then return false end
  local changed = store(me, res, ns.plain(ns.safe(GetSpecialization), "number"))
  if changed and ns.Tracker.onChange then ns.Tracker.onChange() end
  return true
end

---------------------------------------------------------------------------
-- Inspect queue
---------------------------------------------------------------------------
local function busy()
  if ns.plain(ns.safe(InCombatLockdown), "boolean") then return true end
  -- Never step on the player's own inspecting.
  if InspectFrame and ns.plain(ns.safe(InspectFrame.IsShown, InspectFrame), "boolean") then return true end
  if TL.paused and ns.Now() < TL.paused then return true end
  return false
end

-- Next roster member to inspect, or nil.
function TL.NextTarget(now, wall)
  local need, any = TL.NeededClasses()
  if not any then return nil end
  local c = cache()
  local best, bestScore
  for guid, m in pairs(ns.roster) do
    if guid ~= ns.Tracker.playerGUID and m.unit and m.online ~= false and need[m.class]
      and not (TL.failed[guid] and now - TL.failed[guid] < backoff(guid)) then
      local e = c[guid]
      local score
      if not e or (e.t or 0) == 0 then score = 3
      elseif e.dirty then score = 2
      elseif wall - (e.t or 0) > TL.STALE then score = 1 end
      if score and (not bestScore or score > bestScore) then
        local can = ns.safe(CanInspect, m.unit)
        if ns.isSecret(can) or can ~= false then
          local near = CheckInteractDistance and ns.safe(CheckInteractDistance, m.unit, 1)
          if ns.isSecret(near) or near ~= false then best, bestScore = guid, score end
        end
      end
    end
  end
  return best
end

function TL.Tick()
  if not TL.Enabled() or not NotifyInspect then return end
  local now = ns.Now()
  if TL.pending then
    if now - TL.pending.t < TL.TIMEOUT then return end
    fail(TL.pending.guid, now)
    TL.pending = nil
  end
  if now - TL.last < TL.INTERVAL or busy() then return end
  local guid = TL.NextTarget(now, ns.Wall())
  if not guid then return end
  local unit = ns.roster[guid].unit
  TL.pending = { guid = guid, unit = unit, t = now }
  TL.last = now
  ns.safe(NotifyInspect, unit)
end

-- INSPECT_READY for anyone in the group is used, whoever asked for it.
function TL.OnInspectReady(guid)
  if ns.isSecret(guid) or guid == nil then return end
  local ours = TL.pending and TL.pending.guid == guid
  if ours then TL.pending = nil end
  local m = ns.roster[guid]
  if m and guid ~= ns.Tracker.playerGUID and TL.Enabled() then
    local cid = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
    local res = TL.ReadConfig(cid or -1)
    if not res or not res.complete then
      -- Unreadable or partial: back off like a timeout, or the queue picks them again at once.
      fail(guid, ns.Now())
    else
      TL.failed[guid], TL.tries[guid] = nil, nil
    end
    if res then
      local spec = m.unit and ns.plain(ns.safe(GetInspectSpecialization, m.unit), "number")
      if store(guid, res, spec) and ns.Tracker.onChange then ns.Tracker.onChange() end
    end
  end
  if ours and not busy() then ns.safe(ClearInspectPlayer) end
end

-- Drop entries not inspected or seen casting for KEEP at login. Entries saved
-- before the complete flag existed are re-checked.
function TL.Prune(wall)
  local c = cache()
  for guid, e in pairs(c) do
    local age = type(e) == "table" and ((e.t or 0) > 0 and e.t or e.cast or 0)
    if type(e) ~= "table" or wall - age > TL.KEEP then c[guid] = nil
    elseif e.complete == nil and (e.t or 0) > 0 then e.dirty = true end
  end
end

function TL.Start()
  TL.Prune(ns.Wall())
  TL.ReadSelf()
  if C_Timer and C_Timer.NewTicker and not TL.ticker then
    TL.ticker = C_Timer.NewTicker(1, function() ns.safe(TL.Tick) end)
  end
end
