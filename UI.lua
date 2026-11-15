-- ForeverCDs: the cooldown window, test mode, alerts, and choosing window or
-- party-frame mode by group type.
local _, ns = ...
local UI = {}
ns.UI = UI

local T = ns.Tracker
local HEADER_H = 18
local PAD = 4

UI.test = false
UI.rows, UI.headers = {}, {}

---------------------------------------------------------------------------
-- Context and data
---------------------------------------------------------------------------
function UI.Context()
  if ns.plain(ns.safe(IsInRaid), "boolean") then return "raid" end
  if ns.plain(ns.safe(IsInGroup), "boolean") then return "party" end
  return "solo"
end

function UI.SortedSpells()
  local list = {}
  for _, s in pairs(ns.db.spells) do
    if type(s) == "table" and s.enabled then list[#list + 1] = s end
  end
  table.sort(list, function(a, b) return (a.name or a.key) < (b.name or b.key) end)
  return list
end

local TEST_NAMES = { "Leafwind", "Thornbark", "Mossheart" }
UI.testStart = 0

-- Simulated members for test mode: ready, assumed, and on cooldown.
function UI.TestMembers(spell)
  local now = ns.Now()
  local cd = ns.Spells.Cooldown(spell)
  if cd <= 0 then cd = 60 end
  local elapsed = (now - UI.testStart) % (cd + 20)
  local out = {}
  for i, name in ipairs(TEST_NAMES) do
    local e = { guid = "Test-" .. i, name = name, fullName = name, class = spell.class, test = true }
    if i == 1 then
      e.state, e.remaining, e.rec = "ready", 0, { source = "cast", start = now - cd - 30, duration = cd }
    elseif i == 2 then
      e.state, e.remaining = "assumed", 0
    else
      local rem = cd - elapsed
      if rem > 0 then
        e.state, e.remaining, e.rec = "cooldown", rem, { source = "cast", start = now - elapsed, duration = cd }
      else
        e.state, e.remaining, e.rec = "ready", 0, { source = "cast", start = now - elapsed, duration = cd }
      end
    end
    out[i] = e
  end
  return out
end

-- A strict order (table.sort needs one): ready first, then soonest ready, name, GUID.
local function sortMembers(a, b)
  local ar, br = a.state ~= "cooldown", b.state ~= "cooldown"
  if ar ~= br then return ar end
  if not ar and a.remaining ~= b.remaining then return a.remaining < b.remaining end
  local an, bn = a.name or "", b.name or ""
  if an ~= bn then return an < bn end
  return (a.guid or "") < (b.guid or "")
end
UI.SortMembers = sortMembers

-- Entries shown in the window for one spell.
function UI.Members(spell, now)
  if UI.test then
    -- Frame-mode test previews on the unit frames; the window stays empty.
    if ns.Frames and ns.Frames.Active() then return {} end
    local list = UI.TestMembers(spell)
    table.sort(list, sortMembers)
    return list
  end
  local list = {}
  local framesOn = ns.Frames and ns.Frames.Active() and not UI.test
  for _, guid in ipairs(T.Eligible(spell)) do
    if not (framesOn and ns.Frames.IsAttached(guid)) and not (framesOn and ns.Frames.Skipped(guid)) then
      local m = ns.roster[guid]
      local state, rem, rec, unavailable = T.GetState(guid, spell.key, now)
      list[#list + 1] = {
        guid = guid, name = m.name or "?", fullName = m.fullName or m.name, class = m.class,
        state = state, remaining = rem, rec = rec, unavailable = unavailable,
      }
    end
  end
  table.sort(list, sortMembers)
  return list
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
function UI.Create()
  if UI.frame then return end
  local f = CreateFrame("Frame", "ForeverCDsWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(180, 40)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetFrameStrata("MEDIUM")
  f:Hide()
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  end
  UI.frame = f

  local handle = CreateFrame("Frame", nil, f)
  handle:SetHeight(14)
  handle:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0)
  handle:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 0)
  handle:EnableMouse(true)
  handle:RegisterForDrag("LeftButton")
  handle.bg = handle:CreateTexture(nil, "BACKGROUND")
  handle.bg:SetAllPoints()
  handle.bg:SetColorTexture(0.2, 0.5, 0.8, 0.8)
  handle.text = handle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  handle.text:SetPoint("CENTER")
  handle.text:SetText("ForeverCDs - drag to move, /fcds lock")
  handle:SetScript("OnDragStart", function() f:StartMoving() end)
  handle:SetScript("OnDragStop", function() f:StopMovingOrSizing(); UI.SavePosition() end)
  UI.handle = handle

  UI.ApplyLayout()
