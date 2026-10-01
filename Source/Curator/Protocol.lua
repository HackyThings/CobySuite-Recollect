-------------------------------------------------------------------------------
-- Curator.Protocol: the wire format (curator spec, "Protocol": message types,
-- handshake challenge, payload encoding)
--
-- A message is fields joined by SEP ("~", which no field can hold: IDs,
-- version strings, "Name-Realm", Base64): the type letter, the mode, the
-- addressee (a curator ID, "*" for everyone, or "a" for the author), then
-- the type's own fields. The last field of a D (a chunk of the payload) is
-- never split.
--
-- Protocol 2 (security design B, 2026-09-30): the mode letter is capital,
-- "L" live and "T" test. A client of protocol 1 (Recollect 0.0.2 and older)
-- reads only "l" and "t", so it drops every protocol 2 message unread, and
-- nothing it sends is taken as more than a sighting (DecodeLegacy). The one
-- exception is the author's presence check to everyone, which keeps its
-- protocol 1 shape ("l" or "t") so an older client still answers and the
-- console can list it as "unsecure". Decode reads protocol 2 exactly: every
-- type has its field count and every field its pattern and bound
-- (Protocol.SHAPES), and anything else is no message at all, never read
-- another way.
--
-- A collection's payload is the snapshot table, CBOR-serialized and
-- Base64-encoded (C_EncodingUtil), cut into chunks so every message stays
-- within MAX_MESSAGE bytes. Nothing is compressed: a receiver that
-- decompresses can be handed a small payload that expands without bound
-- (review PAY-02), so a block is at most BLOCK_RAW bytes of CBOR (LARGE_RAW
-- in a pull the author asks to be large), and the author's side scans it
-- before decoding it (Unpack's preflight). The checksum is FNV-1a, 32 bits,
-- as 8 hex digits: over the whole encoded payload for S and K, and over
-- salt .. ownName .. bucketSlice for the handshake (a weak installation
-- check, never trust).
--
-- The encoding calls go through Protocol.seams (the offline suites script
-- them). Nothing here sends; Transport does.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host

local Protocol = {}
Curator.Protocol = Protocol

-- The transport version (Cobanyte, 2026-09-28): what the author's console
-- and a curator must share for a pull, whatever their addon versions. It
-- covers the messages (types, fields, order), the packing (CBOR, Base64,
-- chunking, the checksum; no Deflate since protocol 2) and the payload's shape (records, stamps,
-- contexts, quests, notes). Raise it only when a change breaks an older
-- client: a field removed, moved or read differently, or the packing
-- changed. A field added that the other side can do without keeps it (the
-- author's console is always the newest side, so it reads a payload with or
-- without the field; 0.0.1b's versions.schema and frozen blocks are such an
-- addition). An addon release that changes none of this keeps it, so the
-- author on the next unreleased version still pulls curators on the last
-- release. It rides in every R and O as the "protocol" field.
Protocol.VERSION = 2
Protocol.SEP = "~"
Protocol.LIVE, Protocol.TEST = "L", "T"
-- protocol 1's modes: the presence check to everyone still goes in them
Protocol.LEGACY_LIVE, Protocol.LEGACY_TEST = "l", "t"
Protocol.AUTHOR = "a"      -- the addressee of every curator-to-author message
Protocol.ALL = "*"
-- 255 bytes with the prefix and its separator (AceComm's limit; Step 1 T4
-- measures the real one)
Protocol.MAX_MESSAGE = 255 - #Curator.Const.PREFIX - 1
-- A block's size in CBOR bytes: what a pull carries by itself, and what a
-- pull the author asks to be large may (a frozen block, a big quest base);
-- and the most observations (findings, stamps, notes) one block holds
Protocol.BLOCK_RAW = 32 * 1024
Protocol.LARGE_RAW = 512 * 1024
Protocol.OBSERVATIONS = 256

-- EncodedSize(raw): Base64's length for raw bytes
function Protocol.EncodedSize(raw)
  return 4 * math.ceil(raw / 3)
