-- ForeverCDs: roster and cooldown records. No UI code here, so this file can be
-- tested outside the game with a stubbed API (see tests/).
--
-- Sources only write records. A seen cast, the player's own client and a
-- member's own report (sync) rank the same, so the newest wins; an aura sighting
-- only fills an empty slot.
local _, ns = ...
local T = {}
ns.Tracker = T

ns.roster = {}       -- [guid] = { unit, name, fullName, class, level, online, dead }
ns.cds = {}          -- [guid][spellKey] = { start, duration, source }
T.unitGUID = {}      -- [unit] = guid
T.leftAt = {}        -- [guid] = GetTime() when they left the group
T.recent = {}        -- [guid .. key] = GetTime() of the last accepted cast
T.pendingCast = {}   -- [guid .. key] = { t, spell } for cast alerts waiting on a target
T.meterSeen = {}     -- [session .. guid .. key] = meter total last counted
T.hiddenCasts = {}   -- debug only: hidden casts from this fight, checked after it

T.DEDUPE = 0.75      -- same GUID + spell within this many seconds counts once
T.RETAIN = 1800      -- keep records of players who left for 30 minutes, or until their last cooldown ends
T.SELF_GRACE = 2     -- ignore "no cooldown" from our own client this soon after a cast

local RANK = { cast = 3, self = 3, sync = 3, aura = 1, meter = 1 }

local function spells() return (ns.db and ns.db.spells) or {} end

local function running(rec, now)
  return rec and rec.duration > 0 and (rec.start + rec.duration) > now
end

-- True while any of this player's records is still counting down.
local function anyRunning(list, now)
  for _, rec in pairs(list) do if running(rec, now) then return true end end
  return false
end