end

-- Saved offsets are in UIParent units (L.ui = true), so changing the window scale
-- keeps its corner in place. GetLeft/GetTop and SetPoint offsets are in the
-- window's own scaled units, hence the multiply and divide by its scale.
function UI.SavePosition()
  local f, L = UI.frame, ns.db.layout
  local left = f:GetLeft()
  if not left then return end
  local s = f:GetScale() or 1
  if L.grow == "up" then
    L.point, L.x, L.y = "BOTTOMLEFT", left * s, (f:GetBottom() or 0) * s
  else
    L.point, L.x, L.y = "TOPLEFT", left * s, (f:GetTop() or 0) * s
  end
  L.ui = true
  UI.ApplyPosition()
end

function UI.ApplyPosition()
  local f, L = UI.frame, ns.db.layout
  local s = f:GetScale() or 1
  if not L.ui then
    -- Saved by an older version in the window's own units: keep it where it is now.
    L.x, L.y, L.ui = (L.x or 0) * s, (L.y or 0) * s, true
  end
  f:ClearAllPoints()
  if L.point == "CENTER" or not L.point then
    f:SetPoint(L.grow == "up" and "BOTTOM" or "TOP", UIParent, "CENTER", (L.x or 0) / s, (L.y or 0) / s)
  else
    -- Keep the edge that does not grow fixed.
    local point = (L.grow == "up") and "BOTTOMLEFT" or "TOPLEFT"
    if point ~= L.point then
      -- Grow direction changed since saving: convert using the current size.
      local h = (f:GetHeight() or 0) * s
      L.y = (point == "TOPLEFT") and (L.y + h) or (L.y - h)
      L.point = point
    end
    f:SetPoint(point, UIParent, "BOTTOMLEFT", (L.x or 0) / s, (L.y or 0) / s)
  end
end

function UI.ApplyLayout()
  if not UI.frame then return end
  local L = ns.db.layout
  UI.frame:SetScale(math.max(0.5, math.min(2, L.scale or 1)))
  UI.frame:SetWidth(L.width or 180)
  UI.ApplyPosition()
  UI.ApplyLock()
  UI.Refresh()
end

function UI.ApplyLock()
  local f, locked = UI.frame, ns.db.layout.locked
  if not f then return end
  if f.SetBackdropColor then
    if locked and not UI.test then
      f:SetBackdropColor(0, 0, 0, 0); f:SetBackdropBorderColor(0, 0, 0, 0)
    else
      f:SetBackdropColor(0, 0, 0, 0.55); f:SetBackdropBorderColor(0.2, 0.5, 0.8, 0.9)
    end
  end
  f:EnableMouse(false)
  UI.handle:SetShown(not locked)
end

local function rowHeight() return ns.db.layout.rowHeight or 20 end

local function newHeader()
  local h = CreateFrame("Frame", nil, UI.frame)
  h:SetHeight(HEADER_H)
  h.icon = h:CreateTexture(nil, "ARTWORK")
  h.icon:SetSize(HEADER_H - 2, HEADER_H - 2)
  h.icon:SetPoint("LEFT", 2, 0)
  h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  h.text:SetPoint("LEFT", h.icon, "RIGHT", 4, 0)
  return h
end

local function newRow()
  local r = CreateFrame("Frame", nil, UI.frame)
  r:EnableMouse(true)
  if r.SetMouseClickEnabled then r:SetMouseClickEnabled(false) end
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetPoint("TOPLEFT")
  r.mark = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  r.mark:SetPoint("TOPRIGHT", r.icon, "TOPRIGHT", 1, 1)
  r.mark:SetText("?")
  r.mark:SetTextColor(1, 0.85, 0.1)
  r.bar = CreateFrame("StatusBar", nil, r)
  r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  r.bar:SetMinMaxValues(0, 1)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetColorTexture(0, 0, 0, 0.5)
  r.name = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetJustifyH("LEFT")
  r.time = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.time:SetJustifyH("RIGHT")
  r:SetScript("OnEnter", function(self) UI.ShowTooltip(self, self.entry, self.spell) end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- Anchors never change; set them once here, not on every refresh.
  r.bar:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 2, 0)
  r.bar:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
  r.bg:SetAllPoints(r.bar)
  r.time:SetPoint("RIGHT", r.bar, "RIGHT", -4, 0)
  r.name:SetPoint("LEFT", r.bar, "LEFT", 4, 0)
  r.name:SetPoint("RIGHT", r.time, "LEFT", -4, 0)
  return r