end


-- A message type in words, for what players read (the diagnostic lines, the
-- dashboard's last message not answered)
Protocol.KIND_WORDS = { H = "a presence check", R = "a presence answer", O = "an online notice", L = "a leaving notice",
  Q = "a collection request", S = "a collection start", D = "a data part", N = "a request to send parts again",
  K = "an acknowledgement", V = "a saved report", X = "a cancel" }

-- How many fields each type has after the header (a D's payload is last)
Protocol.FIELDS = { H = 6, R = 12, O = 5, Q = 5, S = 5, D = 3, N = 2, K = 3, V = 5, X = 2, L = 1 }

Protocol.seams = {
  Serialize = function(value) return C_EncodingUtil.SerializeCBOR(value) end,
  Deserialize = function(text) return C_EncodingUtil.DeserializeCBOR(text) end,
  Encode64 = function(text) return C_EncodingUtil.EncodeBase64(text) end,
  Decode64 = function(text) return C_EncodingUtil.DecodeBase64(text) end,
  Xor = function(a, b) return bit.bxor(a, b) end,
}

-------------------------------------------------------------------------------
-- Field shapes
-------------------------------------------------------------------------------
local function Matches(pattern, max)
  return function(value) return #value <= max and value:find(pattern) ~= nil end
end
local function Optional(check)
  return function(value) return value == "" or check(value) end
end
local function Digits(max)
  return Matches("^%d+$", max)
end
local function OneOf(...)
  local set = {}
  for i = 1, select("#", ...) do set[select(i, ...)] = true end
  return function(value) return set[value] == true end
end
-- ListOf(check, most): a comma list of at most most items, each passing check ("" is empty)
local function ListOf(check, most)
  return function(value)
    if value == "" then return true end
    local n = 0
    for item in (value .. ","):gmatch("([^,]*),") do
      n = n + 1
      if n > most or not check(item) then return false end
    end
    return true
  end
end

-- A curator ID: letters and digits, 8 to 32 (the client makes 24 hex digits)
function Protocol.IsCuratorID(value)
  return type(value) == "string" and #value >= 8 and #value <= 32 and value:find("^%w+$") ~= nil
end
-- A request ID, as the author's console makes them ("q" .. seconds .. 4 hex digits)
function Protocol.IsRequest(value)
  return type(value) == "string" and #value <= 24 and value:find("^q%d+%x%x%x%x$") ~= nil
end
-- A store token the author hands out in Q ("s" .. number .. "." .. epoch)
function Protocol.IsStore(value)
  return type(value) == "string" and #value <= 24 and value:find("^s%d+%.%d+$") ~= nil
end

local NONCE = Matches("^%x%x%x%x%x%x%x%x%x%x%x%x$", 12)
local CHECKSUM = Matches("^%x%x%x%x%x%x%x%x$", 8)
-- a version as a client reports it: "?" or empty when it can't be read (a
-- data file missing: Host.Versions), which the author's row shows as it is
local VERSION_TEXT = Optional(Matches("^[%w%.%-_?]+$", 32))
local FORMAT = Optional(Digits(3))
local FLAG = OneOf("0", "1")
-- the most request IDs a list carries (an R's awaiting list, V's lists)
Protocol.LIST_MAX = 20
local REQUESTS = ListOf(Protocol.IsRequest, Protocol.LIST_MAX)
-- a record ID or stamp key ("v:1234@69933"), as K's list carries them
function Protocol.IsKey(value)
  return type(value) == "string" and #value >= 1 and #value <= 64 and value:find("^[%w:@%.%-_$]+$") ~= nil
end
local KEY = Protocol.IsKey
-- a reason: printable text with no separator or UI escape
local function Reason(value)
  return #value >= 1 and #value <= 80 and value:find("^[ -}]+$") ~= nil and not value:find("|", 1, true)
end
local function Info(value)
  return value:find("^refused:%a+$") ~= nil and #value <= 40
    or value:find("^records:%d+,confirms:%d+,notes:%d+,more:%d+$") ~= nil and #value <= 80
end
local function Base64(value)
  return #value <= Protocol.MAX_MESSAGE and value:find("^[%w+/=]*$") ~= nil
end

-- The addressees a type may carry: the author ("a"), a curator ID, or everyone
local TO_AUTHOR = function(to) return to == Protocol.AUTHOR end
local TO_CURATOR = Protocol.IsCuratorID
local function ToAny(to) return to == Protocol.AUTHOR or Protocol.IsCuratorID(to) end

-- SHAPES[kind] = { to = check, fields }: every protocol 2 message, exactly
Protocol.SHAPES = {
  H = { to = function(to) return to == Protocol.ALL or Protocol.IsCuratorID(to) end,
    NONCE, Digits(3), Optional(Digits(6)), Optional(Digits(9)), Optional(Digits(4)), Optional(NONCE) },
  R = { to = TO_AUTHOR, NONCE, Protocol.IsCuratorID, VERSION_TEXT, VERSION_TEXT, FORMAT, Digits(3), Optional(CHECKSUM),
    OneOf("on", "ask", "off", "nodata"), OneOf("idle", "resting", "moving", "combat", "lockdown"), Digits(9), Digits(10),
    REQUESTS },
  O = { to = TO_AUTHOR, Protocol.IsCuratorID, VERSION_TEXT, VERSION_TEXT, FORMAT, Digits(3) },
  L = { to = TO_AUTHOR, Protocol.IsCuratorID },
  Q = { to = TO_CURATOR, Protocol.IsRequest, FLAG, Protocol.IsStore, FLAG, FLAG },
  S = { to = TO_AUTHOR, Protocol.IsRequest, Digits(6), Digits(9), Optional(CHECKSUM), Info },
  D = { to = TO_AUTHOR, Protocol.IsRequest, Digits(6), Base64 },
  N = { to = TO_CURATOR, Protocol.IsRequest, ListOf(Digits(6), 40) },
  K = { to = TO_CURATOR, Protocol.IsRequest, CHECKSUM, ListOf(KEY, 20) },
  V = { to = TO_CURATOR, REQUESTS, REQUESTS, REQUESTS, REQUESTS, REQUESTS },
  X = { to = ToAny, Protocol.IsRequest, Reason },
}

-------------------------------------------------------------------------------
-- Messages
-------------------------------------------------------------------------------
-- Encode(kind, mode, to, ...): the message text, or nil when a field holds SEP
function Protocol.Encode(kind, mode, to, ...)
  local parts = { kind, mode, to }
  for i = 1, select("#", ...) do
    local field = select(i, ...)
    field = field == nil and "" or tostring(field)
    if i < select("#", ...) or kind ~= "D" then
      if field:find(Protocol.SEP, 1, true) then return nil end
    end
    parts[#parts + 1] = field
  end
  for i = 1, 3 do
    if tostring(parts[i]):find(Protocol.SEP, 1, true) then return nil end
  end
  local text = table.concat(parts, Protocol.SEP)
  -- the game refuses a longer message: never queue one
  if #text > Protocol.MAX_MESSAGE then return nil end
  return text
end

-- IsTest(mode): test mode, in either protocol's letter
function Protocol.IsTest(mode)
  return mode == Protocol.TEST or mode == Protocol.LEGACY_TEST
end

-- Split(rest, count): count fields, the last taking the rest; nil when
-- there are fewer
local function Split(rest, count)
  local fields, from = {}, 1
  for i = 1, count do
    if i == count then
      fields[i] = rest:sub(from)
    else
      local at = rest:find(Protocol.SEP, from, true)
      if not at then return nil end
      fields[i] = rest:sub(from, at - 1)
      from = at + 1
    end
  end
  return fields
end

-- Decode(text): a protocol 2 message, { kind, mode ("L" or "T"), to,
-- fields }, or nil for anything that isn't exactly one (Protocol.SHAPES).
-- An H in protocol 1's letters is read too (the presence check keeps that
-- shape), its mode given as protocol 2's and legacyShape set
function Protocol.Decode(text)
  if type(text) ~= "string" or #text > Protocol.MAX_MESSAGE then return nil end
  local kind, mode, to, rest = text:match("^(%u)~(%a)~([^~]*)~(.*)$")
  local shape = kind and Protocol.SHAPES[kind]
  if not shape then return nil end
  local legacyShape = false
  if mode ~= Protocol.LIVE and mode ~= Protocol.TEST then
    if kind ~= "H" or (mode ~= Protocol.LEGACY_LIVE and mode ~= Protocol.LEGACY_TEST) then return nil end
    mode, legacyShape = mode == Protocol.LEGACY_LIVE and Protocol.LIVE or Protocol.TEST, true
  end
  if not shape.to(to) then return nil end
  local fields = Split(rest, #shape)
  if not fields then return nil end
  for i, check in ipairs(shape) do
    if not check(fields[i]) then return nil end
  end
  return { kind = kind, mode = mode, to = to, fields = fields, legacyShape = legacyShape or nil }
end

-- DecodeLegacy(text): a protocol 1 R, O or L (Recollect 0.0.2 and older),
-- read only far enough to list its sender: { kind, mode, to, fields,
-- legacy = true }, every field cut to 64 bytes; nil for anything else.
-- Nothing but a sighting may come of it (security design S1)
Protocol.LEGACY_FIELDS = { R = 12, O = 5, L = 1 }
function Protocol.DecodeLegacy(text)
  if type(text) ~= "string" or #text > Protocol.MAX_MESSAGE then return nil end
  local kind, mode, to, rest = text:match("^([ROL])~([lt])~([^~]*)~(.*)$")
  local count = kind and Protocol.LEGACY_FIELDS[kind]
  if not count then return nil end
  local fields, from = {}, 1
  for i = 1, count do
    local at = i < count and rest:find(Protocol.SEP, from, true) or nil
    fields[i] = (at and rest:sub(from, at - 1) or rest:sub(from)):sub(1, 64)
    from = at and at + 1 or #rest + 2
  end
  return { kind = kind, mode = mode == "l" and Protocol.LIVE or Protocol.TEST, to = to:sub(1, 64), fields = fields,
    legacy = true }
end

-------------------------------------------------------------------------------
-- FNV-1a, 32 bits
-------------------------------------------------------------------------------
local TWO32 = 4294967296

-- XOR of two bytes without a bit library
local function Xor8(a, b)
  local out, place = 0, 1
  for _ = 1, 8 do
    local x, y = a % 2, b % 2
    if x ~= y then out = out + place end
    a, b, place = (a - x) / 2, (b - y) / 2, place * 2
  end
  return out
end

Protocol.CHECKSUM_START = 2166136261

-- The bit library's XOR when it works here (the game has one), else nil
local function BitXor()
  local xor = Protocol.seams.Xor
  local ok, value = pcall(xor, 5, 3)
  return ok and value == 6 and xor or nil
end

-- ChecksumUpdate(h, text, from, to): h over text:sub(from, to); the FNV
-- prime 16777619 is 2^24 + 403, so h * prime mod 2^32 stays exact in a double
function Protocol.ChecksumUpdate(h, text, from, to)
  local xor = BitXor()
  for i = from or 1, math.min(to or #text, #text) do
    local byte = text:byte(i)
    if xor then
      h = xor(h, byte) % TWO32
    else
      local low = h % 256
      h = h - low + Xor8(low, byte)
    end
    h = (h * 403 + (h % 256) * 16777216) % TWO32
  end
  return h
end

function Protocol.ChecksumText(h)
  return ("%08x"):format(h)
end

function Protocol.Checksum(text)
  return Protocol.ChecksumText(Protocol.ChecksumUpdate(Protocol.CHECKSUM_START, text))
end

-- The handshake answer: FNV-1a of salt .. ownName .. the bucket slice, or
-- nil when that bucket isn't shipped
function Protocol.Challenge(bucketIndex, offset, length, salt, ownName)
  local bucket = Host.Bucket(tonumber(bucketIndex))
  offset, length = tonumber(offset), tonumber(length)
  if not bucket or not offset or not length or length < 1 or length > 4096 then return nil end
  return Protocol.Checksum(tostring(salt) .. tostring(ownName) .. bucket:sub(offset, offset + length - 1))
end

-------------------------------------------------------------------------------
-- Payloads
-------------------------------------------------------------------------------
-- Pack(tbl): the encoded payload text and its size in CBOR bytes, or nil
-- and why
function Protocol.Pack(tbl)
  local seams = Protocol.seams
  local ok, serialized = pcall(seams.Serialize, tbl)
  if not ok or type(serialized) ~= "string" then return nil, "serialize failed" end
  local okEnc, encoded = pcall(seams.Encode64, serialized)
  if not okEnc or type(encoded) ~= "string" then return nil, "encode failed" end
  return encoded, #serialized
end

-- Unpack(text, preflight, maxRaw): the table, or nil and why. The received
-- size is checked before anything is decoded, the CBOR size after Base64,
-- then preflight(raw) (the author's scanner: true, or false and why) runs
-- before the native decoder ever sees it; without a preflight nothing is
-- decoded. maxRaw defaults to BLOCK_RAW
function Protocol.Unpack(text, preflight, maxRaw)
  maxRaw = maxRaw or Protocol.BLOCK_RAW
  if type(text) ~= "string" or #text > Protocol.EncodedSize(maxRaw) then return nil, "too large" end
  if type(preflight) ~= "function" then return nil, "no preflight scanner" end
  local seams = Protocol.seams
  local ok, raw = pcall(seams.Decode64, text)
  if not ok or type(raw) ~= "string" then return nil, "decode failed" end
  if #raw > maxRaw then return nil, "block too large" end
  local okScan, scanned, why = pcall(preflight, raw)
  if not okScan or scanned ~= true then return nil, "preflight: " .. tostring(okScan and why or scanned) end
  local okDes, value = pcall(seams.Deserialize, raw)
  if not okDes or type(value) ~= "table" then return nil, "deserialize failed" end
  return value
end

-- The chunk size for a request's D messages (the header takes the rest)
function Protocol.ChunkSize(requestID)
  local header = #Protocol.Encode("D", Protocol.LIVE, Protocol.AUTHOR, requestID, "99999", "")
  return Protocol.MAX_MESSAGE - header
end

-- Chunks(payload, requestID): the payload cut into D-sized pieces
function Protocol.Chunks(payload, requestID)
  local size, out = Protocol.ChunkSize(requestID), {}
  for from = 1, #payload, size do out[#out + 1] = payload:sub(from, from + size - 1) end
  if #out == 0 then out[1] = "" end
  return out
end

-- MaxChunks(requestID, maxRaw): the most chunks a request may have (the
-- receive limit) for blocks of at most maxRaw bytes (default LARGE_RAW)
function Protocol.MaxChunks(requestID, maxRaw)
  return math.ceil(Protocol.EncodedSize(maxRaw or Protocol.LARGE_RAW) / Protocol.ChunkSize(requestID))
end

-- A comma list of numbers or IDs, and back
function Protocol.List(list)
  return table.concat(list or {}, ",")
end

-- ListWithin(list, room, most): the list's first entries that fit room bytes
-- (and, given most, no more than that many) as a List, and how many of them
-- (the rest go in a later message)
function Protocol.ListWithin(list, room, most)
  local out, used = {}, 0
  for _, item in ipairs(list or {}) do
    local add = #tostring(item) + (#out > 0 and 1 or 0)
    if used + add > room or (most and #out >= most) then break end
    out[#out + 1] = tostring(item)
    used = used + add
  end
  return table.concat(out, ","), #out
end

function Protocol.ParseList(text)
  local out = {}
  for item in tostring(text or ""):gmatch("[^,]+") do out[#out + 1] = item end
  return out
end
