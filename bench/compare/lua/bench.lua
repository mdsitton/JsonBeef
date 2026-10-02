-- Lua JSON benchmark: <luajit|lua5.5> bench.lua cjson <input> <min-samples>
--   cjson - lua-cjson (OpenResty's fork) cjson.decode into Lua tables, with its defaults (nesting
--           limit 1000; numbers through strtoll, or its own strtod when they have a fraction or
--           exponent; an integer outside the signed 64-bit range saturates in strtoll, so values in
--           (2^63, 2^64) come back as 2^63 - 1). Under LuaJIT numbers are doubles; under Lua 5.5
--           integers become Lua integers.
-- ../build.sh lua builds cjson.so (and benchclock.so, a CLOCK_MONOTONIC clock: os.clock is CPU time)
-- per interpreter into rocks/luajit and rocks/lua5.5; this script picks the directory by interpreter.
-- The check pass uses a second cjson instance with decode_array_with_array_mt on, to tell empty
-- arrays from empty objects; the timed decodes use the defaults. A .ndjson input is a batch: its lines
-- are split before timing and each is parsed as its own document; one operation parses every line
-- once. Prints the check line (see ../reference.py) first; exits 1 on a parse error. Timings follow
-- the shared rule (see measure and ../run.sh).
local here = arg[0]:match("^(.*)/") or "."
local luajit = rawget(_G, "jit") ~= nil
package.cpath = here .. "/rocks/" .. (luajit and "luajit" or "lua5.5") .. "/?.so;" .. package.cpath
local cjson = require("cjson")
local now = require("benchclock").now

local function measure(min_samples, op)
  local warm = now()
  repeat op() until now() - warm >= 1e9
  local start = now()
  local samples = {}
  while true do
    local t0 = now()
    op()
    samples[#samples + 1] = now() - t0
    local sorted = {}
    for i, s in ipairs(samples) do sorted[i] = s end
    table.sort(sorted)
    local n = #sorted
    local median = n % 2 == 1 and sorted[(n + 1) / 2] or (sorted[n / 2] + sorted[n / 2 + 1]) / 2
    if n >= min_samples then
      local within = 0
      for _, s in ipairs(samples) do
        if s >= median * 0.9 and s <= median * 1.1 then within = within + 1 end
      end
      if within >= 0.6 * n then return median, n, true end
    end
    if n >= 1000 or now() - start >= 10e9 then return median, n, false end
  end
end

-- numsum: wrapping 64-bit sum of double bit patterns (ffi uint64_t under LuaJIT, Lua integers under 5.5)
local add_bits, numsum_hex
if luajit then
  local ffi = require("ffi")
  local u = ffi.new("union { double d; uint64_t u; }")
  local sum = ffi.new("uint64_t", 0)
  local half = ffi.new("uint64_t", 4294967296)
  add_bits = function(x)
    u.d = x + 0.0
    sum = sum + u.u
  end
  numsum_hex = function()
    return string.format("%08x%08x", tonumber(sum / half), tonumber(sum % half))
  end
else
  local sum = 0
  add_bits = function(x)
    sum = sum + string.unpack("<i8", string.pack("<d", x + 0.0))
  end
  numsum_hex = function() return string.format("%016x", sum) end
end

local function chars(s)
  local _, n = s:gsub("[^\128-\191]", "")
  return n
end

-- objects arrays keys strings numbers true false null chars
local c = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local null, array_mt = cjson.null, cjson.array_mt

local function walk(v)
  local t = type(v)
  if t == "table" then
    if getmetatable(v) == array_mt then
      c[2] = c[2] + 1
      for i = 1, #v do walk(v[i]) end
    else
      c[1] = c[1] + 1
      for k, x in pairs(v) do
        c[3] = c[3] + 1
        c[9] = c[9] + chars(k)
        walk(x)
      end
    end
  elseif t == "string" then
    c[4] = c[4] + 1
    c[9] = c[9] + chars(v)
  elseif t == "number" then
    c[5] = c[5] + 1
    add_bits(v)
  elseif v == true then
    c[6] = c[6] + 1
  elseif v == false then
    c[7] = c[7] + 1
  elseif v == null then
    c[8] = c[8] + 1
  end
end

local variant, path, min = arg[1], arg[2], tonumber(arg[3])
if variant ~= "cjson" or not path or not min then
  io.stderr:write("usage: bench.lua cjson <input> <min-samples>\n")
  os.exit(2)
end
local f = assert(io.open(path, "rb"))
local data = f:read("*a")
f:close()
local docs = {}
if path:match("%.ndjson$") then
  for line in data:gmatch("[^\n]+") do
    if line:match("%S") then docs[#docs + 1] = line end
  end
else
  docs[1] = data
end

local checker = cjson.new()
checker.decode_array_with_array_mt(true)
for _, d in ipairs(docs) do
  local ok, v = pcall(checker.decode, d)
  if not ok then
    io.stderr:write("parse error: ", tostring(v), "\n")
    os.exit(1)
  end
  walk(v)
end
print("check: " .. table.concat(c, " ") .. " " .. numsum_hex())
io.stdout:flush()

local decode = cjson.decode
local median, n, converged = measure(min, function()
  for i = 1, #docs do decode(docs[i]) end
end)
local ms = median / 1e6
print(string.format("%.3f ms/op %.1f MB/s (n=%d, %s)", ms, #data / 1048576 / (ms / 1000), n,
  converged and "converged" or "capped"))
