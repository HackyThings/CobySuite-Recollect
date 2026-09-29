-------------------------------------------------------------------------------
-- Curator.Protocol: the wire format (curator spec, "Protocol": message types,
-- handshake challenge, payload encoding)
--
-- A message is fields joined by SEP ("~", which no field can hold: IDs,
-- version strings, "Name-Realm", Base64): the type letter, the mode ("l"
-- live, "t" test), the addressee (a curator ID, "*" for everyone, or "a" for
-- the author), then the type's own fields. The last field of a D (a chunk of
-- the payload) is never split, so a payload may hold anything.
--
-- A collection's payload is the snapshot table, CBOR-serialized, Deflate-
-- compressed and Base64-encoded (C_EncodingUtil; the Step 1 byte test may
-- later allow raw bytes), cut into chunks so every message stays within
-- MAX_MESSAGE bytes. The checksum is FNV-1a, 32 bits, as 8 hex digits: over
-- the whole encoded payload for S and K, and over salt .. ownName ..
-- bucketSlice for the handshake (a weak installation check, never trust).
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
-- covers the messages (types, fields, order), the packing (CBOR, Deflate,
-- Base64, chunking, the checksum) and the payload's shape (records, stamps,
-- contexts, quests, notes). Raise it only when a change breaks an older
-- client: a field removed, moved or read differently, or the packing
-- changed. A field added that the other side can do without keeps it (the
-- author's console is always the newest side, so it reads a payload with or
-- without the field; 0.0.1b's versions.schema and frozen blocks are such an
-- addition). An addon release that changes none of this keeps it, so the
-- author on the next unreleased version still pulls curators on the last
-- release. It rides in every R and O as the "protocol" field.
Protocol.VERSION = 1
Protocol.SEP = "~"
Protocol.LIVE, Protocol.TEST = "l", "t"
Protocol.AUTHOR = "a"      -- the addressee of every curator-to-author message
Protocol.ALL = "*"
-- 255 bytes with the prefix and its separator (AceComm's limit; Step 1 T4
-- measures the real one)
Protocol.MAX_MESSAGE = 255 - #Curator.Const.PREFIX - 1
-- What the author accepts before decoding: the 1 MB cap plus a margin
-- (Base64 grows a third; a full store rarely compresses less than 3 to 1)
Protocol.MAX_PAYLOAD = 1024 * 1024 + 512 * 1024
Protocol.MAX_DECODED = 8 * 1024 * 1024

-- How many fields each type has after the header (a D's payload is last)
Protocol.FIELDS = { H = 6, R = 12, O = 5, Q = 2, S = 5, D = 3, N = 2, K = 2, V = 2, X = 2, L = 1 }

Protocol.seams = {
  Serialize = function(value) return C_EncodingUtil.SerializeCBOR(value) end,
  Deserialize = function(text) return C_EncodingUtil.DeserializeCBOR(text) end,
  Compress = function(text) return C_EncodingUtil.CompressString(text) end,
  Decompress = function(text) return C_EncodingUtil.DecompressString(text) end,
  Encode64 = function(text) return C_EncodingUtil.EncodeBase64(text) end,
  Decode64 = function(text) return C_EncodingUtil.DecodeBase64(text) end,
  Xor = function(a, b) return bit.bxor(a, b) end,
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

-- Decode(text): { kind, mode, to, fields = { ... } }, or nil for anything
-- that isn't a known message
function Protocol.Decode(text)
  if type(text) ~= "string" then return nil end
  local kind, mode, to, rest = text:match("^(%u)~([lt])~([^~]*)~?(.*)$")
  local count = kind and Protocol.FIELDS[kind]
  if not count then return nil end
  local fields, from = {}, 1
  for i = 1, count do
    if i == count then
      fields[i] = rest:sub(from)
    else
      local at = rest:find(Protocol.SEP, from, true)
      if not at then
        fields[i] = rest:sub(from)
        from = #rest + 2
      else
        fields[i] = rest:sub(from, at - 1)
        from = at + 1
      end
    end
  end
  return { kind = kind, mode = mode, to = to, fields = fields }
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
-- Pack(tbl): the encoded payload text, or nil and why
function Protocol.Pack(tbl)
  local seams = Protocol.seams
  local ok, serialized = pcall(seams.Serialize, tbl)
  if not ok or type(serialized) ~= "string" then return nil, "serialize failed" end
  local okZip, zipped = pcall(seams.Compress, serialized)
  if not okZip or type(zipped) ~= "string" then return nil, "compress failed" end
  local okEnc, encoded = pcall(seams.Encode64, zipped)
  if not okEnc or type(encoded) ~= "string" then return nil, "encode failed" end
  return encoded
end

-- Unpack(text): the table, or nil and why. The received size is checked
-- before anything is decoded, the decoded size after decompressing, and the
-- deserializer runs under pcall.
function Protocol.Unpack(text)
  if type(text) ~= "string" or #text > Protocol.MAX_PAYLOAD then return nil, "too large" end
  local seams = Protocol.seams
  local ok, zipped = pcall(seams.Decode64, text)
  if not ok or type(zipped) ~= "string" then return nil, "decode failed" end
  local okZip, serialized = pcall(seams.Decompress, zipped)
  if not okZip or type(serialized) ~= "string" then return nil, "decompress failed" end
  if #serialized > Protocol.MAX_DECODED then return nil, "decoded too large" end
  local okDes, value = pcall(seams.Deserialize, serialized)
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

-- The most chunks a request may have (the receive limit)
function Protocol.MaxChunks(requestID)
  return math.ceil(Protocol.MAX_PAYLOAD / Protocol.ChunkSize(requestID))
end

-- A comma list of numbers or IDs, and back
function Protocol.List(list)
  return table.concat(list or {}, ",")
end

-- ListWithin(list, room): the list's first entries that fit room bytes as a
-- List, and how many of them (the rest go in a later message)
function Protocol.ListWithin(list, room)
  local out, used = {}, 0
  for _, item in ipairs(list or {}) do
    local add = #tostring(item) + (#out > 0 and 1 or 0)
    if used + add > room then break end
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
