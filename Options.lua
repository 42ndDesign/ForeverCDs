-- ForeverCDs: options panel (Esc > Options > AddOns > ForeverCDs).
-- Built from flat textures and font strings to match the Claude Design mockup:
-- a header, a tab rail (Spells, Window, Party frames, Alerts & sync) and one
-- page per tab. Every control writes through ns.setOpt or a slash command, so
-- the panel and /fcds always agree.
local ADDON, ns = ...
local O = {}
ns.Options = O

local Spells, T, F, UI = ns.Spells, ns.Tracker, ns.Frames, ns.UI
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local COL = {
  bg = "0f0f11", header = "141417", rail = "121214", line = "2c2c31", line2 = "3a3a40",
  rowLine = "222226", raised = "1f1f23", input = "0b0b0c", segOff = "1a1a1d", card = "141417",
  text = "ececec", muted = "a3a3a8", dim = "8d8d93", soft = "c9c9ce", offText = "b4b4ba",
  gold = "ffd100", goldHover = "ffe566", dark = "141414", activeTab = "24241f", onRow = "1b1b16",
  preview = "1b2420", knobOff = "6a6a72", trackOff = "4a4a52", hover = "6a6a72",
  green = "5ce65c", amber = "ff9f1a",
}

local function rgb(hex)
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

---------------------------------------------------------------------------
-- Primitives
---------------------------------------------------------------------------
local function Tex(parent, hex, layer, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  local r, g, b = rgb(hex)
  t:SetColorTexture(r, g, b, a or 1)
  return t
end

local function SetBox(f, bg, border)
  if bg then local r, g, b = rgb(bg); f:SetBackdropColor(r, g, b, 1) end
  if border then local r, g, b = rgb(border); f:SetBackdropBorderColor(r, g, b, 1) end
end

local function Box(parent, bg, border, kind)
  local f = CreateFrame(kind or "Frame", nil, parent, "BackdropTemplate")
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  SetBox(f, bg or COL.bg, border or COL.line)
  return f
end

local function Text(parent, size, hex, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(FONT, size or 12, "")
  fs:SetTextColor(rgb(hex or COL.text))
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local function Color(fs, hex) fs:SetTextColor(rgb(hex)) end

local function Tip(frame, text)
  frame:HookScript("OnEnter", function(self)
    if not text then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(type(text) == "function" and text() or text, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Button kinds: primary (gold), secondary, outline (gold border), selected, off.
local KINDS = {
  primary   = { bg = COL.gold,      border = COL.gold,  text = COL.dark },
  secondary = { bg = COL.raised,    border = COL.line2, text = COL.text },
  outline   = { bg = COL.raised,    border = COL.gold,  text = COL.gold },
  selected  = { bg = COL.activeTab, border = COL.gold,  text = COL.gold },
  off       = { bg = COL.segOff,    border = COL.line2, text = COL.soft },
  ghost     = { bg = COL.bg,        border = COL.line2, text = COL.soft },
}

local function Button(parent, label, kind, w, h, onClick)
  local b = Box(parent, nil, nil, "Button")
  b:SetSize(w, h or 28)
  b.text = Text(b, 12, COL.text, "CENTER")
  b.text:SetPoint("CENTER")
  b.text:SetText(label)
  function b:SetKind(k)
    self.kind = k
    local c = KINDS[k]
    SetBox(self, c.bg, c.border)
    Color(self.text, c.text)
  end
  b:SetKind(kind or "secondary")
  b:SetScript("OnEnter", function(self)
    if self.kind == "primary" then SetBox(self, COL.goldHover, COL.goldHover)
    else SetBox(self, nil, self.kind == "outline" and COL.goldHover or COL.hover) end
  end)
  b:SetScript("OnLeave", function(self) self:SetKind(self.kind) end)
  b:SetScript("OnClick", onClick)
  return b
end

-- Square on/off switch (30x16).
local function Toggle(parent, label, onChange)
  local b = Box(parent, COL.input, COL.trackOff, "Button")
  b:SetSize(30, 16)
  b.knob = Tex(b, COL.knobOff, "ARTWORK")
  b.knob:SetSize(12, 12)
  function b:Set(on)
    self.on = on and true or false
    SetBox(self, on and COL.gold or COL.input, on and COL.gold or COL.trackOff)
    self.knob:SetColorTexture(rgb(on and COL.dark or COL.knobOff))
    self.knob:ClearAllPoints()
    self.knob:SetPoint(on and "RIGHT" or "LEFT", on and -1 or 1, 0)
  end
  b:Set(false)
  b:SetScript("OnClick", function(self) onChange(not self.on) end)
  if label then Tip(b, label) end
  return b
end

-- Checkbox with a label; the whole row is clickable.
local function Check(parent, label, onChange)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(20)
  b.box = Box(b, COL.input, COL.line2)
  b.box:SetSize(16, 16)
  b.box:SetPoint("LEFT")
  b.box:EnableMouse(false)
  b.mark = b.box:CreateTexture(nil, "OVERLAY")
  b.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  b.mark:SetPoint("CENTER")
  b.mark:SetSize(20, 20)
  b.label = Text(b, 12, COL.text)
  b.label:SetPoint("LEFT", b.box, "RIGHT", 10, 0)
  b.label:SetText(label)
  b:SetWidth(26 + (b.label:GetStringWidth() or 100))
  function b:Set(on)
    self.on = on and true or false
    self.mark:SetShown(self.on)
    SetBox(self.box, COL.input, self.on and COL.gold or COL.line2)
  end
  b:Set(false)
  b:SetScript("OnClick", function(self) onChange(not self.on) end)
  return b
end

-- Segmented control: items = { {value, label}, ... }
local function Segmented(parent, items, itemW, h, onPick)
  local f = Box(parent, COL.segOff, COL.line2)
  h = h or 28
  f:SetSize(#items * itemW + 2, h)
  f.buttons = {}
  for i, it in ipairs(items) do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(itemW, h - 2)
    b:SetPoint("LEFT", 1 + (i - 1) * itemW, 0)
    b.bg = Tex(b, COL.segOff)
    b.bg:SetAllPoints()
    if i > 1 then
      local sep = Tex(b, COL.line2, "BORDER")
      sep:SetWidth(1)
      sep:SetPoint("TOPLEFT"); sep:SetPoint("BOTTOMLEFT")
    end
    b.text = Text(b, 12, COL.soft, "CENTER")
    b.text:SetPoint("CENTER")
    b.text:SetText(it[2])
    b.value = it[1]
    b:SetScript("OnClick", function() onPick(it[1]) end)
    f.buttons[i] = b
  end
  function f:Set(value)
    for _, b in ipairs(self.buttons) do
      local on = b.value == value
      b.bg:SetColorTexture(rgb(on and COL.gold or COL.segOff))
      Color(b.text, on and COL.dark or COL.soft)
    end
  end
  return f
end

-- Slider with label, value and min/max captions. fmt(v) formats the value.
local function Slider(parent, label, min, max, step, fmt, onChange)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(46)
  f.label = Text(f, 11, COL.muted)
  f.label:SetPoint("TOPLEFT")
  f.label:SetText(label)
  f.value = Text(f, 12, COL.text, "RIGHT")
  f.value:SetPoint("TOPRIGHT")
  local s = CreateFrame("Slider", nil, f)
  s:SetPoint("TOPLEFT", 0, -16)
  s:SetPoint("TOPRIGHT", 0, -16)
  s:SetHeight(16)
  s:SetOrientation("HORIZONTAL")
  s:SetMinMaxValues(min, max)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  local track = Tex(s, COL.line, "BACKGROUND")
  track:SetHeight(4)
  track:SetPoint("LEFT"); track:SetPoint("RIGHT")
  local thumb = s:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(rgb(COL.text))
  thumb:SetSize(10, 16)
  s:SetThumbTexture(thumb)
  local fill = Tex(s, COL.gold, "ARTWORK")
  fill:SetHeight(4)
  fill:SetPoint("LEFT", track, "LEFT")
  fill:SetPoint("RIGHT", thumb, "CENTER")
  local lo = Text(f, 10, COL.dim); lo:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -2); lo:SetText(tostring(min))
  local hi = Text(f, 10, COL.dim, "RIGHT"); hi:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2); hi:SetText(tostring(max))
  local function round(v) return math.floor(v / step + 0.5) * step end
  s:SetScript("OnValueChanged", function(_, v)
    if f.setting then return end
    v = round(v)
    f.value:SetText(fmt(v))
    onChange(v)
  end)
  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(self, d) self:SetValue(self:GetValue() + d * step) end)
  function f:Set(v)
    self.setting = true
    s:SetValue(v)
    self.setting = false
    self.value:SetText(fmt(v))
  end
  return f
end

-- [-] value [+]; shift-click steps by 10.
local function Stepper(parent, label, fmt, onStep)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(124, 46)
  f.label = Text(f, 11, COL.muted)
  f.label:SetPoint("TOPLEFT")
  f.label:SetText(label)
  local box = Box(f, COL.input, COL.line2)
  box:SetPoint("TOPLEFT", 0, -16)
  box:SetPoint("TOPRIGHT", 0, -16)
  box:SetHeight(28)
  local function side(sym, d, point)
    local b = CreateFrame("Button", nil, box)
    b:SetSize(28, 26)
    b:SetPoint(point, point == "LEFT" and 1 or -1, 0)
    b.bg = Tex(b, COL.segOff); b.bg:SetAllPoints()
    local t = Text(b, 14, COL.text, "CENTER"); t:SetPoint("CENTER"); t:SetText(sym)
    b:SetScript("OnClick", function() onStep(IsShiftKeyDown() and d * 10 or d) end)
    b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(rgb(COL.raised)) end)
    b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(rgb(COL.segOff)) end)
    return b
  end
  side("-", -1, "LEFT"); side("+", 1, "RIGHT")
  f.value = Text(box, 12, COL.text, "CENTER")
  f.value:SetPoint("CENTER")
  Tip(box, "Shift-click for steps of 10.")
  function f:Set(v) self.value:SetText(fmt(v)) end
  return f