end

-- Move a row or header only when its offset changed.
local function place(region, f, y)
  if region._y == y then return end
  region._y = y
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
end

local function sourceText(e, now)
  if e.state == "assumed" or not e.rec then return "assumed (not seen cast)" end
  local ago = ns.TimeText(now - (e.rec.start or now))
  if ago == "" then ago = "0" end
  local src = e.rec.source
  if src == "self" then return "your own cooldown" end
  if src == "aura" then return "buff seen, cast about " .. ago .. " ago" end
  if src == "sync" then return "synced, cast " .. ago .. " ago" end
  return "seen cast " .. ago .. " ago"
end

function UI.ShowTooltip(owner, e, spell)
  if not e or not spell then return end
  local now = ns.Now()
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(e.fullName or e.name, ns.ClassColor(e.class))
  GameTooltip:AddLine(spell.name, 1, 1, 1)
  local state
  if e.state == "cooldown" then state = "On cooldown: " .. ns.TimeText(e.remaining)
  elseif e.state == "assumed" then state = "Ready (assumed)"
  else state = "Ready" end
  if e.unavailable then state = state .. " - dead or offline" end
  GameTooltip:AddLine(state, 0.9, 0.9, 0.9)
  GameTooltip:AddLine(sourceText(e, now), 0.6, 0.6, 0.6)
  if spell.talent and e.guid and ns.Talents and not e.test then
    GameTooltip:AddLine("Talent: " .. ns.Talents.Describe(e.guid, spell), 0.6, 0.8, 1)
  end
  if e.test then GameTooltip:AddLine("Test mode", 1, 0.5, 0.2) end
  GameTooltip:Show()
end

local function styleRow(r, e, spell, width)
  local L = ns.db.layout
  local h = rowHeight()
  if r._w ~= width or r._h ~= h then
    r._w, r._h = width, h
    r:SetSize(width, h)
    r.icon:SetSize(h, h)
  end
  r.entry, r.spell = e, spell
  local tex = ns.Spells.IconOf(spell)
  if r._tex ~= tex then r._tex = tex; r.icon:SetTexture(tex) end
  local onCD = e.state == "cooldown"
  r.icon:SetDesaturated(onCD or e.unavailable)
  r.mark:SetShown(e.state == "assumed")
  local cr, cg, cb = ns.ClassColor(e.class)
  if e.unavailable then cr, cg, cb = 0.5, 0.5, 0.5 end
  r.name:SetText(e.name)
  r.name:SetTextColor(cr, cg, cb)
  r.time:SetText(onCD and ns.TimeText(e.remaining) or "Ready")
  if onCD then r.time:SetTextColor(1, 1, 1) else r.time:SetTextColor(0.3, 1, 0.3) end
  if e.unavailable then r.time:SetTextColor(0.5, 0.5, 0.5) end

  if L.style == "icons" then
    r.bar:SetStatusBarColor(0, 0, 0, 0)
    r.bar:SetValue(0)
  else
    local value = 1
    if onCD and e.rec and e.rec.duration > 0 then value = e.remaining / e.rec.duration end
    r.bar:SetValue(value)
    if e.unavailable then r.bar:SetStatusBarColor(0.35, 0.35, 0.35, 0.8)
    elseif onCD then r.bar:SetStatusBarColor(cr * 0.6, cg * 0.6, cb * 0.6, 0.9)
    else r.bar:SetStatusBarColor(cr * 0.45, cg * 0.45, cb * 0.45, 0.6) end
  end
  r:Show()
end

-- Should the window be visible at all in this context?
function UI.ContextShown()
  local ctx = UI.Context()
  return ns.db.show[ctx] and true or false
end

