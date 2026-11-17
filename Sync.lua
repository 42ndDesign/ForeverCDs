-- ForeverCDs: cooldown sharing between players running ForeverCDs.
--
-- Forever hides other players' spells from addons in combat, so the reliable
-- source for a group member's cooldown is that member's own client. Each player
-- reports every tracked spell of their class, whether or not they have it
-- switched on themselves:
--   H|2|key=value,key=value   state: seconds left, 0 ready, ? unknown, - not known
--   R|2                       "send me your state" (joining a group, /reload)
--   C|key|seconds             one cast, from v0.1.x; still accepted
-- The state is sent when it changes, every HEARTBEAT seconds, and in reply to a
-- request. A send the client refuses (addon messages can be blocked during boss
-- fights) is retried, and the seconds left are worked out at send time, so a
-- late report is still right.
local _, ns = ...
local S = {}
ns.Sync = S

S.PREFIX = "FCDS"
S.PROTO = 2
S.HEARTBEAT = 120    -- resend the state this often while grouped
S.RETRY = 5          -- after a refused send
S.REPLY_MIN, S.REPLY_MAX = 1, 3   -- random wait before answering a request
S.MAX_LEN = 240      -- addon messages carry 255 bytes

S.peers = {}         -- [guid] = { t, proto, known = { [key] = true | false } }

local st = {}
function S.Reset()
  S.peers = {}
  st = { sentSig = nil, lastHello = -math.huge, retryAt = nil, replyAt = nil,
         wantRequest = false, requestAt = 0, hadChannel = false }
end
S.Reset()

function S.Register()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    ns.safe(C_ChatInfo.RegisterAddonMessagePrefix, S.PREFIX)
  end
end

local function channel()
  local home = LE_PARTY_CATEGORY_HOME
  local inst = LE_PARTY_CATEGORY_INSTANCE
  if inst and ns.plain(ns.safe(IsInGroup, inst), "boolean")
      and not ns.plain(ns.safe(IsInGroup, home), "boolean") then
    return "INSTANCE_CHAT"
  end
  if ns.plain(ns.safe(IsInRaid), "boolean") then return "RAID" end
  if ns.plain(ns.safe(IsInGroup), "boolean") then return "PARTY" end
  return nil
end

local function jitter(lo, hi) return lo + math.random() * (hi - lo) end