end

local POINT_ORDER = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local POINT_NAMES = {
  TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right", LEFT = "Left", CENTER = "Center",
  RIGHT = "Right", BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right",
}

-- 3x3 anchor point picker.
local function AnchorPicker(parent, label, fill, onPick)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(96, 106)
  f.label = Text(f, 11, COL.muted)
  f.label:SetPoint("TOPLEFT")
  f.label:SetText(label)
  local grid = Box(f, fill, COL.line2)
  grid:SetPoint("TOPLEFT", 0, -18)
  grid:SetSize(96, 66)
  f.cells = {}
  for i, point in ipairs(POINT_ORDER) do
    local b = CreateFrame("Button", nil, grid)
    b:SetSize(32, 22)
    b:SetPoint("TOPLEFT", ((i - 1) % 3) * 32, -math.floor((i - 1) / 3) * 22)
    b.dot = Tex(b, COL.knobOff, "ARTWORK")
    b.dot:SetPoint("CENTER")
    b.point = point
    b:SetScript("OnClick", function() onPick(point) end)
    Tip(b, POINT_NAMES[point])
    f.cells[i] = b
  end
  f.value = Text(f, 11, COL.text)
  f.value:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -6)
  function f:Set(point)
    for _, b in ipairs(self.cells) do
      local on = b.point == point
      b.dot:SetSize(on and 10 or 5, on and 10 or 5)
      b.dot:SetColorTexture(rgb(on and COL.gold or "5a5a62"))
    end
    self.value:SetText(POINT_NAMES[point] or point)
  end
  return f
end

-- Text input with placeholder. onEnter(text) on Enter.
local function Input(parent, w, h, placeholder, onEnter)
  local e = Box(parent, COL.input, COL.line2, "EditBox")
  e:SetSize(w, h or 28)
  e:SetAutoFocus(false)
  e:SetFont(FONT, 12, "")
  e:SetTextColor(rgb(COL.text))
  e:SetTextInsets(10, 10, 0, 0)
  e.ph = Text(e, 12, COL.dim)
  e.ph:SetPoint("LEFT", 10, 0)
  e.ph:SetText(placeholder or "")
  local function upd(self) self.ph:SetShown(self:GetText() == "" and not self:HasFocus()) end
  e:SetScript("OnTextChanged", upd)
  e:SetScript("OnEditFocusGained", function(self) SetBox(self, nil, COL.gold); upd(self) end)
  e:SetScript("OnEditFocusLost", function(self) SetBox(self, nil, COL.line2); upd(self) end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) onEnter(self:GetText()); self:ClearFocus() end)
  function e:SetValue(v) if not self:HasFocus() then self:SetText(v or ""); upd(self) end end
  return e
end

local function Heading(parent, text)
  local fs = Text(parent, 15, COL.gold)
  fs:SetText(text)
  return fs
end

local function Muted(parent, text, size)
  local fs = Text(parent, size or 12, COL.muted)
  fs:SetText(text)
  return fs
end

local function SmallLabel(parent, text)
  local fs = Text(parent, 11, COL.muted)
  fs:SetText(text)
  return fs
end

local function fmtCD(sec)
  if not sec or sec <= 0 then return "?" end
  local s = math.floor(sec + 0.5)
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function opt(name) return ns.findOpt(name) end
local function get(name) return ns.getOpt(opt(name)) end
local function set(name, v) ns.setOpt(opt(name), v) end

