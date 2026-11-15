-- ForeverCDs: optional addon-message sync (off by default).
-- A player running ForeverCDs broadcasts their own tracked casts:
--   C|<spellKey>|<remainingSeconds>
-- Midnight may block addon messages during encounters, so sends are best effort.
local _, ns = ...
local S = {}
ns.Sync = S

S.PREFIX = "FCDS"
S.RATE = 2          -- at most one message per spell per 2 s
S.lastSent = {}

function S.Register()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    ns.safe(C_ChatInfo.RegisterAddonMessagePrefix, S.PREFIX)
  end
end

local function channel()
  if ns.plain(ns.safe(IsInRaid), "boolean") then return "RAID" end
  if ns.plain(ns.safe(IsInGroup), "boolean") then return "PARTY" end
  return nil
end

function S.Send(spellKey, remaining)
  if not ns.db or not ns.db.sync then return end
  local ch = channel()
  if not ch or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end
  local now = ns.Now()
  if S.lastSent[spellKey] and now - S.lastSent[spellKey] < S.RATE then return end
  S.lastSent[spellKey] = now
  local msg = ("C|%s|%d"):format(spellKey, math.floor((remaining or 0) + 0.5))
  ns.safe(C_ChatInfo.SendAddonMessage, S.PREFIX, msg, ch)
end

-- Parse and validate one message. Returns key, remaining or nil.
function S.Parse(msg)
  if type(msg) ~= "string" or #msg > 64 then return nil end
  local key, rem = msg:match("^C|([%w]+)|(%d%d?%d?%d?)$")
  if not key then return nil end
  rem = tonumber(rem)
  if not rem or rem > 7200 then return nil end
  return key, rem
end

function S.OnMessage(prefix, msg, _, sender)
  if not ns.db or not ns.db.sync then return end
  if ns.isSecret(prefix) or prefix ~= S.PREFIX then return end
  if ns.isSecret(msg) or ns.isSecret(sender) then return end
  local key, rem = S.Parse(msg)
  if not key then return end
  local name = sender
  if Ambiguate then name = ns.safe(Ambiguate, sender, "none") or sender end
  local guid = ns.Tracker.GUIDByName(name)
  if not guid or guid == ns.Tracker.playerGUID then return end
  ns.Debug(("sync from %s: %s %ss"):format(tostring(name), key, tostring(rem)))
  ns.Tracker.OnSync(guid, key, rem)
end