---------------------------------------------------------------------------
-- Roster
---------------------------------------------------------------------------
function T.GroupUnits()
  local units = {}
  local inRaid = ns.safe(IsInRaid)
  if not ns.isSecret(inRaid) and inRaid then
    local n = ns.plain(ns.safe(GetNumGroupMembers), "number") or 0
    for i = 1, math.min(n, 40) do units[#units + 1] = "raid" .. i end
  else
    units[1] = "player"
    local n = ns.plain(ns.safe(GetNumSubgroupMembers), "number") or 0
    for i = 1, math.min(n, 4) do units[#units + 1] = "party" .. i end
  end
  return units
end

local function readMember(unit, guid, old)
  local m = old or {}
  m.unit = unit
  local name, realm = ns.safe(UnitName, unit)
  name, realm = ns.plain(name, "string"), ns.plain(realm, "string")
  if name then
    m.name = name
    m.fullName = (realm and realm ~= "") and (name .. "-" .. realm) or name
  end
  local _, class = ns.safe(UnitClass, unit)
  class = ns.plain(class, "string")
  if class then m.class = class end
  local level = ns.plain(ns.safe(UnitLevel, unit), "number")
  if level and level > 0 then m.level = level end
  T.RefreshStatus(m)
  return m
end

-- Online / dead flags; unreadable values leave the old flag alone.
function T.RefreshStatus(m)
  local unit = m.unit
  local online = ns.plain(ns.safe(UnitIsConnected, unit), "boolean")
  if online ~= nil then m.online = online elseif m.online == nil then m.online = true end
  local dead = ns.plain(ns.safe(UnitIsDeadOrGhost, unit), "boolean")
  if dead ~= nil then m.dead = dead elseif m.dead == nil then m.dead = false end
end

function T.RefreshAllStatus()
  for _, m in pairs(ns.roster) do T.RefreshStatus(m) end
end

function T.RebuildRoster()
  local now = ns.Now()
  local seen, newUnitGUID = {}, {}
  for _, unit in ipairs(T.GroupUnits()) do
    local guid = ns.UnitGUIDSafe(unit)
    if guid then
      seen[guid] = true
      newUnitGUID[unit] = guid
      ns.roster[guid] = readMember(unit, guid, ns.roster[guid])
      T.leftAt[guid] = nil
    end
  end
  -- The player always maps, even in a raid where they are also raidN.
  local pg = ns.UnitGUIDSafe("player")
  if pg then newUnitGUID.player = pg; T.playerGUID = pg end
  T.unitGUID = newUnitGUID
  for guid in pairs(ns.roster) do
    if not seen[guid] then ns.roster[guid] = nil; T.leftAt[guid] = T.leftAt[guid] or now end
  end
  for guid in pairs(ns.cds) do
    if not seen[guid] then
      T.leftAt[guid] = T.leftAt[guid] or now
      if now - T.leftAt[guid] > T.RETAIN and not anyRunning(ns.cds[guid], now) then
        ns.cds[guid] = nil; T.leftAt[guid] = nil
      end
    end
  end
  if T.onChange then T.onChange() end
end

function T.GUIDForUnit(unit)
  return T.unitGUID[unit] or ns.UnitGUIDSafe(unit)
end

-- Find a roster GUID by player name ("Name" or "Name-Realm").
function T.GUIDByName(name)
  if type(name) ~= "string" then return nil end
  -- Exact full name first, then short name; a short name shared by two members matches neither.
  for guid, m in pairs(ns.roster) do
    if m.fullName == name then return guid end
  end
  local short = name:match("^([^%-]+)")
  local found
  for guid, m in pairs(ns.roster) do
    if m.name == name or m.name == short then
      if found then return nil end
      found = guid
    end
  end
  return found
end

-- A talent spell is hidden only when an inspect says the player lacks it;
-- unchecked players stay listed, and a running cooldown always shows.
local function talentOK(guid, spell)
  if not spell.talent or not ns.Talents then return true end
  if ns.Talents.Has(guid, spell) ~= false then return true end
  return running(ns.cds[guid] and ns.cds[guid][spell.key], ns.Now()) and true or false
end
T.TalentOK = talentOK

-- What the member's own ForeverCDs reports beats any guess: a member who says
-- they lack the spell is hidden (unless a cooldown is running), one who says they
-- have it is shown.
local function reportedOK(guid, spell)
  local known = ns.Sync and ns.Sync.Known and ns.Sync.Known(guid, spell.key)
  if known == nil then return nil end
  if known then return true end
  return running(ns.cds[guid] and ns.cds[guid][spell.key], ns.Now()) and true or false
end

-- Members who can cast this spell: class match, then their own report if they
-- sent one, else level >= minLevel (when known) and, for talent spells, not
-- known to lack the talent.
function T.Eligible(spell)
  local list = {}
  local showSelf = not ns.db or ns.db.show == nil or ns.db.show.self ~= false
  for guid, m in pairs(ns.roster) do
    if m.class == spell.class and (showSelf or guid ~= T.playerGUID) then
      local ok
      if guid ~= T.playerGUID then ok = reportedOK(guid, spell) end
      if ok == nil then
        ok = (not spell.minLevel or not m.level or m.level >= spell.minLevel) and talentOK(guid, spell)
      end
      if ok then list[#list + 1] = guid end
    end
  end
  return list
end

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------

-- Write a record if the source is allowed to replace what is there.
function T.Start(guid, key, start, duration, source)
  if not guid or not key or type(start) ~= "number" or type(duration) ~= "number" then return false end
  local now = ns.Now()
  ns.cds[guid] = ns.cds[guid] or {}
  local old = ns.cds[guid][key]
  if old and running(old, now) then
    local newRank, oldRank = RANK[source] or 0, RANK[old.source] or 0
    if newRank <= 1 then return false end                -- estimates only fill an empty slot
    if newRank < oldRank then return false end
  end
  ns.cds[guid][key] = { start = start, duration = duration, source = source }
  if T.onChange then T.onChange() end
  return true
end

-- State of one member/spell pair:
-- returns state ("ready" | "assumed" | "cooldown"), remaining seconds, record, unavailable
function T.GetState(guid, key, now)
  now = now or ns.Now()
  local rec = ns.cds[guid] and ns.cds[guid][key]
  local m = ns.roster[guid]
  local unavailable = m and (m.online == false or m.dead == true) or false
  if running(rec, now) then
    return "cooldown", rec.start + rec.duration - now, rec, unavailable
  elseif rec then
    return "ready", 0, rec, unavailable
  end
  return "assumed", 0, nil, unavailable
end

---------------------------------------------------------------------------
-- Source 1: group cast events (UNIT_SPELLCAST_SUCCEEDED)
---------------------------------------------------------------------------
function T.OnCast(unit, castGUID, spellID)
  local unitOK = ns.IsGroupUnit(unit)
  -- Target, focus, nameplates and pets fire this too; skip them before any lookup.
  if not unitOK and not ns.debug then return end
  local idSecret = ns.isSecret(spellID)
  local id = ns.plain(spellID, "number")
  local name, nameSecret
  if id then name = ns.Spells.NameOf(id)
  elseif idSecret and C_Spell and C_Spell.GetSpellName then
    local raw = ns.safe(C_Spell.GetSpellName, spellID)
    nameSecret = ns.isSecret(raw)
    name = ns.plain(raw, "string")
  end
  local guid = unitOK and T.GUIDForUnit(unit) or nil

  if ns.debug then
    local combat = ns.plain(ns.safe(UnitAffectingCombat, "player"), "boolean")
    ns.Debug(("cast unit=%s guid=%s id=%s name=%s combat=%s secret:%s%s%s%s"):format(
      ns.isSecret(unit) and "<secret>" or tostring(unit),
      tostring(guid or (unitOK and "<secret/nil>" or "-")),
      idSecret and "<secret>" or tostring(spellID),
      nameSecret and "<secret>" or tostring(name or "?"),
      combat == nil and "?" or (combat and "yes" or "no"),
      idSecret and " id" or "",
      nameSecret and " name" or "",
      ns.isSecret(castGUID) and " castGUID" or "",
      (unitOK and not guid) and " guid" or ""))
  end

  if not unitOK or not guid then return end
  if not id and not name then
    -- Debug test: does a hidden spell ID become readable once combat is over?
    if ns.debug and idSecret and #T.hiddenCasts < 20 then
      T.hiddenCasts[#T.hiddenCasts + 1] = { t = ns.Now(), guid = guid, id = spellID }
    end
    return
  end
  -- Our own casts count for every spell of our class: sync reports them all.
  local own = guid == T.playerGUID
  local spell = ns.Spells.Find(spells(), id, name, own and ns.roster[guid] and ns.roster[guid].class or nil)
  if not spell then return end

  local now = ns.Now()
  local dk = guid .. "\0" .. spell.key
  if T.recent[dk] and now - T.recent[dk] < T.DEDUPE then ns.Debug("  -> " .. spell.key .. ": repeat, ignored"); return end
  T.recent[dk] = now

  local duration = ns.Spells.Cooldown(spell)
  if duration <= 0 then ns.Debug("  -> " .. spell.key .. ": no cooldown length"); return end
  ns.Debug(("  -> tracked %s, %d s"):format(spell.key, duration))
  if ns.Talents then ns.Talents.NoteCast(guid, spell) end
  T.Start(guid, spell.key, now, duration, "cast")
  if spell.enabled then
    T.pendingCast[dk] = { t = now, guid = guid, spell = spell }
    if T.onCast then T.onCast(guid, spell) end
  end
  return spell
end

---------------------------------------------------------------------------
-- Source 2: the player's own cooldowns
---------------------------------------------------------------------------
function T.PollSelf()
  local me = T.playerGUID or ns.UnitGUIDSafe("player")
  if not me or not C_Spell or not C_Spell.GetSpellCooldown then return end
  local m = ns.roster[me]
  local _, myClass = ns.safe(UnitClass, "player")
  myClass = ns.plain(myClass, "string") or (m and m.class)
  local now = ns.Now()
  for key, spell in pairs(spells()) do
    if type(spell) == "table" and spell.class == myClass then
      for _, id in ipairs(spell.ids or {}) do
        local known = ns.safe(IsPlayerSpell, id)
        if known == nil and IsSpellKnown then known = ns.safe(IsSpellKnown, id) end
        if ns.plain(known, "boolean") then
          T.ApplySelfCooldown(me, spell, ns.safe(C_Spell.GetSpellCooldown, id), now)
          break
        end
      end
    end
  end
end

-- info = C_Spell.GetSpellCooldown result. Secret or GCD-only results are ignored.
function T.ApplySelfCooldown(me, spell, info, now)
  if type(info) ~= "table" or ns.isSecret(info) then return end
  local start = ns.field(info, "startTime", "number")
  local duration = ns.field(info, "duration", "number")
  if not start or not duration then return end
  local onGCD = ns.field(info, "isOnGCD")
  if onGCD == true then return end
  local cur = ns.cds[me] and ns.cds[me][spell.key]
  if duration <= 0 then
    -- Client says ready. Trust it unless we only just saw the cast.
    if cur and running(cur, now) and now - cur.start < T.SELF_GRACE then return end
    if not cur or running(cur, now) then
      ns.cds[me] = ns.cds[me] or {}
      ns.cds[me][spell.key] = { start = now, duration = 0, source = "self" }
      if T.onChange then T.onChange() end
    end
    return
  end
  if duration <= 1.5 then return end
  if cur and running(cur, now) and math.abs(cur.start - start) < 0.5 and math.abs(cur.duration - duration) < 0.5 then
    return
  end
  T.Start(me, spell.key, start, duration, "self")
end

---------------------------------------------------------------------------
-- Source 3: buff sighting (UNIT_AURA)
---------------------------------------------------------------------------
function T.ScanAuras(unit)
  if not ns.IsGroupUnit(unit) then return end
  if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return end
  local targetGUID = T.GUIDForUnit(unit)
  local now = ns.Now()
  local hidden = ns.debug and {} or nil
  for i = 1, 40 do
    local aura = ns.safe(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
    if ns.isSecret(aura) then if hidden then hidden[#hidden + 1] = i .. ":aura" end break end
    if type(aura) ~= "table" then break end
    local id = ns.field(aura, "spellId", "number")
    local name = ns.field(aura, "name", "string")
    if hidden then
      local f = ""
      for _, k in ipairs({ "spellId", "name", "sourceUnit", "expirationTime", "duration" }) do
        local ok, v = pcall(function() return aura[k] end)
        if ok and ns.isSecret(v) then f = f .. "," .. k end
      end
      if f ~= "" then hidden[#hidden + 1] = i .. ":" .. f:sub(2) end
    end
    local spell = (id or name) and ns.Spells.Find(spells(), id, name)
    if spell then
      local srcUnit = ns.field(aura, "sourceUnit", "string")
      local srcGUID = srcUnit and ns.UnitGUIDSafe(srcUnit)
      if srcGUID and ns.roster[srcGUID] then
        local expires = ns.field(aura, "expirationTime", "number")
        local dur = ns.field(aura, "duration", "number")
        if expires and dur and dur > 0 then
          local cd = ns.Spells.Cooldown(spell)
          if cd > 0 then T.Start(srcGUID, spell.key, expires - dur, cd, "aura") end
        end
        local p = T.pendingCast[srcGUID .. "\0" .. spell.key]
        if p and not p.target and now - p.t < 2 then
          local m = targetGUID and ns.roster[targetGUID]
          p.target = (m and m.name) or ns.plain(ns.safe(UnitName, unit), "string")
        end
      end
    end
  end
  -- Debug: which buff fields this client hides, at most once per unit every 5 s.
  if hidden and #hidden > 0 then
    T.auraLogged = T.auraLogged or {}
    if not T.auraLogged[unit] or now - T.auraLogged[unit] >= 5 then
      T.auraLogged[unit] = now
      local combat = ns.plain(ns.safe(UnitAffectingCombat, "player"), "boolean")
      ns.Debug(("aura unit=%s combat=%s hidden %s"):format(unit,
        combat == nil and "?" or (combat and "yes" or "no"), table.concat(hidden, " ")))
    end
  end
end

---------------------------------------------------------------------------
-- Source 5: after combat, for group members without ForeverCDs
---------------------------------------------------------------------------
-- In combat other players' casts and buffs are hidden. Once the combat
-- restriction lifts: re-read every buff (no UNIT_AURA fires for that), and read
-- Blizzard's damage meter for the fight, whose per-player breakdown lists the
-- spells that healed or did damage. A meter hit means "used during that fight":
-- the timer starts at the fight's end, so it never shows ready too early.
T.AFTER_TRIES = 20      -- one check a second while the restriction lasts

function T.Restricted()
  local RA, E = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
  if RA and RA.GetAddOnRestrictionState and E and E.Combat ~= nil then
    local st = ns.plain(ns.safe(RA.GetAddOnRestrictionState, E.Combat), "number")
    if st and st > 0 then return true end
  end
  return ns.plain(ns.safe(InCombatLockdown), "boolean") == true
end

local METER_TYPES = { "HealingDone", "DamageDone" }

-- Returns false while the meter data is still secret (try again later).
function T.ScanMeter(now)
  local DM = C_DamageMeter
  local types = Enum and Enum.DamageMeterType
  if type(DM) ~= "table" or type(types) ~= "table" or not DM.GetAvailableCombatSessions
      or not DM.GetCombatSessionSourceFromID then return true end
  local list = ns.safe(DM.GetAvailableCombatSessions)
  if ns.isSecret(list) then return false end
  if type(list) ~= "table" then return true end
  local sid = ns.field(list[#list], "sessionID", "number")
  if not sid then return true end
  for _, tn in ipairs(METER_TYPES) do
    local mt = types[tn]
    if mt ~= nil then
      for guid, m in pairs(ns.roster) do
        if guid ~= T.playerGUID then
          local src = ns.safe(DM.GetCombatSessionSourceFromID, sid, mt, guid)
          if ns.isSecret(src) then return false end
          local list2 = ns.field(src, "combatSpells", "table")
          for i = 1, list2 and math.min(#list2, 200) or 0 do
            local entry = list2[i]
            if ns.isSecret(entry) then return false end
            local id = ns.field(entry, "spellID", "number")
            local amount = ns.field(entry, "totalAmount", "number") or 0
            local spell = id and ns.Spells.Find(spells(), id)
            if spell and spell.class == m.class then
              -- The same session can span more than one fight: a new use shows as
              -- a bigger total.
              local k = sid .. "\0" .. guid .. "\0" .. spell.key
              local seen = T.meterSeen[k]
              if not seen or amount > seen then
                T.meterSeen[k] = amount
                local cd = ns.Spells.Cooldown(spell)
                local started = cd > 0 and T.Start(guid, spell.key, now, cd, "meter")
                ns.Debug(("after combat: meter shows %s used %s (%s)"):format(
                  tostring(m.name), spell.key, started and "timer started" or "timer already running"))
              end
            end
          end
        end
      end
    end
  end
  return true
end

-- One pass. Returns false when something was still secret.
function T.AfterCombat(now)
  now = now or ns.Now()
  for _, unit in ipairs(T.GroupUnits()) do T.ScanAuras(unit) end
  local ok = T.ScanMeter(now)
  if ns.debug and #T.hiddenCasts > 0 then
    for _, h in ipairs(T.hiddenCasts) do
      local secret = ns.isSecret(h.id)
      local name = not secret and ns.Spells.NameOf(ns.plain(h.id, "number"))
        or ns.plain(ns.safe(C_Spell and C_Spell.GetSpellName, h.id), "string")
      local m = ns.roster[h.guid]
      ns.Debug(("after combat: hidden cast by %s %.0f s ago: id %s, name %s"):format(
        tostring(m and m.name or h.guid), now - h.t, secret and "still secret" or tostring(h.id), tostring(name or "unreadable")))
    end
  end
  T.hiddenCasts = {}
  return ok
end

function T.OnCombatEnd()
  local tries = 0
  local function step()
    tries = tries + 1
    if not T.Restricted() and T.AfterCombat() ~= false then return end
    if tries < T.AFTER_TRIES and C_Timer then C_Timer.After(1, step) end
  end
  if C_Timer then C_Timer.After(0.5, step) else step() end
end

---------------------------------------------------------------------------
-- Source 4: addon-message sync (see Sync.lua)
---------------------------------------------------------------------------
function T.OnSync(guid, key, remaining)
  if not guid or not ns.roster[guid] then return false end
  local spell = spells()[key]
  if type(spell) ~= "table" or not spell.enabled then return false end
  if type(remaining) ~= "number" or remaining < 0 or remaining > 7200 then return false end
  local duration = ns.Spells.Cooldown(spell)
  if duration <= 0 then duration = remaining end
  if remaining > duration then remaining = duration end
  local now = ns.Now()
  if remaining == 0 then
    local cur = ns.cds[guid] and ns.cds[guid][key]
    if cur and running(cur, now) and (RANK[cur.source] or 0) > RANK.sync then return false end
    ns.cds[guid] = ns.cds[guid] or {}
    ns.cds[guid][key] = { start = now, duration = 0, source = "sync" }
    if T.onChange then T.onChange() end
    return true
  end
  return T.Start(guid, key, now - (duration - remaining), duration, "sync")
end

---------------------------------------------------------------------------
-- Persistence: wall-clock times across sessions
---------------------------------------------------------------------------
function T.Save(db, now, wall)
  now, wall = now or ns.Now(), wall or ns.Wall()
  local saved = {}
  for guid, list in pairs(ns.cds) do
    for key, rec in pairs(list) do
      if running(rec, now) then
        saved[guid] = saved[guid] or {}
        saved[guid][key] = {
          endsAt = wall + (rec.start + rec.duration - now),
          duration = rec.duration,
          source = rec.source,
        }
      end
    end
  end
  db.saved = saved
end

function T.Restore(db, now, wall)
  now, wall = now or ns.Now(), wall or ns.Wall()
  if type(db.saved) ~= "table" then return end
  for guid, list in pairs(db.saved) do
    if type(list) == "table" then
      for key, s in pairs(list) do
        if type(s) == "table" and type(s.endsAt) == "number" and type(s.duration) == "number" then
          local remaining = s.endsAt - wall
          if remaining > 0 and remaining <= s.duration + 1 then
            ns.cds[guid] = ns.cds[guid] or {}
            if not ns.cds[guid][key] then
              ns.cds[guid][key] = { start = now - (s.duration - remaining), duration = s.duration, source = s.source or "cast" }
            end
          end
        end
      end
    end
  end
end

function T.Reset()
  ns.roster, ns.cds = {}, {}
  T.unitGUID, T.leftAt, T.recent, T.pendingCast, T.auraLogged = {}, {}, {}, {}, {}
  T.meterSeen, T.hiddenCasts = {}, {}
  T.playerGUID = nil
end