---------------------------------------------------------------------------
-- Panel skeleton
---------------------------------------------------------------------------
local panel, category, root
local pages, tabButtons, current = {}, {}, "spells"
local refreshers = {}

local TABS = {
  { key = "spells",  label = "Spells" },
  { key = "window",  label = "Window" },
  { key = "party",   label = "Party frames" },
  { key = "alerts",  label = "Alerts & sync" },
}

local function selectTab(key)
  current = key
  for k, p in pairs(pages) do p:SetShown(k == key) end
  for _, b in ipairs(tabButtons) do
    local on = b.key == key
    b.bg:SetShown(on)
    Color(b.text, on and COL.gold or COL.soft)
  end
  O.Refresh()
end

local function version()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local v = get and ns.safe(get, ADDON, "Version")
  if not v or v:find("@") then return "dev" end
  return v
end

local function buildHeader()
  local h = Box(root, COL.header, COL.line)
  h:SetPoint("TOPLEFT"); h:SetPoint("TOPRIGHT")
  h:SetHeight(56)
  local logo = Box(h, "2a3a1c", COL.gold)
  logo:SetSize(28, 28)
  logo:SetPoint("LEFT", 20, 0)
  local lt = Text(logo, 11, COL.gold, "CENTER"); lt:SetPoint("CENTER"); lt:SetText("CD")
  local title = Text(h, 17, COL.gold); title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, 2); title:SetText("ForeverCDs")
  local sub = Muted(h, "v" .. version() .. " · group cooldowns · only you need it", 11)
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)

  O.lockBtn = Button(h, "Unlock window", "primary", 120, 30, function()
    ns.Slash(ns.db.layout.locked and "unlock" or "lock")
  end)
  O.lockBtn:SetPoint("RIGHT", -20, 0)
  O.testBtn = Button(h, "Test mode", "secondary", 96, 30, function() UI.SetTest(not UI.test) end)
  O.testBtn:SetPoint("RIGHT", O.lockBtn, "LEFT", -12, 0)
  Tip(O.testBtn, "Shows simulated members so you can check layout solo.")
  refreshers.header = function()
    local locked = ns.db.layout.locked
    O.lockBtn.text:SetText(locked and "Unlock window" or "Lock window")
    O.lockBtn:SetKind(locked and "primary" or "outline")
    O.testBtn.text:SetText(UI.test and "Stop test" or "Test mode")
    O.testBtn:SetKind(UI.test and "selected" or "secondary")
  end
  return h
end

local function buildRail(header)
  local r = Box(root, COL.rail, COL.line)
  r:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 1)
  r:SetPoint("BOTTOMLEFT")
  r:SetWidth(172)
  for i, tab in ipairs(TABS) do
    local b = CreateFrame("Button", nil, r)
    b:SetSize(152, 36)
    b:SetPoint("TOPLEFT", 10, -14 - (i - 1) * 40)
    b.bg = Tex(b, COL.activeTab); b.bg:SetAllPoints(); b.bg:Hide()
    b.hl = Tex(b, COL.segOff, "BORDER"); b.hl:SetAllPoints(); b.hl:Hide()
    b.text = Text(b, 13, COL.soft); b.text:SetPoint("LEFT", 12, 0); b.text:SetText(tab.label)
    b.key = tab.key
    b:SetScript("OnEnter", function(self) if current ~= self.key then self.hl:Show() end end)
    b:SetScript("OnLeave", function(self) self.hl:Hide() end)
    b:SetScript("OnClick", function(self) self.hl:Hide(); selectTab(self.key) end)
    tabButtons[i] = b
  end
  local sep = Tex(r, COL.line, "ARTWORK")
  sep:SetHeight(1)
  sep:SetPoint("BOTTOMLEFT", 10, 64); sep:SetPoint("BOTTOMRIGHT", -10, 64)
  local foot = Muted(r, "Every option also works as a command. Type |cffececec/fcds help|r.", 11)
  foot:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 12, -10)
  foot:SetWidth(128)
  foot:SetSpacing(3)
  return r
end

local function newPage(rail, key)
  local p = CreateFrame("Frame", nil, root)
  p:SetPoint("TOPLEFT", rail, "TOPRIGHT", 22, -18)
  p:SetPoint("BOTTOMRIGHT", -22, 14)
  p:Hide()
  pages[key] = p
  return p
end

---------------------------------------------------------------------------
-- Spells tab
---------------------------------------------------------------------------
local CLASS_LIST = { "DRUID", "PALADIN", "PRIEST", "SHAMAN", "WARLOCK", "MAGE", "HUNTER", "ROGUE", "WARRIOR" }

local function classColorHex(class)
  local r, g, b = ns.ClassColor(class)
  return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function memberCount(spell)
  local n = #T.Eligible(spell)
  if n == 0 then return "none", false end
  local cname = (Spells.CLASS_NAMES[spell.class] or spell.class or "?"):lower()
  return ("%d %s%s"):format(n, cname, n == 1 and "" or "s"), true
end