---------------------------------------------------------------------------
-- Our own state
---------------------------------------------------------------------------
-- Every tracked spell of our class, sorted by key: { key, value } with value a
-- number of seconds, "?" or "-". Also returns a signature that changes only when
-- the state does (not as the seconds count down).
function S.OwnState(now)
  now = now or ns.Now()
  local T, TL = ns.Tracker, ns.Talents
  local _, class = ns.safe(UnitClass, "player")
  class = ns.plain(class, "string")
  local me = T.playerGUID or ns.UnitGUIDSafe("player")
  local out, sig = {}, {}
  if not class or not ns.db or type(ns.db.spells) ~= "table" then return out, "" end
  local keys = {}
  for key, spell in pairs(ns.db.spells) do
    if type(spell) == "table" and spell.class == class and key:match("^%w+$") then keys[#keys + 1] = key end
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local spell = ns.db.spells[key]
    local has = TL and TL.OwnSpellbook and TL.OwnSpellbook(spell)
    if has == false then
      out[#out + 1] = { key, "-" }; sig[#sig + 1] = key .. "-"
    elseif has == true then
      local rec = me and ns.cds[me] and ns.cds[me][key]
      if rec and rec.duration > 0 and rec.start + rec.duration > now then
        local left = math.min(7200, math.ceil(rec.start + rec.duration - now))
        out[#out + 1] = { key, left }
        sig[#sig + 1] = key .. "@" .. math.floor(rec.start + rec.duration)
      elseif rec then
        out[#out + 1] = { key, 0 }; sig[#sig + 1] = key .. "0"
      else
        out[#out + 1] = { key, "?" }; sig[#sig + 1] = key .. "?"
      end
    end
    -- An unreadable spellbook claims nothing.
  end
  return out, table.concat(sig, ",")
end

-- Hello messages for a state, split to fit the message size.
function S.Encode(entries)
  local head = "H|" .. S.PROTO .. "|"
  local msgs, cur = {}, {}
  local len = #head
  for _, e in ipairs(entries) do
    local part = e[1] .. "=" .. tostring(e[2])
    if #cur > 0 and len + 1 + #part > S.MAX_LEN then
      msgs[#msgs + 1] = head .. table.concat(cur, ",")
      cur, len = {}, #head
    end
    cur[#cur + 1] = part
    len = len + #part + (#cur > 1 and 1 or 0)
  end
  msgs[#msgs + 1] = head .. table.concat(cur, ",")
  return msgs
end

---------------------------------------------------------------------------
-- Parsing
---------------------------------------------------------------------------
-- Legacy one-cast message. Returns key, remaining or nil.
function S.Parse(msg)
  if type(msg) ~= "string" or #msg > 64 then return nil end
  local key, rem = msg:match("^C|([%w]+)|(%d%d?%d?%d?)$")
  if not key then return nil end
  rem = tonumber(rem)
  if not rem or rem > 7200 then return nil end
  return key, rem
end

-- Any message. Returns { kind = "C"|"H"|"R", ... } or nil.
function S.Decode(msg)
  if type(msg) ~= "string" or #msg > 255 then return nil end
  local key, rem = S.Parse(msg)
  if key then return { kind = "C", key = key, rem = rem } end
  local proto = msg:match("^R|(%d%d?)$")
  if proto then return { kind = "R", proto = tonumber(proto) } end
  local body
  proto, body = msg:match("^H|(%d%d?)|(.*)$")
  if not proto then return nil end
  local entries = {}
  for part in body:gmatch("[^,]+") do
    local k, v = part:match("^(%w+)=(.+)$")
    if k and #k <= 48 then
      if v == "-" or v == "?" then
        entries[#entries + 1] = { k, v }
      elseif v:match("^%d%d?%d?%d?$") and tonumber(v) <= 7200 then
        entries[#entries + 1] = { k, tonumber(v) }
      end
    end
  end
  return { kind = "H", proto = tonumber(proto), entries = entries }
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
-- True when the client accepted the message.
local function sendRaw(msg, ch)
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, S.PREFIX, msg, ch)
  if not ok then return false end
  if res == nil or res == true then return true end
  if ns.isSecret(res) then return false end
  local codes = Enum and Enum.SendAddonMessageResult
  if type(codes) == "table" and codes.Success ~= nil then return res == codes.Success end
  return res == 0
end
S.sendRaw = sendRaw

function S.Tick(now)
  now = now or ns.Now()
  if not ns.db or not ns.db.sync then st.hadChannel = false; return end
  local ch = channel()
  if not ch then st.hadChannel = false; return end
  if not st.hadChannel then
    -- Just joined (or logged in grouped): ask for everyone's state, send ours.
    st.hadChannel = true
    st.wantRequest, st.requestAt = true, now + jitter(0, 1)
    st.sentSig = nil
  end
  if st.retryAt and now < st.retryAt then return end
  st.retryAt = nil

  if st.wantRequest and now >= st.requestAt then
    if sendRaw("R|" .. S.PROTO, ch) then
      st.wantRequest = false
      ns.Debug("sync: asked the group for their cooldowns")
    else
      st.retryAt = now + S.RETRY; return
    end
  end

  local entries, sig = S.OwnState(now)
  local due = sig ~= st.sentSig or now - st.lastHello >= S.HEARTBEAT
    or (st.replyAt and now >= st.replyAt)
  if not due then return end
  for _, msg in ipairs(S.Encode(entries)) do
    if not sendRaw(msg, ch) then
      ns.Debug("sync: send refused, retrying in " .. S.RETRY .. " s")
      st.retryAt = now + S.RETRY
      return
    end
    ns.Debug("sync sent: " .. msg)
  end
  st.sentSig, st.lastHello, st.replyAt = sig, now, nil
end

function S.Start()
  if not S.ticker and C_Timer and C_Timer.NewTicker then
    S.ticker = C_Timer.NewTicker(1, function() ns.safe(S.Tick) end)
  end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
-- What a member's own ForeverCDs says about a spell: true (has it), false
-- (doesn't), nil (no report).
function S.Known(guid, key)
  local p = S.peers[guid]
  if not p then return nil end
  return p.known[key]
end

function S.OnMessage(prefix, msg, _, sender)
  if not ns.db or not ns.db.sync then return end
  if ns.isSecret(prefix) or prefix ~= S.PREFIX then return end
  if ns.isSecret(msg) or ns.isSecret(sender) then return end
  local m = S.Decode(msg)
  if not m then return end
  local name = sender
  if Ambiguate then name = ns.plain(ns.safe(Ambiguate, sender, "none"), "string") or sender end
  local T = ns.Tracker
  local guid = T.GUIDByName(name)
  if not guid or guid == T.playerGUID then return end
  local now = ns.Now()
  local p = S.peers[guid] or { known = {} }
  S.peers[guid] = p
  p.t, p.proto = now, m.proto or p.proto or 1

  if m.kind == "R" then
    ns.Debug(("sync: %s asked for our cooldowns"):format(tostring(name)))
    local at = now + jitter(S.REPLY_MIN, S.REPLY_MAX)
    if not st.replyAt or at < st.replyAt then st.replyAt = at end
  elseif m.kind == "C" then
    ns.Debug(("sync from %s: %s %ss"):format(tostring(name), m.key, tostring(m.rem)))
    p.known[m.key] = true
    T.OnSync(guid, m.key, m.rem)
  else
    ns.Debug(("sync from %s: %s"):format(tostring(name), msg))
    for _, e in ipairs(m.entries) do
      local key, v = e[1], e[2]
      if v == "-" then
        p.known[key] = false
      else
        p.known[key] = true
        if type(v) == "number" then T.OnSync(guid, key, v) end
      end
    end
  end
  if T.onChange then T.onChange() end
end
