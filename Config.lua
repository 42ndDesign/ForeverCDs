-- ForeverCDs: defaults, saved-variable migration, slash commands, options
-- panel and event wiring.
local ADDON, ns = ...
local T, UI, F, S, Spells, TL = ns.Tracker, ns.UI, ns.Frames, ns.Sync, ns.Spells, ns.Talents

local DB_VERSION = 1

ns.defaults = {
  version = DB_VERSION,
  spells = {},
  layout = { point = "CENTER", x = 0, y = 0, scale = 1, width = 180, rowHeight = 20, style = "bars", grow = "down", locked = false },
  party = {
    mode = "window",
    point = "LEFT", relativePoint = "RIGHT", x = 4, y = 0,
    size = 20, spacing = 2, grow = "right", timerText = true, self = true,
    framePattern = nil,
  },
  show = { solo = false, party = true, raid = true, self = true },
  alerts = { ready = false, readySound = true, cast = false, players = {} },
  sync = false,
  talentCheck = true,
  talents = {},
  saved = {},
}

local function fill(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      dst[k] = Spells.copy(v)
    elseif type(v) == "table" and type(dst[k]) == "table" and k ~= "spells" and k ~= "saved" and k ~= "players" and k ~= "talents" then
      fill(dst[k], v)
    end
  end
end

function ns.InitDB()
  if type(ForeverCDsDB) ~= "table" then ForeverCDsDB = {} end
  local db = ForeverCDsDB
  fill(db, ns.defaults)
  if type(db.spells) ~= "table" then db.spells = {} end
  Spells.FillPresets(db.spells)
  -- Future reshaping goes here, gated on db.version.
  db.version = DB_VERSION
  ns.db = db
end

---------------------------------------------------------------------------
-- Options (shared by the slash command and the panel)
---------------------------------------------------------------------------
local function applyUI() if UI.frame then UI.ApplyLayout() end end
local function applyFrames() F.Update(); UI.Refresh() end
local POINT_LIST = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

-- kind: bool | number | choice
ns.options = {
  { name = "lock",       path = { "layout", "locked" },  kind = "bool",   label = "Lock the window", apply = applyUI },
  { name = "scale",      path = { "layout", "scale" },   kind = "number", min = 0.5, max = 2, step = 0.1, label = "Window scale", apply = applyUI },
  { name = "width",      path = { "layout", "width" },   kind = "number", min = 100, max = 400, step = 10, label = "Row width (px)", apply = applyUI },
  { name = "rowheight",  path = { "layout", "rowHeight" }, kind = "number", min = 12, max = 40, step = 1, label = "Row height (px)", apply = applyUI },
  { name = "style",      path = { "layout", "style" },   kind = "choice", choices = { "bars", "icons" }, label = "Layout", apply = applyUI },
  { name = "grow",       path = { "layout", "grow" },    kind = "choice", choices = { "down", "up" }, label = "Window grows", apply = applyUI },
  { name = "solo",       path = { "show", "solo" },      kind = "bool",   label = "Show when solo", apply = applyFrames },
  { name = "partyshow",  path = { "show", "party" },     kind = "bool",   label = "Show in a party", apply = applyFrames },
  { name = "raid",       path = { "show", "raid" },      kind = "bool",   label = "Show in a raid", apply = applyFrames },
  { name = "self",       path = { "show", "self" },      kind = "bool",   label = "Include yourself", apply = applyFrames },
  { name = "partymode",  path = { "party", "mode" },     kind = "choice", choices = { "window", "frames" }, label = "Party display (raids always use the window)", apply = applyFrames },
  { name = "point",      path = { "party", "point" },    kind = "choice", choices = POINT_LIST, label = "Strip anchor point", apply = applyFrames },
  { name = "relpoint",   path = { "party", "relativePoint" }, kind = "choice", choices = POINT_LIST, label = "Unit frame point", apply = applyFrames },
  { name = "x",          path = { "party", "x" },        kind = "number", min = -200, max = 200, step = 1, label = "X offset (px)", apply = applyFrames },
  { name = "y",          path = { "party", "y" },        kind = "number", min = -200, max = 200, step = 1, label = "Y offset (px)", apply = applyFrames },
  { name = "size",       path = { "party", "size" },     kind = "number", min = 12, max = 48, step = 1, label = "Icon size (px)", apply = applyFrames },
  { name = "spacing",    path = { "party", "spacing" },  kind = "number", min = 0, max = 16, step = 1, label = "Icon spacing (px)", apply = applyFrames },
  { name = "stripgrow",  path = { "party", "grow" },     kind = "choice", choices = { "right", "left", "up", "down" }, label = "Icons grow", apply = applyFrames },
  { name = "timertext",  path = { "party", "timerText" }, kind = "bool",  label = "Timer text on icons", apply = applyFrames },
  { name = "selfstrip",  path = { "party", "self" },     kind = "bool",   label = "Strip on your own frame", apply = applyFrames },
  { name = "readyalert", path = { "alerts", "ready" },   kind = "bool",   label = "Alert when a cooldown is ready" },
  { name = "readysound", path = { "alerts", "readySound" }, kind = "bool", label = "Play a sound with the ready alert" },
  { name = "castalert",  path = { "alerts", "cast" },    kind = "bool",   label = "Print tracked casts" },
  { name = "sync",       path = { "sync" },              kind = "bool",   label = "Addon-message sync (best effort)" },
  { name = "talents",    path = { "talentCheck" },       kind = "bool",   label = "Check talents by inspecting (out of combat)", apply = function() T.RebuildRoster() end },
}

local function getOpt(o)
  local t = ns.db
  for i = 1, #o.path - 1 do t = t[o.path[i]] end
  return t[o.path[#o.path]]
end

local function setOpt(o, v)
  local t = ns.db
  for i = 1, #o.path - 1 do t = t[o.path[i]] end
  t[o.path[#o.path]] = v
  if o.apply then o.apply() end
  if ns.RefreshPanel then ns.RefreshPanel() end
end

local function findOpt(name)
  for _, o in ipairs(ns.options) do if o.name == name then return o end end
end

-- Parse and set an option from text. Returns ok, message.
local function setFromText(o, text)
  text = (text or ""):lower()
  if o.kind == "bool" then
    local v
    if text == "on" or text == "1" or text == "true" then v = true
    elseif text == "off" or text == "0" or text == "false" then v = false
    elseif text == "" then v = not getOpt(o) end
    if v == nil then return false, "use on or off" end
    setOpt(o, v)
  elseif o.kind == "number" then
    local n = tonumber(text)
    if not n then return false, ("a number from %s to %s"):format(o.min, o.max) end
    n = math.max(o.min, math.min(o.max, n))
    setOpt(o, n)
  else
    for _, c in ipairs(o.choices) do
      if c:lower() == text then setOpt(o, c); return true end
    end
    return false, "one of " .. table.concat(o.choices, ", ")
  end
  return true
end

local function fmt(v)
  if v == true then return "on" elseif v == false then return "off" end
  return tostring(v)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
  "/fcds - options panel",
  "/fcds add <spell> [CLASS] - track a spell (e.g. /fcds add Innervate DRUID)",
  "/fcds remove <spell> - stop tracking",
  "/fcds list - tracked spells, IDs and cooldowns",
  "/fcds cd <spell> <seconds> - override a cooldown (0 clears)",
  "/fcds party window | frames - party display; raids always use the window",
  "/fcds anchor <point> <relativePoint> <x> <y> - frame-mode anchor (e.g. LEFT RIGHT 4 0)",
  "/fcds frames <pattern> | clear - custom unit-frame name pattern",
  "/fcds lock | unlock - lock or unlock the window",
  "/fcds test - simulated members and timers",
  "/fcds reset - reset position and options, keep the spell list",
  "/fcds sync on | off - addon-message sync",
  "/fcds debug - log every group cast event",
  "/fcds talents - who has Mana Tide / Power Infusion (checked by automatic inspect)",
  "/fcds set <option> <value> - any panel option; /fcds options lists them",
  "/fcds alert players <names> | clear - limit alerts to these players",
}

local function printHelp()
  for _, l in ipairs(HELP) do ns.Print(l) end
end

local function cmdList()
  local keys = {}
  for k in pairs(ns.db.spells) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local s = ns.db.spells[k]
    local ids = {}
    for _, id in ipairs(s.ids or {}) do ids[#ids + 1] = tostring(id) end
    ns.Print(("%s%s|r [%s] %s, ids %s, cd %ss%s"):format(
      s.enabled and "|cff33ff33" or "|cff999999", s.name or k, k, s.class or "?",
      table.concat(ids, ","), tostring(Spells.Cooldown(s)),
      s.cdOverride and " (override)" or ""))
  end
end

local function cmdAdd(rest)
  local words = {}
  for w in rest:gmatch("%S+") do words[#words + 1] = w end
  local class
  if #words > 1 and Spells.CLASSES[words[#words]:upper()] and words[#words] == words[#words]:upper() then
    class = table.remove(words):upper()
  end
  local query = table.concat(words, " ")
  if query == "" then return ns.Print("Usage: /fcds add <spell name or ID> [CLASS]") end

  local existing = Spells.Lookup(ns.db.spells, query)
  if existing then
    existing.enabled = true
    if class then existing.class = class end
    ns.Print(("Tracking %s (%s)."):format(existing.name, existing.class or "?"))
    return applyFrames()
  end
  local id, name = Spells.Resolve(query)
  if not id or not name then
    return ns.Print(("Couldn't find a spell called %q. Try its spell ID."):format(query))
  end
  local presetKey, preset = Spells.PresetFor(id, name)
  if presetKey and ns.db.spells[presetKey] then
    local s = ns.db.spells[presetKey]
    s.enabled = true
    if class then s.class = class end
    ns.Print(("Tracking %s (%s)."):format(s.name, s.class))
    return applyFrames()
  end
  class = class or (preset and preset.class)
  if not class then
    return ns.Print(("Which class casts %s? e.g. /fcds add %s DRUID"):format(name, query))
  end
  local key = ns.KeyFor(name)
  ns.db.spells[key] = { key = key, name = name, class = class, ids = { id }, enabled = true }
  Spells.ClearCache()
  ns.Print(("Tracking %s (%s, ID %d, cd %ss)."):format(name, class, id, tostring(Spells.Cooldown(ns.db.spells[key]))))
  applyFrames()
end

local function cmdRemove(rest)
  local s = Spells.Lookup(ns.db.spells, rest)
  if not s then return ns.Print(("Not tracking %q. /fcds list shows the keys."):format(rest)) end
  if Spells.presets[s.key] then s.enabled = false else ns.db.spells[s.key] = nil end
  ns.Print(("Stopped tracking %s."):format(s.name))
  applyFrames()
end

local function cmdCd(rest)
  local spellText, secs = rest:match("^(.-)%s+(%-?[%d%.]+)$")
  local s = spellText and Spells.Lookup(ns.db.spells, spellText)
  if not s then return ns.Print("Usage: /fcds cd <spell> <seconds>") end
  secs = tonumber(secs)
  if secs and secs > 0 then s.cdOverride = secs else s.cdOverride = nil end
  ns.Print(("%s cooldown: %ss%s"):format(s.name, tostring(Spells.Cooldown(s)), s.cdOverride and " (override)" or ""))
end

local function cmdAnchor(rest)
  local p, rp, x, y = rest:match("^(%a+)%s+(%a+)%s+(%-?%d+)%s+(%-?%d+)$")
  p, rp = p and p:upper(), rp and rp:upper()
  if not p or not F.POINTS[p] or not F.POINTS[rp] then
    return ns.Print("Usage: /fcds anchor <point> <relativePoint> <x> <y>, e.g. LEFT RIGHT 4 0")
  end
  local P = ns.db.party
  P.point, P.relativePoint = p, rp
  P.x = math.max(-200, math.min(200, tonumber(x)))
  P.y = math.max(-200, math.min(200, tonumber(y)))
  applyFrames()
  ns.Print(("Anchor: strip %s to frame %s, %d, %d"):format(P.point, P.relativePoint, P.x, P.y))
end

local function cmdReset()
  local spells = ns.db.spells
  local saved = ns.db.saved
  for k in pairs(ns.db) do ns.db[k] = nil end
  for k, v in pairs(ns.defaults) do ns.db[k] = Spells.copy(v) end
  ns.db.spells, ns.db.saved = spells, saved
  if UI.frame then UI.ApplyLayout() end
  applyFrames()
  ns.Print("Position and options reset. Spell list kept.")
end

local function cmdAlert(rest)
  local sub, names = rest:match("^(%S+)%s*(.*)$")
  if sub ~= "players" then return ns.Print("Usage: /fcds alert players <names> | clear") end
  local players = {}
  if names ~= "clear" and names ~= "" then
    for n in names:gmatch("[^%s,]+") do players[n:lower()] = true end
  end
  ns.db.alerts.players = players
  if next(players) then ns.Print("Alerts limited to: " .. names) else ns.Print("Alerts for everyone.") end
end

---------------------------------------------------------------------------
-- /fcds inspect: probe which talent APIs return readable data for another
-- player on this client. Diagnostic only; nothing uses the result yet.
---------------------------------------------------------------------------
local probe = nil   -- { unit, guid, t }

local function v2s(v)
  if v == nil then return "nil" end
  if ns.isSecret(v) then return "<secret>" end
  return tostring(v)
end

-- Probe output goes to chat and to ForeverCDsDB.probeLog, which /reload writes to
-- WTF/Account/<account>/SavedVariables/ForeverCDs.lua (chat can't be copied).
local function out(msg)
  ns.Print(msg)
  if not ns.db then return end
  local log = ns.db.probeLog
  if type(log) ~= "table" then log = {}; ns.db.probeLog = log end
  log[#log + 1] = date("%H:%M:%S ") .. tostring(msg)
  while #log > 400 do table.remove(log, 1) end
end

local function runProbe(unit, self)
  local P = out
  local insp = not self
  P(("%s probe for %s (%s):"):format(self and "Self talent" or "Inspect", v2s(ns.safe(UnitName, unit)), unit))

  -- 1. Classic ranks: GetTalentInfo(tab, index, isInspect)
  local tabs = ns.safe(GetNumTalentTabs, insp)
  P(("[classic] GetNumTalentTabs(%s) = %s"):format(insp and "inspect" or "own", v2s(tabs)))
  local picked, secret = {}, 0
  if ns.plain(tabs, "number") then
    for tab = 1, tabs do
      local a, b, c, d, e = ns.safe(GetTalentTabInfo, tab, insp)
      P(("[classic] tab %d info: %s | %s | %s | %s | %s"):format(tab, v2s(a), v2s(b), v2s(c), v2s(d), v2s(e)))
      local n = ns.plain(ns.safe(GetNumTalents, tab, insp), "number") or 0
      for i = 1, n do
        local name, _, _, _, rank = ns.safe(GetTalentInfo, tab, i, insp)
        if ns.isSecret(name) or ns.isSecret(rank) then secret = secret + 1
        elseif type(rank) == "number" and rank > 0 then picked[#picked + 1] = ("%s %d"):format(tostring(name), rank) end
      end
    end
    P(("[classic] talents with points: %d, secret: %d"):format(#picked, secret))
    if #picked > 0 then P("  " .. table.concat(picked, ", ", 1, math.min(#picked, 25))) end
  end

  -- 2. Talent tiers: C_SpecializationInfo.GetTalentInfo{ tier, column, isInspect = true }
  if C_SpecializationInfo and C_SpecializationInfo.GetTalentInfo then
    local sel = {}
    for tier = 1, 7 do
      for col = 1, 3 do
        local info = ns.safe(C_SpecializationInfo.GetTalentInfo, { tier = tier, column = col, isInspect = insp, target = insp and unit or nil })
        if type(info) == "table" and not ns.isSecret(info) then
          local s = ns.field(info, "selected")
          if s == true then sel[#sel + 1] = v2s(ns.field(info, "name")) end
        end
      end
    end
    P(("[tiers] selected: %s"):format(#sel > 0 and table.concat(sel, ", ") or "none readable"))
  else
    P("[tiers] C_SpecializationInfo.GetTalentInfo missing")
  end

  -- 3. Trait trees (Forever uses these). Walk every node with purchased ranks.
  local cid
  if self then
    cid = C_ClassTalents and ns.plain(ns.safe(C_ClassTalents.GetActiveConfigID), "number")
  else
    cid = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
  end
  if cid and C_Traits and C_Traits.GetConfigInfo then
    local cfg = ns.safe(C_Traits.GetConfigInfo, cid)
    local trees = ns.field(cfg, "treeIDs", "table")
    P(("[traits] config %s: %s, trees: %s"):format(v2s(cid), v2s(cfg and "found" or nil), v2s(trees and #trees)))
    local tracked = {}
    for _, key in ipairs(ns.Spells.ORDER) do
      local sp = ns.Spells.presets[key]
      for _, id in ipairs(sp.ids) do tracked[id] = sp.name end
    end
    for _, treeID in ipairs(trees or {}) do
      local nodes = ns.safe(C_Traits.GetTreeNodes, treeID)
      local total, bought, secret, list, hits = 0, 0, 0, {}, {}
      if type(nodes) == "table" and not ns.isSecret(nodes) then
        for _, nodeID in ipairs(nodes) do
          total = total + 1
          local info = ns.safe(C_Traits.GetNodeInfo, cid, nodeID)
          if ns.isSecret(info) or info == nil then secret = secret + 1 else
            local ranks = ns.field(info, "ranksPurchased", "number") or ns.field(info, "currentRank", "number") or 0
            local active = ns.field(info, "activeEntry", "table")
            local entryID = active and ns.field(active, "entryID", "number")
            if ranks > 0 and entryID then
              bought = bought + 1
              local e = ns.safe(C_Traits.GetEntryInfo, cid, entryID)
              local defID = ns.field(e, "definitionID", "number")
              local d = defID and ns.safe(C_Traits.GetDefinitionInfo, defID)
              local sid = ns.field(d, "spellID", "number") or ns.field(d, "overriddenSpellID", "number")
              local name = ns.field(d, "overrideName", "string") or (sid and ns.Spells.NameOf(sid))
              list[#list + 1] = ("%s(%s)%s"):format(v2s(name), v2s(sid), ranks > 1 and ("x" .. ranks) or "")
              if sid and tracked[sid] then hits[#hits + 1] = tracked[sid] .. " by id" end
              if name then
                for _, key in ipairs(ns.Spells.ORDER) do
                  if ns.Spells.presets[key].name == name then hits[#hits + 1] = name .. " by name" end
                end
              end
            end
          end
        end
      else
        P(("[traits] tree %s: GetTreeNodes returned %s"):format(v2s(treeID), v2s(nodes)))
      end
      P(("[traits] tree %s: nodes %d, purchased %d, unreadable %d"):format(v2s(treeID), total, bought, secret))
      for i = 1, #list, 6 do
        P("  " .. table.concat(list, ", ", i, math.min(i + 5, #list)))
      end
      P(("[traits] tracked talents found: %s"):format(#hits > 0 and table.concat(hits, ", ") or "none"))
    end
  else
    P(("[traits] no trait config (id %s, C_Traits %s)"):format(v2s(cid), v2s(C_Traits and "yes" or nil)))
  end

  if self then
    -- 4. Own spellbook: how the addon would detect the player's own talent spells.
    for _, key in ipairs(ns.Spells.ORDER) do
      local p = ns.Spells.presets[key]
      if p and p.talent then
        local id = p.ids[#p.ids]
        local parts = {}
        for _, fn in ipairs({ "IsPlayerSpell", "IsSpellKnown" }) do
          if _G[fn] then
            local any = false
            for _, sid in ipairs(p.ids) do
              local v = ns.safe(_G[fn], sid)
              if ns.isSecret(v) then any = "<secret>"; break end
              if v then any = true end
            end
            parts[#parts + 1] = ("%s=%s"):format(fn, tostring(any))
          end
        end
        P(("[spellbook] %s (ids %s): %s, name on client: %s"):format(p.name,
          table.concat(p.ids, "/"), table.concat(parts, " "), v2s(ns.Spells.NameOf(p.ids[1]))))
      end
    end
    local spec = GetSpecialization and ns.safe(GetSpecialization)
    local sid, sname = ns.safe(GetSpecializationInfo, ns.plain(spec, "number") or 0)
    P(("[spec] GetSpecialization = %s (id %s, %s)"):format(v2s(spec), v2s(sid), v2s(sname)))
    return
  end
  local specID = ns.safe(GetInspectSpecialization, unit)
  local _, sname, _, _, role, cls = ns.safe(GetSpecializationInfoByID, ns.plain(specID, "number") or 0)
  P(("[spec] GetInspectSpecialization = %s (%s, %s, %s)"):format(v2s(specID), v2s(sname), v2s(role), v2s(cls)))
  ns.safe(ClearInspectPlayer)
end

local function cmdInspect(rest)
  local unit = (rest ~= "" and rest:lower()) or "target"
  if unit == "me" or unit == "self" then unit = "player" end
  if unit == "player" or ns.plain(ns.safe(UnitIsUnit, unit, "player"), "boolean") then
    return runProbe("player", true)
  end
  if not ns.plain(ns.safe(UnitIsPlayer, unit), "boolean") then
    return out("Target a player (or /fcds inspect party1) first.")
  end
  local can = ns.safe(CanInspect, unit)
  out(("CanInspect(%s) = %s, in combat: %s"):format(unit, v2s(can), v2s(ns.safe(InCombatLockdown))))
  if not NotifyInspect then return out("NotifyInspect does not exist on this client.") end
  probe = { unit = unit, guid = ns.UnitGUIDSafe(unit), t = ns.Now() }
  TL.pending = nil; TL.paused = ns.Now() + 6
  ns.safe(NotifyInspect, unit)
  out("Inspect requested, waiting for INSPECT_READY (stay within about 28 yards)...")
  C_Timer.After(5, function()
    if probe and ns.Now() - probe.t >= 4.9 then
      out("No INSPECT_READY after 5 s. Reading anyway:")
      local u = probe.unit; probe = nil
      runProbe(u)
    end
  end)
end

function ns.OnInspectReady(guid)
  if not probe then return end
  if probe.guid and not ns.isSecret(guid) and guid ~= probe.guid then return end
  out(("INSPECT_READY after %.1f s (guid %s)"):format(ns.Now() - probe.t, v2s(guid)))
  local u = probe.unit; probe = nil
  runProbe(u)
end

-- /fcds talents: what the automatic talent check knows about the group.
local function cmdTalents()
  out(("Talent check: %s. Pending: %s"):format(TL.Enabled() and "on" or "off (/fcds set talents on)",
    TL.pending and (ns.roster[TL.pending.guid] and ns.roster[TL.pending.guid].name or "?") or "none"))
  local any = false
  for _, s in ipairs(Spells.Sorted(ns.db.spells)) do
    if s.enabled and s.talent then
      for guid, m in pairs(ns.roster) do
        if m.class == s.class then
          any = true
          local e = TL.Cache()[guid]
          local age = e and e.t and e.t > 0 and (" checked %s ago"):format(ns.TimeText(ns.Wall() - e.t)) or ""
          out(("  %s: %s - %s%s"):format(s.name, m.name or "?", TL.Describe(guid, s), age))
        end
      end
    end
  end
  if not any then out("  No group members of a class with an enabled talent spell.") end
end

local function onSlash(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S*)%s*(.*)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    if not (ns.OpenPanel and ns.OpenPanel()) then printHelp() end
  elseif cmd == "help" then printHelp()
  elseif cmd == "add" then cmdAdd(rest)
  elseif cmd == "remove" then cmdRemove(rest)
  elseif cmd == "list" then cmdList()
  elseif cmd == "cd" then cmdCd(rest)
  elseif cmd == "party" then
    rest = rest:lower()
    if rest ~= "window" and rest ~= "frames" then return ns.Print("Usage: /fcds party window | frames") end
    setOpt(findOpt("partymode"), rest)
    ns.Print("Party display: " .. rest .. (rest == "frames" and " (raids still use the window)" or ""))
  elseif cmd == "anchor" then cmdAnchor(rest)
  elseif cmd == "frames" then
    if rest == "" then return ns.Print("Frame pattern: " .. tostring(ns.db.party.framePattern or "none")) end
    ns.db.party.framePattern = (rest:lower() ~= "clear") and rest or nil
    F.noticed, F.scanCache = {}, {}
    applyFrames()
    ns.Print("Frame pattern: " .. tostring(ns.db.party.framePattern or "none"))
  elseif cmd == "lock" or cmd == "unlock" then
    setOpt(findOpt("lock"), cmd == "lock")
    ns.Print(cmd == "lock" and "Window locked." or "Window unlocked: drag the blue bar to move it.")
  elseif cmd == "test" then UI.SetTest(not UI.test)
  elseif cmd == "reset" then cmdReset()
  elseif cmd == "sync" then
    local ok, err = setFromText(findOpt("sync"), rest)
    if not ok then return ns.Print("Usage: /fcds sync on | off") end
    ns.Print("Sync " .. fmt(ns.db.sync) .. ".")
  elseif cmd == "debug" then
    ns.debug = not ns.debug
    ns.Print("Debug " .. (ns.debug and "on: every group cast is logged." or "off."))
  elseif cmd == "set" then
    local name, value = rest:match("^(%S+)%s*(.*)$")
    local o = name and findOpt(name:lower())
    if not o then return ns.Print("Unknown option. /fcds options lists them.") end
    local ok, err = setFromText(o, value)
    if not ok then return ns.Print(o.name .. ": " .. err) end
    ns.Print(("%s = %s"):format(o.name, fmt(getOpt(o))))
  elseif cmd == "options" then
    for _, o in ipairs(ns.options) do
      local hint = o.kind == "bool" and "on|off" or o.kind == "number" and (o.min .. "-" .. o.max) or table.concat(o.choices, "|")
      ns.Print(("%s = %s  (%s) - %s"):format(o.name, fmt(getOpt(o)), hint, o.label))
    end
  elseif cmd == "alert" then cmdAlert(rest)
  elseif cmd == "talents" then cmdTalents()
  elseif cmd == "inspect" and rest:lower() == "clear" then
    if ns.db then ns.db.probeLog = nil end
    ns.Print("Probe log cleared.")
  elseif cmd == "inspect" then cmdInspect(rest)
  else printHelp() end
end

SLASH_FOREVERCDS1 = "/fcds"
SLASH_FOREVERCDS2 = "/forevercds"
SlashCmdList.FOREVERCDS = onSlash

-- Shared with Options.lua.
ns.getOpt, ns.setOpt, ns.findOpt, ns.setFromText = getOpt, setOpt, findOpt, setFromText
ns.Slash, ns.ResetOptions, ns.ApplyFrames = onSlash, cmdReset, applyFrames

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")

-- Unknown events raise an error; register carefully. Never COMBAT_LOG_EVENT_UNFILTERED.
local function tryRegister(name)
  if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(name) then return end
  pcall(ev.RegisterEvent, ev, name)
end

for _, e in ipairs({
  "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD",
  "GROUP_ROSTER_UPDATE", "UNIT_CONNECTION", "UNIT_LEVEL", "UNIT_SPELLCAST_SUCCEEDED",
  "UNIT_AURA", "SPELL_UPDATE_COOLDOWN", "CHAT_MSG_ADDON", "PLAYER_REGEN_ENABLED",
  "EDIT_MODE_LAYOUTS_UPDATED", "INSPECT_READY", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
  "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
}) do tryRegister(e) end

-- UNIT_AURA can be busy in a raid: batch dirty units and scan 0.2 s later.
local dirtyAura, auraQueued = {}, false
local function flushAuras()
  auraQueued = false
  for unit in pairs(dirtyAura) do T.ScanAuras(unit) end
  dirtyAura = {}
end

local selfQueued = false
local function queueSelf()
  if selfQueued then return end
  selfQueued = true
  C_Timer.After(0.1, function() selfQueued = false; T.PollSelf() end)
end

local function rosterChanged()
  T.RebuildRoster()
  UI.UpdateMode()
end

-- Records or talent answers changed: re-resolve frame strips and redraw, at most
-- once per 0.2 s (a newly eligible member needs a strip, not just a redraw).
local changeQueued = false
local function queueChange()
  if changeQueued then return end
  changeQueued = true
  C_Timer.After(0.2, function() changeQueued = false; UI.UpdateMode() end)
end

local started = false
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    if started then T.OnCast(a1, a2, a3) end
  elseif event == "UNIT_AURA" then
    if not started or not ns.IsGroupUnit(a1) then return end
    dirtyAura[a1] = true
    if not auraQueued then auraQueued = true; C_Timer.After(0.2, flushAuras) end
  elseif event == "SPELL_UPDATE_COOLDOWN" then
    if started then queueSelf() end
  elseif event == "CHAT_MSG_ADDON" then
    if started then S.OnMessage(a1, a2, a3, a4) end
  elseif event == "ADDON_LOADED" then
    if a1 ~= ADDON then return end
    ns.InitDB()
    S.Register()
  elseif event == "PLAYER_LOGIN" then
    if not ns.db then ns.InitDB() end
    T.onCast = UI.OnCast
    T.onChange = queueChange
    T.onOwnCast = function(spell, duration) S.Send(spell.key, duration) end
    if ns.RegisterPanel then ns.RegisterPanel() end
    T.RebuildRoster()
    T.Restore(ns.db)
    TL.Start()
    started = true
    UI.Start()
    UI.UpdateMode()
    queueSelf()
  elseif event == "INSPECT_READY" then
    if started then TL.OnInspectReady(a1) end
    ns.OnInspectReady(a1)
  elseif event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE"
      or event == "ACTIVE_TALENT_GROUP_CHANGED" then
    if started then C_Timer.After(0.5, function() TL.ReadSelf() end) end
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
    if not started then return end
    if a1 == nil or a1 == "player" then C_Timer.After(0.5, function() TL.ReadSelf() end)
    elseif ns.IsGroupUnit(a1) then TL.MarkDirty(T.GUIDForUnit(a1)) end
  elseif event == "PLAYER_LOGOUT" then
    if ns.db then T.Save(ns.db) end
  elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD"
      or event == "UNIT_CONNECTION" or event == "UNIT_LEVEL" then
    if started then rosterChanged() end
  elseif event == "PLAYER_REGEN_ENABLED" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
    if started then F.Update() end
  end
end)