local function buildSpells(p)
  local h = Heading(p, "Tracked spells"); h:SetPoint("TOPLEFT")
  local talentChk = Check(p, "Check talents (auto inspect)", function(v) set("talents", v); O.Refresh() end)
  talentChk:SetPoint("TOPRIGHT", 0, -2)
  Tip(talentChk, "Out of combat, quietly inspects group members of a class with a talent spell (Mana Tide Totem, Power Infusion), one every 2 seconds, and hides the spell for those without the talent. /fcds talents lists the results.")
  local sub = Muted(p, "Shown for every group member of that class. Talent spells hide players an inspect shows lack the talent. Click a cooldown to set your own.")
  sub:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
  sub:SetPoint("RIGHT", p, "RIGHT")

  -- Add row: [ name input ][ class menu ][ Add ]
  local addLabel = SmallLabel(p, "Add a spell"); addLabel:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -14)
  local addRow = CreateFrame("Frame", nil, p)
  addRow:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 0, -4)
  addRow:SetPoint("RIGHT", p, "RIGHT")
  addRow:SetHeight(30)
  local addClass = nil
  local add = Input(addRow, 100, 30, "Spell name or ID", function(text)
    if text == "" then return end
    ns.Slash("add " .. text .. (addClass and (" " .. addClass) or ""))
    p.addBox:SetText("")
    O.Refresh()
  end)
  p.addBox = add
  add:SetPoint("LEFT")

  local addBtn = Button(addRow, "Add", "outline", 64, 30, function() add:GetScript("OnEnterPressed")(add) end)
  addBtn:SetPoint("RIGHT")

  local classBtn = Button(addRow, "Class: auto", "secondary", 120, 30, nil)
  classBtn:SetPoint("RIGHT", addBtn, "LEFT", -8, 0)
  classBtn.text:ClearAllPoints(); classBtn.text:SetPoint("LEFT", 10, 0)
  local chev = Text(classBtn, 10, COL.muted); chev:SetPoint("RIGHT", -10, 0); chev:SetText("v")
  local classLabel = SmallLabel(p, "Class"); classLabel:SetPoint("BOTTOMLEFT", classBtn, "TOPLEFT", 0, 4)
  add:SetPoint("RIGHT", classBtn, "LEFT", -8, 0)

  -- Class menu
  local menu = Box(p, COL.raised, COL.line2)
  menu:SetFrameStrata("DIALOG")
  menu:SetPoint("TOPLEFT", classBtn, "BOTTOMLEFT", 0, -2)
  menu:SetSize(120, (#CLASS_LIST + 1) * 22 + 2)
  menu:Hide()
  local function pick(class)
    addClass = class
    classBtn.text:SetText(class and (Spells.CLASS_NAMES[class] or class) or "Class: auto")
    if class then Color(classBtn.text, classColorHex(class)) else Color(classBtn.text, COL.text) end
    menu:Hide()
  end
  local entries = { false }
  for _, c in ipairs(CLASS_LIST) do entries[#entries + 1] = c end
  for i, c in ipairs(entries) do
    local b = CreateFrame("Button", nil, menu)
    b:SetSize(118, 22)
    b:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 22)
    b.hl = Tex(b, COL.segOff); b.hl:SetAllPoints(); b.hl:Hide()
    local t = Text(b, 12, c and classColorHex(c) or COL.text); t:SetPoint("LEFT", 10, 0)
    t:SetText(c and (Spells.CLASS_NAMES[c] or c) or "Auto-detect")
    b:SetScript("OnEnter", function(self) self.hl:Show() end)
    b:SetScript("OnLeave", function(self) self.hl:Hide() end)
    b:SetScript("OnClick", function() pick(c or nil) end)
  end
  classBtn:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
  p:SetScript("OnHide", function() menu:Hide() end)

  -- List
  local list = Box(p, COL.card, COL.line)
  list:SetPoint("TOPLEFT", addRow, "BOTTOMLEFT", 0, -14)
  list:SetPoint("BOTTOMRIGHT", 0, 0)
  local head = CreateFrame("Frame", nil, list)
  head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(26)
  local hl = Tex(head, COL.line, "ARTWORK"); hl:SetHeight(1); hl:SetPoint("BOTTOMLEFT"); hl:SetPoint("BOTTOMRIGHT")
  local COLS = { 10, 54, -212, -92 }  -- track, spell, cooldown (from right), in group (from right)
  local function headText(text, x, right)
    local t = Text(head, 10, COL.muted, right and "RIGHT" or "LEFT")
    t:SetText(text:upper())
    if right then t:SetPoint("RIGHT", -10, 0) else t:SetPoint("LEFT", x, 0) end
    return t
  end
  headText("Track", COLS[1]); headText("Spell", COLS[2])
  local cdHead = headText("Cooldown", 0); cdHead:ClearAllPoints(); cdHead:SetPoint("LEFT", head, "RIGHT", COLS[3], 0)
  headText("In group", 0, true)

  local scroll = CreateFrame("ScrollFrame", nil, list)
  scroll:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
  scroll:SetPoint("BOTTOMRIGHT", -1, 1)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w) end)
  local bar = Tex(list, COL.line2, "OVERLAY"); bar:SetWidth(3); bar:Hide()
  local function updateBar()
    local viewH, fullH = scroll:GetHeight(), content:GetHeight()
    if not viewH or fullH <= viewH + 1 then bar:Hide(); return end
    local frac = viewH / fullH
    local off = scroll:GetVerticalScroll() / (fullH - viewH)
    bar:SetHeight(viewH * frac)
    bar:ClearAllPoints()
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -1, -off * viewH * (1 - frac))
    bar:Show()
  end
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, d)
    local max = math.max(0, content:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 37)))
    updateBar()
  end)

  local rows = {}
  local ROW_H = 37
  local function newRow(i)
    local r = CreateFrame("Frame", nil, content)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("RIGHT", content, "RIGHT")
    r.bg = Tex(r, COL.onRow); r.bg:SetAllPoints()
    local line = Tex(r, COL.rowLine, "BORDER"); line:SetHeight(1); line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
    r.toggle = Toggle(r, nil, function(on) r.spell.enabled = on; ns.ApplyFrames(); O.Refresh() end)
    r.toggle:SetPoint("LEFT", COLS[1], 0)
    r.iconBorder = Box(r, COL.bg, COL.line2); r.iconBorder:SetSize(28, 28); r.iconBorder:SetPoint("LEFT", COLS[2], 0)
    r.icon = r.iconBorder:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("TOPLEFT", 1, -1); r.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = Text(r, 12.5, COL.text); r.name:SetPoint("TOPLEFT", r.iconBorder, "TOPRIGHT", 10, -1)
    r.class = Text(r, 11, COL.muted); r.class:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    -- Cooldown cell: click to override.
    r.cd = CreateFrame("Button", nil, r)
    r.cd:SetSize(110, ROW_H - 6)
    r.cd:SetPoint("LEFT", r, "RIGHT", COLS[3], 0)
    r.cdText = Text(r.cd, 12.5, COL.text); r.cdText:SetPoint("LEFT")
    r.cdNote = Text(r.cd, 10, COL.muted); r.cdNote:SetPoint("LEFT", r.cdText, "RIGHT", 6, 0)
    r.cdEdit = Input(r, 64, 24, "sec", function(text)
      ns.Slash(("cd %s %s"):format(r.spell.key, tonumber(text) and text or "0"))
      O.Refresh()
    end)
    r.cdEdit:SetPoint("LEFT", r, "RIGHT", COLS[3], 0)
    r.cdEdit:Hide()
    r.cdEdit:HookScript("OnEditFocusLost", function(self) self:Hide(); r.cd:Show() end)
    r.cd:SetScript("OnClick", function()
      r.cd:Hide(); r.cdEdit:Show()
      r.cdEdit:SetText(r.spell.cdOverride and tostring(r.spell.cdOverride) or "")
      r.cdEdit:SetFocus()
    end)
    Tip(r.cd, "Click to set your own cooldown in seconds. Empty or 0 goes back to the default.")
    r.group = Text(r, 12, COL.text, "RIGHT"); r.group:SetPoint("RIGHT", -10, 0)
    r.remove = Button(r, "x", "ghost", 20, 20, function()
      ns.Slash("remove " .. r.spell.key); O.Refresh()
    end)
    r.remove:SetPoint("RIGHT", -8, 0)
    Tip(r.remove, "Remove this spell")
    return r
  end

  refreshers.spells = function()
    talentChk:Set(ns.db.talentCheck ~= false)
    local list = Spells.Sorted(ns.db.spells)
    for i, s in ipairs(list) do
      local r = rows[i] or newRow(i)
      rows[i] = r
      r.spell = s
      local on = s.enabled and true or false
      r.bg:SetShown(on)
      r.toggle:Set(on)
      r.icon:SetTexture(Spells.IconOf(s))
      r.icon:SetDesaturated(not on)
      r.iconBorder:SetAlpha(on and 1 or 0.55)
      r.name:SetText(s.name or s.key)
      Color(r.name, on and COL.text or COL.offText)
      local cname = Spells.CLASS_NAMES[s.class] or s.class or "?"
      local tags = ""
      if s.talent then
        local unk = 0
        if ns.Talents and ns.Talents.Enabled() then
          for guid, m in pairs(ns.roster) do
            if m.class == s.class and ns.Talents.Has(guid, s) == nil then unk = unk + 1 end
          end
        end
        tags = tags .. (unk > 0 and (" · talent, %d unchecked"):format(unk) or " · talent")
      end
      if not Spells.presets[s.key] then tags = tags .. " · custom" end
      r.class:SetText(("|cff%s%s|r|cff%s%s|r"):format(on and classColorHex(s.class) or COL.muted, cname, COL.muted, tags))
      r.cdText:SetText(fmtCD(Spells.Cooldown(s)))
      Color(r.cdText, on and COL.text or COL.offText)
      r.cdNote:SetText(Spells.CooldownSource(s))
      local count, any = memberCount(s)
      r.group:SetText(count)
      Color(r.group, (on and any) and COL.text or COL.muted)
      local custom = not Spells.presets[s.key]
      r.remove:SetShown(custom)
      r.group:ClearAllPoints()
      r.group:SetPoint("RIGHT", custom and -34 or -10, 0)
      r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(1, #list * ROW_H))
    updateBar()
  end
end

---------------------------------------------------------------------------
-- Window tab
---------------------------------------------------------------------------
local function buildWindow(p)
  local h = Heading(p, "Cooldown window"); h:SetPoint("TOPLEFT")
  local sub = Muted(p, "Changes show in the preview and on screen as you make them.")
  sub:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)

  local left = CreateFrame("Frame", nil, p)
  left:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
  left:SetPoint("BOTTOMRIGHT", -258, 0)

  local l1 = SmallLabel(left, "Layout"); l1:SetPoint("TOPLEFT")
  local style = Segmented(left, { { "bars", "Bars" }, { "icons", "Icons only" } }, 92, 28, function(v) set("style", v) end)
  style:SetPoint("TOPLEFT", l1, "BOTTOMLEFT", 0, -6)
  local l2 = SmallLabel(left, "Grows"); l2:SetPoint("TOPLEFT", style, "BOTTOMLEFT", 0, -14)
  local grow = Segmented(left, { { "down", "Down" }, { "up", "Up" } }, 92, 28, function(v) set("grow", v) end)
  grow:SetPoint("TOPLEFT", l2, "BOTTOMLEFT", 0, -6)

  local scale = Slider(left, "Scale", 0.5, 2, 0.1, function(v) return ("%.1fx"):format(v) end, function(v) set("scale", v) end)
  scale:SetPoint("TOPLEFT", grow, "BOTTOMLEFT", 0, -16); scale:SetPoint("RIGHT", left, "RIGHT")
  local width = Slider(left, "Row width", 100, 400, 10, function(v) return v .. " px" end, function(v) set("width", v) end)
  width:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, -10); width:SetPoint("RIGHT", left, "RIGHT")
  local height = Slider(left, "Row height", 12, 40, 1, function(v) return v .. " px" end, function(v) set("rowheight", v) end)
  height:SetPoint("TOPLEFT", width, "BOTTOMLEFT", 0, -10); height:SetPoint("RIGHT", left, "RIGHT")

  local l3 = SmallLabel(left, "Show the window"); l3:SetPoint("TOPLEFT", height, "BOTTOMLEFT", 0, -12)
  local chips = {}
  local chipDefs = { { "solo", "Solo" }, { "partyshow", "In party" }, { "raid", "In raid" } }
  for i, c in ipairs(chipDefs) do
    local b = Button(left, c[2], "off", 76, 28, function() set(c[1], not get(c[1])) end)
    if i == 1 then b:SetPoint("TOPLEFT", l3, "BOTTOMLEFT", 0, -6) else b:SetPoint("LEFT", chips[i - 1], "RIGHT", 6, 0) end
    b.opt = c[1]
    chips[i] = b
  end
  local selfCheck = Check(left, "Include yourself", function(v) set("self", v) end)
  selfCheck:SetPoint("TOPLEFT", chips[1], "BOTTOMLEFT", 0, -14)

  -- Preview
  local pl = Text(p, 10, COL.muted); pl:SetText("PREVIEW")
  pl:SetPoint("TOPLEFT", left, "TOPRIGHT", 22, 0)
  local box = Box(p, COL.preview, COL.line)
  box:SetPoint("TOPLEFT", pl, "BOTTOMLEFT", 0, -8)
  box:SetPoint("BOTTOMRIGHT")
  box:SetClipsChildren(true)
  local win = Box(box, "000000", "335a80")
  win:SetBackdropColor(0, 0, 0, 0.55)
  win:SetPoint("TOP", 0, -20)
  local hIcon = win:CreateTexture(nil, "ARTWORK"); hIcon:SetSize(16, 16); hIcon:SetPoint("TOPLEFT", 6, -5)
  hIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local hText = Text(win, 11, COL.gold); hText:SetPoint("LEFT", hIcon, "RIGHT", 4, 0)
  local note = Muted(box, "Ready first, then by time left. |cffffd100?|r = assumed ready: not seen cast yet.", 11)
  note:SetWidth(196); note:SetJustifyH("CENTER"); note:SetSpacing(3)
  note:SetPoint("TOP", win, "BOTTOM", 0, -14)
  local prow = {}
  local SAMPLE = {
    { "Leafwind", "ready" }, { "Thornbark", "assumed" }, { "Mossheart", "cooldown", 222, 360 },
  }
  for i = 1, 3 do
    local r = CreateFrame("Frame", nil, win)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetPoint("TOPLEFT"); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.mark = Text(r, 10, COL.gold); r.mark:SetPoint("TOPRIGHT", r.icon, "TOPRIGHT", 0, 1); r.mark:SetText("?")
    r.bg = Tex(r, "000000"); r.bg:SetAlpha(0.5)
    r.bar = Tex(r, "5a3a14", "BORDER")
    r.name = Text(r, 11, "ff9a3d"); r.time = Text(r, 11, COL.text, "RIGHT")
    prow[i] = r
  end

  refreshers.window = function()
    local L = ns.db.layout
    style:Set(L.style); grow:Set(L.grow)
    scale:Set(L.scale or 1); width:Set(L.width or 180); height:Set(L.rowHeight or 20)
    for _, b in ipairs(chips) do b:SetKind(get(b.opt) and "selected" or "off") end
    selfCheck:Set(get("self"))

    local spell = ns.db.spells.innervate or Spells.Sorted(ns.db.spells)[1]
    local rh = math.max(12, math.min(28, L.rowHeight or 20))
    local w = math.max(150, math.min(220, (L.width or 180)))
    hIcon:SetTexture(Spells.IconOf(spell)); hText:SetText(spell and spell.name or "")
    local y = 26
    for i, r in ipairs(prow) do
      local s = SAMPLE[i]
      local onCD = s[2] == "cooldown"
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 4, -y); r:SetSize(w - 8, rh)
      r.icon:SetSize(rh, rh); r.icon:SetTexture(Spells.IconOf(spell)); r.icon:SetDesaturated(onCD)
      r.mark:SetShown(s[2] == "assumed")
      r.bg:ClearAllPoints(); r.bg:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 2, 0); r.bg:SetPoint("BOTTOMRIGHT")
      r.bar:ClearAllPoints(); r.bar:SetPoint("TOPLEFT", r.bg, "TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT", r.bg, "BOTTOMLEFT")
      local full = (w - 8) - rh - 2
      r.bar:SetWidth(math.max(1, full * (onCD and (s[3] / s[4]) or 1)))
      r.bar:SetColorTexture(rgb(onCD and "99520a" or "5a3a14"))
      r.bar:SetShown(L.style ~= "icons")
      r.name:ClearAllPoints(); r.name:SetPoint("LEFT", r.bg, "LEFT", 5, 0); r.name:SetText(s[1])
      r.time:ClearAllPoints(); r.time:SetPoint("RIGHT", r.bg, "RIGHT", -5, 0)
      r.time:SetText(onCD and fmtCD(s[3]) or "Ready")
      Color(r.time, onCD and COL.text or COL.green)
      y = y + rh + 1
    end
    win:SetSize(w, y + 4)
  end
