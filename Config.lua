-- ForeverCDs: defaults, saved-variable migration, slash commands, options
-- panel and event wiring.
local ADDON, ns = ...
local T, UI, F, S, Spells = ns.Tracker, ns.UI, ns.Frames, ns.Sync, ns.Spells

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
  saved = {},
}

local function fill(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      dst[k] = Spells.copy(v)
    elseif type(v) == "table" and type(dst[k]) == "table" and k ~= "spells" and k ~= "saved" and k ~= "players" then
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

local function onSlash(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S*)%s*(.*)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    if not ns.OpenPanel() then printHelp() end
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
  else printHelp() end
end

SLASH_FOREVERCDS1 = "/fcds"
SLASH_FOREVERCDS2 = "/forevercds"
SlashCmdList.FOREVERCDS = onSlash

---------------------------------------------------------------------------
-- Options panel (Esc > Options > AddOns > ForeverCDs)
---------------------------------------------------------------------------
local panel, category
local widgets = {}

local function tip(frame, text)
  if not text then return end
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(text, 1, 1, 1, true); GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function makeCheck(parent, label, onClick)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb.label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  cb.label:SetText(label)
  cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
  return cb
end

local function makeButton(parent, text, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

-- One row per option: checkbox, -/+ stepper, or a cycling button.
local function makeOptionRow(parent, o)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(420, 26)
  if o.kind == "bool" then
    row.cb = makeCheck(row, o.label, function(v) setOpt(o, v) end)
    row.cb:SetPoint("LEFT", 0, 0)
    row.Update = function() row.cb:SetChecked(getOpt(o) and true or false) end
  else
    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.label:SetPoint("LEFT", 4, 0)
    row.label:SetText(o.label)
    if o.kind == "number" then
      local function step(d)
        local v = (getOpt(o) or 0) + d * o.step
        v = math.floor(v / o.step + 0.5) * o.step
        setOpt(o, math.max(o.min, math.min(o.max, v)))
      end
      row.plus = makeButton(row, "+", 24, function() step(IsShiftKeyDown() and 10 or 1) end)
      row.plus:SetPoint("RIGHT", 0, 0)
      row.value = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      row.value:SetWidth(50)
      row.value:SetPoint("RIGHT", row.plus, "LEFT", -4, 0)
      row.minus = makeButton(row, "-", 24, function() step(IsShiftKeyDown() and -10 or -1) end)
      row.minus:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
      tip(row.plus, "Shift-click for bigger steps.")
      row.Update = function()
        local v = getOpt(o) or 0
        row.value:SetText(o.step < 1 and string.format("%.1f", v) or tostring(v))
      end
    else
      row.btn = makeButton(row, "", 120, function()
        local cur, idx = getOpt(o), 1
        for i, c in ipairs(o.choices) do if c == cur then idx = i end end
        local d = IsShiftKeyDown() and -1 or 1
        setOpt(o, o.choices[((idx - 1 + d) % #o.choices) + 1])
      end)
      row.btn:SetPoint("RIGHT", 0, 0)
      tip(row.btn, "Click to cycle, shift-click to go back.")
      row.Update = function() row.btn:SetText(tostring(getOpt(o))) end
    end
  end
  return row
end

local function buildPanel()
  if panel.built then return end
  panel.built = true
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("ForeverCDs")
  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
  sub:SetJustifyH("LEFT")
  sub:SetText("Group cooldown tracker. Only you need the addon. Every option here also works as "
    .. "a slash command: /fcds options lists them.")

  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -4, -8)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 12)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(440, 1)
  scroll:SetScrollChild(content)
  panel.content = content

  local y = 0
  local function place(f, h, indent)
    f:SetPoint("TOPLEFT", content, "TOPLEFT", indent or 0, -y)
    y = y + (h or 26)
  end
  local function heading(text)
    y = y + 8
    local h = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    place(h, 20, 4)
    h:SetText(text)
  end

  heading("Tracked spells")
  panel.spellRows = {}
  panel.spellAnchorY = y
  y = y + 26 * 12
  panel.spellBottom = y

  local groups = {
    { "Window", { "lock", "scale", "width", "rowheight", "style", "grow", "solo", "partyshow", "raid", "self" } },
    { "Party frames", { "partymode", "point", "relpoint", "x", "y", "size", "spacing", "stripgrow", "timertext", "selfstrip" } },
    { "Alerts and sync", { "readyalert", "readysound", "castalert", "sync" } },
  }
  for _, g in ipairs(groups) do
    heading(g[1])
    for _, name in ipairs(g[2]) do
      local row = makeOptionRow(content, findOpt(name))
      place(row, 26)
      widgets[#widgets + 1] = row
    end
    if g[1] == "Party frames" then
      local lbl = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
      place(lbl, 18, 4)
      lbl:SetText("Custom frame name pattern (blank = auto-detect):")
      local eb = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
      eb:SetSize(300, 22)
      eb:SetAutoFocus(false)
      place(eb, 28, 8)
      eb:SetScript("OnEnterPressed", function(self)
        local t = self:GetText()
        onSlash("frames " .. ((t == "" and "clear") or t))
        self:ClearFocus()
      end)
      eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
      tip(eb, "e.g. ElvUF_PartyGroup1UnitButton%d. Press Enter to apply.")
      panel.pattern = eb
    end
  end
  heading("Tools")
  local testBtn = makeButton(content, "Test mode", 110, function() UI.SetTest(not UI.test) end)
  place(testBtn, 26, 4)
  local resetBtn = makeButton(content, "Reset options", 110, function() cmdReset() end)
  resetBtn:SetPoint("LEFT", testBtn, "RIGHT", 8, 0)
  local dbg = makeCheck(content, "Debug: log every group cast", function(v) ns.debug = v end)
  place(dbg, 26)
  panel.debug = dbg
  content:SetHeight(y + 20)
end

function ns.RefreshPanel()
  if not panel or not panel.built or not panel:IsVisible() then return end
  for _, w in ipairs(widgets) do w.Update() end
  panel.pattern:SetText(ns.db.party.framePattern or "")
  panel.debug:SetChecked(ns.debug)
  local keys = {}
  for k in pairs(ns.db.spells) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return (ns.db.spells[a].name or a) < (ns.db.spells[b].name or b) end)
  for _, r in ipairs(panel.spellRows) do r:Hide() end
  for i, k in ipairs(keys) do
    if i > 12 then break end
    local s = ns.db.spells[k]
    local r = panel.spellRows[i]
    if not r then
      r = makeCheck(panel.content, "", function() end)
      r.icon = r:CreateTexture(nil, "ARTWORK")
      r.icon:SetSize(18, 18)
      r.icon:SetPoint("LEFT", r, "RIGHT", 4, 0)
      r.label:ClearAllPoints()
      r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
      r:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -(panel.spellAnchorY + (i - 1) * 26))
      panel.spellRows[i] = r
    end
    r.icon:SetTexture(Spells.IconOf(s))
    r.label:SetText(("%s  |cff999999%s, %s|r"):format(s.name, s.class or "?", ns.TimeText(Spells.Cooldown(s))))
    r:SetChecked(s.enabled and true or false)
    r:SetScript("OnClick", function(self) s.enabled = self:GetChecked() and true or false; applyFrames() end)
    r:Show()
  end
end

local function registerPanel()
  panel = CreateFrame("Frame")
  panel.name = "ForeverCDs"
  panel:SetScript("OnShow", function() buildPanel(); ns.RefreshPanel() end)
  if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

function ns.OpenPanel()
  if category and Settings and Settings.OpenToCategory then
    return ns.safe(Settings.OpenToCategory, category:GetID()) ~= false
  elseif panel and InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    return true
  end
  return false
end

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
  "EDIT_MODE_LAYOUTS_UPDATED",
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
    T.onOwnCast = function(spell, duration) S.Send(spell.key, duration) end
    registerPanel()
    T.RebuildRoster()
    T.Restore(ns.db)
    started = true
    UI.Start()
    UI.UpdateMode()
    queueSelf()
  elseif event == "PLAYER_LOGOUT" then
    if ns.db then T.Save(ns.db) end
  elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD"
      or event == "UNIT_CONNECTION" or event == "UNIT_LEVEL" then
    if started then rosterChanged() end
  elseif event == "PLAYER_REGEN_ENABLED" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
    if started then F.Update() end
  end
end)
