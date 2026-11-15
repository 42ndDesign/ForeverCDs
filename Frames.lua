-- ForeverCDs: party frame mode. Small icon strips anchored to each party
-- member's unit frame.
--
-- Anchor points are the same for every frame addon (SetPoint takes any frame
-- as its relative frame), so what differs between UIs is only finding the
-- frame. Frames are matched on their unit / displayedUnit field or "unit"
-- attribute, never on index order. Order tried:
--   1. the user's custom name pattern (/fcds frames <pattern>)
--   2. known frame addons (ForeverUnitFrames, ElvUI, Shadowed UF, Cell, Grid2)
--   3. Blizzard raid-style party frames, then Blizzard party frames / PlayerFrame
--   4. a scan of every frame for a visible one bound to the unit (out of combat
--      only, throttled), which covers most other unit-frame addons.
-- Strips are plain, non-secure frames: anchoring them to a protected unit frame
-- is allowed, they follow it in combat, and nothing is ever called on the unit
-- frame except reads.
local _, ns = ...
local F = {}
ns.Frames = F

local T = ns.Tracker

F.strips = {}       -- [guid] = strip frame
F.attached = {}     -- [guid] = unit frame it is anchored to
F.missing = {}      -- [guid] = true when eligible but no frame was found
F.noticed = {}      -- [name] = true once the session notice was printed
F.scanCache = {}    -- [unit] = frame found by the generic scan
F.lastScan = -100
F.SCAN_EVERY = 10   -- seconds between generic scans while frames are missing,
F.SCAN_MAX = 120    -- doubling after each scan that finds nothing, up to this
F.scanMisses, F.scanKey = 0, nil
F.NOTICE_AFTER = 6  -- seconds a member must stay unfound before the chat notice
F.missingSince = {} -- [guid] = Now() when they were first not found

F.KNOWN_PATTERNS = {
  "ForeverUnitFramesPartyUnitButton%d",
  "ElvUF_PartyGroup1UnitButton%d",
  "SUFHeaderpartyUnitButton%d",
  "CellPartyFrameMember%d",
  "Grid2LayoutHeader1UnitButton%d",
}
F.KNOWN_LABELS = { "ForeverUnitFrames", "ElvUI", "Shadowed Unit Frames", "Cell", "Grid2" }
F.KNOWN_PLAYER = { "ElvUF_Player", "SUFUnitplayer" }
F.KNOWN_PLAYER_LABELS = { "ElvUI", "Shadowed Unit Frames" }
F.source = {}       -- [guid] = label of where its frame was found