function UI.Refresh()
  local f = UI.frame
  if not f or not ns.db then return end
  local now = ns.Now()
  local width = ns.db.layout.width or 180
  local unlocked = not ns.db.layout.locked
  local allowed = UI.ContextShown() or UI.test
  local y, nr, nh = PAD, 0, 0
  if allowed then
    for _, spell in ipairs(UI.SortedSpells()) do
      local members = UI.Members(spell, now)
      if #members > 0 then
        nh = nh + 1
        local h = UI.headers[nh] or newHeader()
        UI.headers[nh] = h
        place(h, f, y)
        if h._w ~= width then h._w = width; h:SetWidth(width - 2 * PAD) end
        local tex = ns.Spells.IconOf(spell)
        if h._tex ~= tex then h._tex = tex; h.icon:SetTexture(tex) end
        h.text:SetText(spell.name)
        h:Show()
        y = y + HEADER_H
        for _, e in ipairs(members) do
          nr = nr + 1
          local r = UI.rows[nr] or newRow()
          UI.rows[nr] = r
          place(r, f, y)
          styleRow(r, e, spell, width - 2 * PAD)
          y = y + rowHeight() + 1
        end
        y = y + 2
      end
    end
  end
  for i = nr + 1, #UI.rows do UI.rows[i]:Hide() end
  for i = nh + 1, #UI.headers do UI.headers[i]:Hide() end

  local hasContent = nr > 0
  if hasContent or unlocked or UI.test then
    if not hasContent then
      y = PAD + HEADER_H
    end
    f:SetHeight(y + PAD)
    if (allowed or unlocked) and not f:IsShown() then f:Show() end
    if not allowed and not unlocked then f:Hide() end
  else
    f:Hide()
  end
end

---------------------------------------------------------------------------
-- Test mode
---------------------------------------------------------------------------
function UI.SetTest(on)
  UI.test = on and true or false
  UI.testStart = ns.Now()
  UI.ApplyLock()
  if ns.Frames then ns.Frames.Update() end
  UI.Refresh()
  if ns.RefreshPanel then ns.RefreshPanel() end
  ns.Print(UI.test and "Test mode on: simulated members. /fcds test again to stop." or "Test mode off.")
end

---------------------------------------------------------------------------
-- Alerts
---------------------------------------------------------------------------
UI.prevState = {}

local function alertAllowed(name)
  local players = ns.db.alerts.players
  if type(players) ~= "table" or next(players) == nil then return true end
  return players[(name or ""):lower()] and true or false
end

function UI.CheckReadyAlerts()
  local A = ns.db.alerts
  local now = ns.Now()
  for _, spell in ipairs(UI.SortedSpells()) do
    for _, guid in ipairs(T.Eligible(spell)) do
      local k = guid .. "\0" .. spell.key
      local state = T.GetState(guid, spell.key, now)
      local prev = UI.prevState[k]
      if A.ready and prev == "cooldown" and state == "ready" then
        local m = ns.roster[guid]
        if m and alertAllowed(m.name) then
          ns.Print(("%s ready: %s"):format(spell.name, m.name or "?"))
          if A.readySound and PlaySound then
            ns.safe(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
          end
        end
      end
      UI.prevState[k] = state
    end
  end
end

function UI.OnCast(guid, spell)
  local m = ns.roster[guid]
  if not ns.db.alerts.cast or not m or not alertAllowed(m.name) then return end
  local k = guid .. "\0" .. spell.key
  local function say()
    local p = T.pendingCast[k]
    local target = p and p.target
    if target then
      ns.Print(("%s cast %s on %s"):format(m.name or "?", spell.name, target))
    else
      ns.Print(("%s cast %s"):format(m.name or "?", spell.name))
    end
  end
  -- Give the aura scan a moment to see who got the buff.
  if C_Timer and C_Timer.After then C_Timer.After(0.5, say) else say() end
end

---------------------------------------------------------------------------
-- Ticker: 0.1 s refresh, 0.5 s alerts and status, 2 s frame re-anchor poll
---------------------------------------------------------------------------
local acc = 0
function UI.Tick()
  if not ns.db then return end
  acc = acc + 1
  if acc % 5 == 0 then
    T.RefreshAllStatus()
    UI.CheckReadyAlerts()
  end
  if acc % 20 == 0 and ns.Frames then ns.Frames.Poll() end
  if UI.frame and (UI.frame:IsShown() or UI.test or UI.ContextShown()) then UI.Refresh() end
  if ns.Frames then ns.Frames.Refresh() end
end

function UI.Start()
  UI.Create()
  if not UI.ticker and C_Timer and C_Timer.NewTicker then
    UI.ticker = C_Timer.NewTicker(0.1, UI.Tick)
  end
end

-- Group type changed: re-pick window or frame mode.
function UI.UpdateMode()
  if ns.Frames then ns.Frames.Update() end
  UI.Refresh()
end
