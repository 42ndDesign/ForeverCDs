-- ForeverCDs: shared helpers. Every value read from a unit or spell API may be
-- a secret value on the Forever client, so nothing here compares a value
-- before checking it.
local ADDON, ns = ...
ns.ADDON = ADDON or "ForeverCDs"

local select, type, pcall, unpack = select, type, pcall, unpack or table.unpack

-- True when v is a secret value (only on clients that have issecretvalue).
function ns.isSecret(v)
  local f = issecretvalue
  if not f then return false end
  local ok, r = pcall(f, v)
  return ok and r and true or false
end

local function pack(...) return { n = select("#", ...), ... } end

-- Call fn safely: returns its results, or nothing if fn is missing or errors.
function ns.safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = pack(pcall(fn, ...))
  if not r[1] then return nil end
  return unpack(r, 2, r.n)
end

-- v if it is readable and of type t, else nil. A t that is not a type name is
-- ignored, so a stray second return from ns.safe(...) can't reject v.
function ns.plain(v, t)
  if ns.isSecret(v) or v == nil then return nil end
  if type(t) == "string" and type(v) ~= t then return nil end
  return v
end

-- Read a field of a table that may be secret or may error on access.
function ns.field(tbl, key, t)
  if ns.isSecret(tbl) or type(tbl) ~= "table" then return nil end
  local ok, v = pcall(function() return tbl[key] end)
  if not ok then return nil end
  return ns.plain(v, t)
end

function ns.Now()
  return (GetTime and GetTime()) or os.clock()
end

function ns.Wall()
  return (time and time()) or os.time()
end

-- "m:ss" at a minute or more, else whole seconds.
function ns.TimeText(sec)
  if not sec or sec <= 0 then return "" end
  if sec >= 60 then
    local s = math.floor(sec + 0.5)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
  end
  return tostring(math.ceil(sec))
end

-- Readable GUID for a unit token, or nil.
function ns.UnitGUIDSafe(unit)
  return ns.plain(ns.safe(UnitGUID, unit), "string")
end

-- Group unit tokens only: player, party1-4, raid1-40.
function ns.IsGroupUnit(unit)
  if type(unit) ~= "string" or ns.isSecret(unit) then return false end
  if unit == "player" then return true end
  local n = unit:match("^party(%d)$")
  if n then n = tonumber(n); return n >= 1 and n <= 4 end
  n = unit:match("^raid(%d+)$")
  if n then n = tonumber(n); return n >= 1 and n <= 40 end
  return false
end

function ns.ClassColor(class)
  local c = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[class]
  if c then return c.r, c.g, c.b end
  return 0.8, 0.8, 0.8
end

function ns.Print(msg)
  local text = "|cff66ccffForeverCDs|r: " .. tostring(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(text) else print(text) end
end

-- Debug logging (toggled by /fcds debug).
ns.debug = false
function ns.Debug(msg)
  if ns.debug then ns.Print("|cff999999[debug]|r " .. tostring(msg)) end
end

-- Normalise a spell key: "Mana Tide Totem" -> "manatidetotem".
function ns.KeyFor(name)
  return (tostring(name):lower():gsub("[^%w]", ""))
end