local POINTS = {
  TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
  RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
F.POINTS = POINTS

---------------------------------------------------------------------------
-- Mode
---------------------------------------------------------------------------
-- Frame mode applies in a party (never in a raid) when the user picked it.
function F.Active()
  if not ns.db or ns.db.party.mode ~= "frames" then return false end
  local ctx = ns.UI.Context()
  if ctx == "raid" then return false end
  if ctx == "solo" then return ns.UI.test end
  return ns.db.show.party and true or false
end

function F.IsAttached(guid) return F.attached[guid] ~= nil end

-- The player's own strip is off, or "Include yourself" is off: they are left
-- out of frame mode entirely.
function F.Skipped(guid)
  return guid == T.playerGUID and (not ns.db.party.self or ns.db.show.self == false)
end

---------------------------------------------------------------------------
-- Finding unit frames
---------------------------------------------------------------------------
-- Every access is guarded: some frames are forbidden or return secret values.
local function rawFrameUnit(f)
  local u = ns.field(f, "unit", "string")
  local d = ns.field(f, "displayedUnit", "string")
  if not u and type(f.GetAttribute) == "function" then
    u = ns.plain(ns.safe(f.GetAttribute, f, "unit"), "string")
  end
  return u, d
end

local function frameUnit(f)
  if type(f) ~= "table" or ns.isSecret(f) then return nil end
  local ok, u, d = pcall(rawFrameUnit, f)
  if not ok then return nil end
  return u, d
end

local function visible(f)
  if type(f) ~= "table" or ns.isSecret(f) then return false end
  local ok, v = pcall(function() return f:IsVisible() end)
  return ok and ns.plain(v, "boolean") == true
end

local function matches(f, unit)
  if not visible(f) then return false end
  local u, d = frameUnit(f)
  return u == unit or d == unit
end

local function fromPattern(pattern, unit)
  if type(pattern) ~= "string" or pattern == "" then return nil end
  if not pattern:find("%%d") then
    local f = _G[pattern]
    return matches(f, unit) and f or nil
  end
  for i = 0, 5 do
    local ok, name = pcall(string.format, pattern, i)
    local f = ok and _G[name]
    if f and matches(f, unit) then return f end
  end
  return nil
end

local function isOurs(f)
  local p = f
  for _ = 1, 4 do
    if not p then return false end
    if p == ns.UI.frame or p.isForeverCDs then return true end
    p = ns.safe(p.GetParent, p)
  end
  return false
end

-- Scan every frame for a visible one bound to this unit (out of combat only).
local function genericScan(units)
  if not EnumerateFrames then return end
  if ns.plain(ns.safe(InCombatLockdown), "boolean") then return end
  local want, found, best = {}, {}, {}
  for _, u in ipairs(units) do want[u] = true end
  local function check(f)
    local u, d = frameUnit(f)
    local unit = (u and want[u] and u) or (d and want[d] and d)
    if unit and visible(f) and not isOurs(f) then
      local name = ns.plain(f:GetName(), "string") or ""
      -- Prefer frames that look like party/raid frames over target-of or nameplates.
      local score = 1
      if name:find("[Pp]arty") or name:find("[Gg]roup") or name:find("[Rr]aid") then score = 3 end
      if name:find("[Nn]ame[Pp]late") or name:find("[Tt]arget") then score = 0 end
      if score > 0 and (not best[unit] or score > best[unit]) then
        best[unit], found[unit] = score, f
      end
    end
  end
  local f = ns.safe(EnumerateFrames)
  local guard = 0
  while f and guard < 50000 do
    guard = guard + 1
    pcall(check, f)
    f = ns.safe(EnumerateFrames, f)
  end
  for unit, frame in pairs(found) do F.scanCache[unit] = frame end
end

-- Returns the unit frame and a label saying where it was found (for the options panel).
function F.FindFrame(unit)
  local P = ns.db.party
  local f = fromPattern(P.framePattern, unit)
  if f then return f, "Custom pattern" end
  for i, pat in ipairs(F.KNOWN_PATTERNS) do
    f = fromPattern(pat, unit)
    if f then return f, F.KNOWN_LABELS[i] end
  end
  if unit == "player" then
    for i, name in ipairs(F.KNOWN_PLAYER) do
      if matches(_G[name], unit) then return _G[name], F.KNOWN_PLAYER_LABELS[i] end
    end
  end
  for i = 1, 5 do
    f = _G["CompactPartyFrameMember" .. i]
    if f and matches(f, unit) then return f, "Blizzard raid-style frames" end
  end
  local pf = _G.PartyFrame
  if type(pf) == "table" then
    for i = 1, 4 do
      f = ns.field(pf, "MemberFrame" .. i)
      if f and matches(f, unit) then return f, "Blizzard party frames" end
    end
  end
  for i = 1, 4 do
    f = _G["PartyMemberFrame" .. i]
    if f and matches(f, unit) then return f, "Blizzard party frames" end
  end
  if unit == "player" and matches(_G.PlayerFrame, "player") then return _G.PlayerFrame, "Blizzard player frame" end
  f = F.scanCache[unit]
  if f and matches(f, unit) then return f, "Found by frame scan" end
  F.scanCache[unit] = nil
  return nil
end

---------------------------------------------------------------------------
-- Strips
---------------------------------------------------------------------------
local function newIcon(strip)
  local b = CreateFrame("Frame", nil, strip)
  b:EnableMouse(true)
  if b.SetMouseClickEnabled then b:SetMouseClickEnabled(false) end
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetAllPoints()
  b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("CENTER", 0, 0)
  b.mark = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.mark:SetPoint("TOPRIGHT", 1, 1)
  b.mark:SetText("?")
  b.mark:SetTextColor(1, 0.85, 0.1)
  b:SetScript("OnEnter", function(self) ns.UI.ShowTooltip(self, self.entry, self.spell) end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function getStrip(key)
  local s = F.strips[key]
  if s then return s end
  s = CreateFrame("Frame", nil, UIParent)
  s.isForeverCDs = true
  s:SetSize(1, 1)
  s:SetFrameStrata("MEDIUM")
  s.icons = {}
  F.strips[key] = s
  return s
end

local function anchor(strip, unitFrame)
  local P = ns.db.party
  strip:ClearAllPoints()
  local point = POINTS[P.point] and P.point or "LEFT"
  local rel = POINTS[P.relativePoint] and P.relativePoint or "RIGHT"
  local ok = pcall(strip.SetPoint, strip, point, unitFrame, rel, P.x or 0, P.y or 0)
  if ok then
    local lvl = ns.plain(ns.safe(unitFrame.GetFrameLevel, unitFrame), "number")
    if lvl then strip:SetFrameLevel(lvl + 5) end
    strip:Show()
  end
  return ok
end

-- entries = { { spell, entry }, ... }
local function layoutStrip(strip, entries)
  local P = ns.db.party
  local size, gap = P.size or 20, P.spacing or 2
  local dx, dy = 0, 0
  if P.grow == "left" then dx = -1 elseif P.grow == "up" then dy = 1 elseif P.grow == "down" then dy = -1 else dx = 1 end
  local n = #entries
  for i, item in ipairs(entries) do
    local b = strip.icons[i] or newIcon(strip)
    strip.icons[i] = b
    b:SetSize(size, size)
    b:ClearAllPoints()
    local off = (i - 1) * (size + gap)
    local start = (dx < 0 and "RIGHT") or (dy > 0 and "BOTTOM") or (dy < 0 and "TOP") or "LEFT"
    b:SetPoint(start, strip, start, dx * off, dy * off)
    local e, spell = item.entry, item.spell
    b.entry, b.spell = e, spell
    b.tex:SetTexture(ns.Spells.IconOf(spell))
    local onCD = e.state == "cooldown"
    b.tex:SetDesaturated(onCD or e.unavailable)
    if e.unavailable then b.tex:SetVertexColor(0.5, 0.5, 0.5) else b.tex:SetVertexColor(1, 1, 1) end
    b.text:SetText((onCD and P.timerText) and ns.TimeText(e.remaining) or "")
    b.mark:SetShown(e.state == "assumed")
    b:Show()
  end
  for i = n + 1, #strip.icons do strip.icons[i]:Hide() end
  local long = n > 0 and (n * size + (n - 1) * gap) or 1
  if dx ~= 0 then strip:SetSize(long, size) else strip:SetSize(size, long) end
end

-- Eligible tracked spells for one member, with their state.
local function memberEntries(guid, now)
  local m = ns.roster[guid]
  local out = {}
  for _, spell in ipairs(ns.UI.SortedSpells()) do
    if m.class == spell.class and (not spell.minLevel or not m.level or m.level >= spell.minLevel)
      and T.TalentOK(guid, spell) then
      local state, rem, rec, unavailable = T.GetState(guid, spell.key, now)
      out[#out + 1] = { spell = spell, entry = {
        guid = guid, name = m.name, fullName = m.fullName, class = m.class,
        state = state, remaining = rem, rec = rec, unavailable = unavailable,
      } }
    end
  end
  return out
end

local function hideAll()
  for _, s in pairs(F.strips) do s:Hide() end
  F.attached, F.missing = {}, {}
end

-- Re-resolve frames and re-anchor every strip.
function F.Update()
  if not ns.db then return end
  if not F.Active() then hideAll(); return end
  if ns.UI.test then F.UpdateTest(); return end
  local now = ns.Now()
  F.attached, F.missing, F.source = {}, {}, {}
  local used = {}
  local needScan = {}
  for guid, m in pairs(ns.roster) do
    if not F.Skipped(guid) then
      local entries = memberEntries(guid, now)
      if #entries > 0 then
        local unitFrame, src = F.FindFrame(m.unit)
        F.source[guid] = src
        if unitFrame then
          local strip = getStrip(guid)
          if anchor(strip, unitFrame) then
            F.attached[guid] = unitFrame
            layoutStrip(strip, entries)
            used[guid] = true
          end
        end
        if not F.attached[guid] then
          F.missing[guid] = true
          needScan[#needScan + 1] = m.unit
        end
      end
    end
  end
  for key, s in pairs(F.strips) do if not used[key] then s:Hide() end end

  -- A different set of missing units starts the backoff over.
  table.sort(needScan)
  local key = table.concat(needScan, ",")
  if key ~= F.scanKey then F.scanKey, F.scanMisses = key, 0 end
  local wait = math.min(F.SCAN_EVERY * 2 ^ F.scanMisses, F.SCAN_MAX)
  local inCombat = ns.plain(ns.safe(InCombatLockdown), "boolean")
  if #needScan > 0 and not inCombat and ns.Now() - F.lastScan >= wait then
    F.lastScan = ns.Now()
    genericScan(needScan)
    local again = false
    for _, u in ipairs(needScan) do if F.scanCache[u] then again = true end end
    if again then F.lastScan = ns.Now(); return F.Update() end
    F.scanMisses = F.scanMisses + 1
  end
  -- Frame addons create frames late: only speak up once the member stays unfound.
  for guid in pairs(F.missingSince) do
    if not F.missing[guid] then F.missingSince[guid] = nil end
  end
  for guid in pairs(F.missing) do
    F.missingSince[guid] = F.missingSince[guid] or now
    local m = ns.roster[guid]
    local name = m and m.name or guid
    if not F.noticed[name] and now - F.missingSince[guid] >= F.NOTICE_AFTER then
      F.noticed[name] = true
      ns.Print(("Couldn't find %s's party frame, showing them in the window. If you use a "
        .. "unit-frame addon, set its frame name with /fcds frames <pattern>, "
        .. "e.g. /fcds frames ElvUF_PartyGroup1UnitButton%%d"):format(name))
    end
  end
end

-- Cheap per-tick update: refresh icon states, hide strips whose frame hid or
-- now shows someone else (frame addons re-sort their buttons).
function F.Refresh()
  if not ns.db or not F.Active() then return end
  if ns.UI.test then
    for _, s in pairs(F.strips) do
      if s:IsShown() and s.testIndex then layoutStrip(s, F.TestEntries(s.testIndex)) end
    end
    return
  end
  local now = ns.Now()
  local lost = false
  for guid, unitFrame in pairs(F.attached) do
    local strip = F.strips[guid]
    local m = ns.roster[guid]
    if not m or not matches(unitFrame, m.unit) then
      if strip then strip:Hide() end
      lost = true
    elseif strip then
      layoutStrip(strip, memberEntries(guid, now))
    end
  end
  if lost then F.Update() end
end

-- Every 2 s while any member lacks a strip (UI replacements create frames late).
function F.Poll()
  if F.Active() and next(F.missing) ~= nil then F.Update() end
end

---------------------------------------------------------------------------
-- Test preview: simulated strips on the frames on screen
---------------------------------------------------------------------------
function F.TestEntries(i)
  local out = {}
  for _, spell in ipairs(ns.UI.SortedSpells()) do
    local list = ns.UI.TestMembers(spell)
    local e = list[((i - 1) % #list) + 1]
    out[#out + 1] = { spell = spell, entry = e }
  end
  return out
end

function F.UpdateTest()
  F.attached, F.missing = {}, {}
  for _, s in pairs(F.strips) do s:Hide() end
  local frames = {}
  for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
    local f = F.FindFrame(unit)
    if f then frames[#frames + 1] = f end
  end
  if #frames == 0 and _G.PlayerFrame then frames[1] = _G.PlayerFrame end
  for i, f in ipairs(frames) do
    local strip = getStrip("test" .. i)
    strip.testIndex = i
    if anchor(strip, f) then layoutStrip(strip, F.TestEntries(i)) end
  end
end