end

---------------------------------------------------------------------------
-- Party frames tab
---------------------------------------------------------------------------
local function buildParty(p)
  local h = Heading(p, "In a party, show cooldowns"); h:SetPoint("TOPLEFT")
  local sub = Muted(p, "Raids always use the window."); sub:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
  local mode = Segmented(p, { { "window", "In the window" }, { "frames", "On party frames" } }, 116, 28,
    function(v) set("partymode", v) end)
  mode:SetPoint("TOPRIGHT")

  local left = CreateFrame("Frame", nil, p)
  left:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
  left:SetSize(262, 440)
  local pt = AnchorPicker(left, "Icon strip point", COL.card, function(v) set("point", v) end)
  pt:SetPoint("TOPLEFT")
  local rp = AnchorPicker(left, "Party frame point", "222222", function(v) set("relpoint", v) end)
  rp:SetPoint("TOPLEFT", pt, "TOPRIGHT", 14, 0)

  local function stepper(name, label, unit)
    local o = opt(name)
    return Stepper(left, label, function(v) return v .. (unit or " px") end, function(d)
      local v = (ns.getOpt(o) or 0) + d * o.step
      ns.setOpt(o, math.max(o.min, math.min(o.max, v)))
    end), name
  end
  local steps = {}
  local defs = { { "x", "X offset" }, { "y", "Y offset" }, { "size", "Icon size" }, { "spacing", "Spacing" } }
  for i, d in ipairs(defs) do
    local s = stepper(d[1], d[2])
    s.opt = d[1]
    if i == 1 then s:SetPoint("TOPLEFT", pt, "BOTTOMLEFT", 0, -10)
    elseif i % 2 == 0 then s:SetPoint("LEFT", steps[i - 1], "RIGHT", 14, 0)
    else s:SetPoint("TOPLEFT", steps[i - 2], "BOTTOMLEFT", 0, -10) end
    steps[i] = s
  end
  local gl = SmallLabel(left, "Icons grow"); gl:SetPoint("TOPLEFT", steps[3], "BOTTOMLEFT", 0, -12)
  local grow = Segmented(left, { { "right", "Right" }, { "left", "Left" }, { "up", "Up" }, { "down", "Down" } }, 58, 26,
    function(v) set("stripgrow", v) end)
  grow:SetPoint("TOPLEFT", gl, "BOTTOMLEFT", 0, -6)
  local timer = Check(left, "Timer text on icons", function(v) set("timertext", v) end)
  timer:SetPoint("TOPLEFT", grow, "BOTTOMLEFT", 0, -14)
  local selfc = Check(left, "Icons on your own frame", function(v) set("selfstrip", v) end)
  selfc:SetPoint("TOPLEFT", timer, "BOTTOMLEFT", 0, -8)

  -- Right column: preview, frames found, pattern
  local right = CreateFrame("Frame", nil, p)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 20, 0)
  right:SetPoint("BOTTOMRIGHT")
  local pl = Text(right, 10, COL.muted); pl:SetText("PREVIEW"); pl:SetPoint("TOPLEFT")
  local box = Box(right, COL.preview, COL.line)
  box:SetPoint("TOPLEFT", pl, "BOTTOMLEFT", 0, -8); box:SetPoint("RIGHT")
  box:SetHeight(168)
  box:SetClipsChildren(true)
  local MOCK = { { "You", "4a4a4a", "ready" }, { "Leafwind", "a65a12", "ready" }, { "Thornbark", "a65a12", "assumed" }, { "Mossheart", "a65a12", "cooldown" } }
  local mocks = {}
  for i, m in ipairs(MOCK) do
    local f = Box(box, "222222", "000000")
    f:SetSize(130, 34)
    f:SetPoint("TOPLEFT", 14, -12 - (i - 1) * 38)
    local hp = Tex(f, m[2], "ARTWORK"); hp:SetPoint("TOPLEFT", 1, -1); hp:SetPoint("BOTTOMRIGHT", -1, 6)
    local mp = Tex(f, "2d4fbf", "ARTWORK"); mp:SetPoint("BOTTOMLEFT", 1, 1); mp:SetPoint("BOTTOMRIGHT", -1, 1); mp:SetHeight(4)
    local n = Text(f, 11, "ffffff"); n:SetPoint("LEFT", 6, 2); n:SetText(m[1])
    f.strip = CreateFrame("Frame", nil, box)
    f.strip:SetFrameLevel(f:GetFrameLevel() + 5)
    f.strip.icons = {}
    f.state = m[3]
    mocks[i] = f
  end

  local fl = Text(right, 10, COL.muted); fl:SetText("FRAMES FOUND")
  fl:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -12)
  local found = Box(right, COL.card, COL.line)
  found:SetPoint("TOPLEFT", fl, "BOTTOMLEFT", 0, -8); found:SetPoint("RIGHT")
  found:SetHeight(30 * 5 + 2)
  local frows = {}
  for i = 1, 5 do
    local r = CreateFrame("Frame", nil, found)
    r:SetHeight(30)
    r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 30); r:SetPoint("RIGHT", -1, 0)
    local ln = Tex(r, COL.rowLine, "BORDER"); ln:SetHeight(1); ln:SetPoint("BOTTOMLEFT"); ln:SetPoint("BOTTOMRIGHT")
    r.dot = Tex(r, COL.green, "ARTWORK"); r.dot:SetSize(8, 8); r.dot:SetPoint("LEFT", 10, 0)
    r.who = Text(r, 11.5, COL.text); r.who:SetPoint("LEFT", r.dot, "RIGHT", 8, 0)
    r.where = Text(r, 11.5, COL.muted, "RIGHT"); r.where:SetPoint("RIGHT", -10, 0)
    frows[i] = r
  end
  local patl = SmallLabel(right, "Frame name pattern (leave blank to auto-detect)")
  patl:SetPoint("TOPLEFT", found, "BOTTOMLEFT", 0, -12)
  local pat = Input(right, 100, 28, "e.g. ElvUF_PartyGroup1UnitButton%d", function(text)
    ns.Slash("frames " .. (text == "" and "clear" or text)); O.Refresh()
  end)
  pat:SetPoint("TOPLEFT", patl, "BOTTOMLEFT", 0, -4); pat:SetPoint("RIGHT")

  local function layoutMockStrip(f, icons)
    local P = ns.db.party
    local size, gap = P.size or 20, P.spacing or 2
    local dx, dy = 0, 0
    if P.grow == "left" then dx = -1 elseif P.grow == "up" then dy = 1 elseif P.grow == "down" then dy = -1 else dx = 1 end
    local strip = f.strip
    for i, spell in ipairs(icons) do
      local b = strip.icons[i]
      if not b then
        b = CreateFrame("Frame", nil, strip)
        b.border = Tex(b, "5a4020", "BACKGROUND"); b.border:SetAllPoints()
        b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetPoint("TOPLEFT", 1, -1); b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.text = Text(b, 10, "ffffff", "CENTER"); b.text:SetPoint("CENTER")
        b.mark = Text(b, 10, COL.gold); b.mark:SetPoint("TOPRIGHT", 0, 1); b.mark:SetText("?")
        strip.icons[i] = b
      end
      b:SetSize(size, size)
      b:ClearAllPoints()
      local off = (i - 1) * (size + gap)
      local start = (dx < 0 and "RIGHT") or (dy > 0 and "BOTTOM") or (dy < 0 and "TOP") or "LEFT"
      b:SetPoint(start, strip, start, dx * off, dy * off)
      b.tex:SetTexture(Spells.IconOf(spell))
      b.tex:SetDesaturated(f.state == "cooldown")
      b.text:SetText((f.state == "cooldown" and P.timerText) and "3:42" or "")
      b.mark:SetShown(f.state == "assumed")
      b:Show()
    end
    for i = #icons + 1, #strip.icons do strip.icons[i]:Hide() end
    local n = #icons
    local long = n > 0 and (n * size + (n - 1) * gap) or 1
    if dx ~= 0 then strip:SetSize(long, size) else strip:SetSize(size, long) end
    -- The same SetPoint the real strips use.
    strip:ClearAllPoints()
    strip:SetPoint(P.point or "LEFT", f, P.relativePoint or "RIGHT", P.x or 0, P.y or 0)
  end

  refreshers.party = function()
    local P = ns.db.party
    mode:Set(P.mode); pt:Set(P.point); rp:Set(P.relativePoint)
    for _, s in ipairs(steps) do s:Set(get(s.opt)) end
    grow:Set(P.grow); timer:Set(P.timerText); selfc:Set(P.self)
    pat:SetValue(P.framePattern or "")

    local icons = {}
    for _, s in ipairs(UI.SortedSpells()) do if #icons < 3 then icons[#icons + 1] = s end end
    if #icons == 0 and ns.db.spells.innervate then icons[1] = ns.db.spells.innervate end
    for i, f in ipairs(mocks) do
      local show = (i > 1 or P.self) and #icons > 0
      f.strip:SetShown(show)
      if show then layoutMockStrip(f, icons) end
    end
    local alpha = P.mode == "frames" and 1 or 0.45
    box:SetAlpha(alpha)

    -- Frames found
    local members = {}
    local inParty = UI.Context() == "party"
    if inParty then
      for guid, m in pairs(ns.roster) do members[#members + 1] = { guid = guid, m = m } end
      table.sort(members, function(a, b) return (a.m.unit or "") < (b.m.unit or "") end)
    end
    for i, r in ipairs(frows) do
      local e = members[i]
      if i == 1 and not inParty then
        r:Show(); r.dot:SetColorTexture(rgb(COL.knobOff))
        r.who:SetText(UI.Context() == "raid" and "In a raid" or "Not in a party")
        Color(r.who, COL.muted)
        r.where:SetText(UI.Context() == "raid" and "the window is used" or "Test mode previews on your frames")
      elseif e then
        r:Show()
        r.who:SetText(e.m.name or "?"); Color(r.who, classColorHex(e.m.class))
        local where, dot
        if F.Skipped(e.guid) then
          where = (ns.db.show.self == false) and "Include yourself is off" or "Icons on your frame are off"
          dot = COL.knobOff
        elseif P.mode ~= "frames" then where, dot = "Window mode", COL.knobOff
        elseif F.attached[e.guid] then where, dot = F.source[e.guid] or "Found", COL.green
        elseif F.missing[e.guid] then where, dot = "Not found: shown in the window", COL.amber
        else where, dot = "No tracked spells", COL.knobOff end
        r.where:SetText(where); r.dot:SetColorTexture(rgb(dot))
      else
        r:Hide()
      end
    end
  end
end

---------------------------------------------------------------------------
-- Alerts & sync tab
---------------------------------------------------------------------------
local function Card(parent)
  return Box(parent, COL.card, COL.line)
end

local function ChatLine(parent, text)
  local b = Box(parent, COL.input, COL.rowLine)
  b:SetHeight(30)
  local t = Text(b, 12, COL.offText); t:SetPoint("LEFT", 10, 0); t:SetText(text)
  return b
end

local function buildAlerts(p)
  local h = Heading(p, "Alerts and sync"); h:SetPoint("TOPLEFT")

  -- Ready alert
  local c1 = Card(p)
  c1:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -12); c1:SetPoint("RIGHT")
  c1:SetHeight(130)
  local t1 = Toggle(c1, "Ready alert", function(v) set("readyalert", v) end); t1:SetPoint("TOPLEFT", 14, -16)
  local n1 = Text(c1, 13, COL.text); n1:SetPoint("TOPLEFT", t1, "TOPRIGHT", 12, 3); n1:SetText("When a cooldown is ready")
  local d1 = Muted(c1, "Prints a line in chat.", 11); d1:SetPoint("TOPLEFT", n1, "BOTTOMLEFT", 0, -3)
  local sound = Check(c1, "Play a sound", function(v) set("readysound", v) end); sound:SetPoint("TOPRIGHT", -14, -16)
  local ex1 = ChatLine(c1, "|cff66ccffForeverCDs|r: Innervate ready: |cffff9a3dLeafwind|r")
  ex1:SetPoint("TOPLEFT", 14, -50); ex1:SetPoint("RIGHT", -14, 0)
  local only = SmallLabel(c1, "Only for"); only:SetPoint("TOPLEFT", ex1, "BOTTOMLEFT", 0, -14)
  local chips = {}
  local addP = Input(c1, 130, 24, "Add a player...", function(text)
    for n in text:gmatch("[^%s,]+") do ns.db.alerts.players[n:lower()] = true end
    c1.addP:SetText(""); O.Refresh()
  end)
  c1.addP = addP
  local everyone = Muted(c1, "Empty = everyone", 11)

  -- Cast alert
  local c2 = Card(p)
  c2:SetPoint("TOPLEFT", c1, "BOTTOMLEFT", 0, -12); c2:SetPoint("RIGHT")
  c2:SetHeight(96)
  local t2 = Toggle(c2, "Cast alert", function(v) set("castalert", v) end); t2:SetPoint("TOPLEFT", 14, -16)
  local n2 = Text(c2, 13, COL.text); n2:SetPoint("TOPLEFT", t2, "TOPRIGHT", 12, 3); n2:SetText("When a tracked spell is cast")
  local d2 = Muted(c2, "Names the target when the buff is seen.", 11); d2:SetPoint("TOPLEFT", n2, "BOTTOMLEFT", 0, -3)
  local ex2 = ChatLine(c2, "|cff66ccffForeverCDs|r: |cffff9a3dLeafwind|r cast Innervate on |cfff2f2f2Mendi|r")
  ex2:SetPoint("TOPLEFT", 14, -50); ex2:SetPoint("RIGHT", -14, 0)

  -- Sync and debug, side by side
  local function smallCard(title, desc, onChange)
    local c = Card(p)
    c:SetHeight(104)
    local t = Toggle(c, title, onChange); t:SetPoint("TOPLEFT", 14, -16)
    local n = Text(c, 12, COL.text); n:SetPoint("LEFT", t, "RIGHT", 12, 0); n:SetPoint("RIGHT", c, "RIGHT", -10, 0)
    n:SetWordWrap(false); n:SetText(title)
    local d = Muted(c, desc, 11)
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -10); d:SetPoint("RIGHT", -14, 0)
    d:SetSpacing(3)
    c.toggle = t
    return c
  end
  local c3 = smallCard("Share with other ForeverCDs users",
    "Sends your own casts to the group. Fills gaps when someone is out of range. Best effort: messages can be blocked during boss fights.",
    function(v) set("sync", v) end)
  local c4 = smallCard("Debug log",
    "Prints every group cast: unit, GUID, spell ID, name, and what was secret. Turn on before sending a bug report.",
    function(v) ns.debug = v; O.Refresh() end)
  c3:SetPoint("TOPLEFT", c2, "BOTTOMLEFT", 0, -12)
  c3:SetPoint("RIGHT", c2, "CENTER", -6, 0)
  c4:SetPoint("TOPLEFT", c3, "TOPRIGHT", 12, 0)
  c4:SetPoint("RIGHT", c2, "RIGHT")

  local reset = Button(p, "Reset options (keeps your spells)", "ghost", 230, 28, function()
    ns.ResetOptions(); O.Refresh()
  end)
  reset:SetPoint("BOTTOMRIGHT")

  refreshers.alerts = function()
    local A = ns.db.alerts
    t1:Set(A.ready); sound:Set(A.readySound); t2:Set(A.cast)
    c3.toggle:Set(ns.db.sync); c4.toggle:Set(ns.debug)
    -- Player chips
    local names = {}
    for n in pairs(A.players or {}) do names[#names + 1] = n end
    table.sort(names)
    for _, c in ipairs(chips) do c:Hide() end
    local prev
    for i, n in ipairs(names) do
      local chip = chips[i]
      if not chip then
        chip = Box(c1, COL.raised, COL.line2)
        chip:SetHeight(24)
        chip.text = Text(chip, 12, "ff9a3d"); chip.text:SetPoint("LEFT", 10, 0)
        chip.x = Button(chip, "x", "secondary", 18, 18, nil)
        chip.x:SetPoint("RIGHT", -3, 0)
        SetBox(chip.x, COL.raised, COL.raised)
        chips[i] = chip
      end
      local display = n:sub(1, 1):upper() .. n:sub(2)
      chip.text:SetText(display)
      chip:SetWidth((chip.text:GetStringWidth() or 40) + 36)
      chip.x:SetScript("OnClick", function() A.players[n] = nil; O.Refresh() end)
      chip:ClearAllPoints()
      if prev then chip:SetPoint("LEFT", prev, "RIGHT", 6, 0) else chip:SetPoint("LEFT", only, "RIGHT", 10, 0) end
      chip:Show()
      prev = chip
    end
    addP:ClearAllPoints()
    if prev then addP:SetPoint("LEFT", prev, "RIGHT", 6, 0) else addP:SetPoint("LEFT", only, "RIGHT", 10, 0) end
    everyone:ClearAllPoints(); everyone:SetPoint("LEFT", addP, "RIGHT", 10, 0)
    everyone:SetShown(#names == 0)
  end
end

---------------------------------------------------------------------------
-- Build, refresh, register
---------------------------------------------------------------------------
local function build()
  if root then return end
  root = Box(panel, COL.bg, COL.line)
  root:SetAllPoints()
  local header = buildHeader()
  local rail = buildRail(header)
  buildSpells(newPage(rail, "spells"))
  buildWindow(newPage(rail, "window"))
  buildParty(newPage(rail, "party"))
  buildAlerts(newPage(rail, "alerts"))
  -- Keep live bits (group counts, frames found) current while open.
  local acc = 0
  root:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc >= 1 then acc = 0; O.Refresh() end
  end)
  selectTab(current)
end

function O.Refresh()
  if not root or not panel:IsVisible() or not ns.db then return end
  refreshers.header()
  local r = refreshers[current]
  if r then r() end
end
ns.RefreshPanel = O.Refresh

function ns.RegisterPanel()
  panel = CreateFrame("Frame")
  panel.name = "ForeverCDs"
  panel:SetScript("OnShow", function() build(); O.Refresh() end)
  if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

function ns.OpenPanel()
  if category and Settings and Settings.OpenToCategory then
    ns.safe(Settings.OpenToCategory, category:GetID())
    return true
  elseif panel and InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    return true
  end
  return false
end
