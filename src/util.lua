-- Pure helpers (no game dependencies) so they can be unit tested outside Balatro.
local U = {}

local bxor = (bit and bit.bxor) or (bit32 and bit32.bxor)
assert(bxor, 'no bit library')

-- Repeating-key XOR. Obfuscation only (see README), symmetric.
function U.xor(data, key)
  local out, n, kl = {}, #data, #key
  local kb = { key:byte(1, kl) }
  local CH = 4096
  for s = 1, n, CH do
    local e = math.min(s + CH - 1, n)
    local t = {}
    for i = s, e do
      t[#t + 1] = string.char(bxor(data:byte(i), kb[(i - 1) % kl + 1]))
    end
    out[#out + 1] = table.concat(t)
  end
  return table.concat(out)
end

-- RFC 4180 parse. Returns list of rows (list of strings).
function U.csv_parse(s)
  if s:sub(1, 3) == '\239\187\191' then s = s:sub(4) end
  local rows, row, field, i, n = {}, {}, {}, 1, #s
  local inq = false
  local function endfield() row[#row + 1] = table.concat(field); field = {} end
  local function endrow() endfield(); rows[#rows + 1] = row; row = {} end
  while i <= n do
    local c = s:sub(i, i)
    if inq then
      if c == '"' then
        if s:sub(i + 1, i + 1) == '"' then field[#field + 1] = '"'; i = i + 1 else inq = false end
      else field[#field + 1] = c end
    else
      if c == '"' then inq = true
      elseif c == ',' then endfield()
      elseif c == '\r' then -- skip
      elseif c == '\n' then endrow()
      else field[#field + 1] = c end
    end
    i = i + 1
  end
  if #field > 0 or #row > 0 then endrow() end
  return rows
end

local function q(v)
  v = tostring(v or '')
  if v:find('[",\r\n]') then return '"' .. v:gsub('"', '""') .. '"' end
  return v
end

-- cols: ordered column names; records: list of tables keyed by column.
function U.csv_write(cols, records)
  local lines = { table.concat((function() local t = {} for _, c in ipairs(cols) do t[#t + 1] = q(c) end return t end)(), ',') }
  for _, r in ipairs(records) do
    local t = {}
    for _, c in ipairs(cols) do t[#t + 1] = q(r[c]) end
    lines[#lines + 1] = table.concat(t, ',')
  end
  return table.concat(lines, '\r\n') .. '\r\n'
end

-- Rows -> list of dict using the first row as header.
function U.csv_dicts(s)
  local rows = U.csv_parse(s)
  local hdr = table.remove(rows, 1)
  local out = {}
  if not hdr then return out end
  for _, r in ipairs(rows) do
    if not (#r == 1 and r[1] == '') then
      local d = {}
      for i, h in ipairs(hdr) do d[h] = r[i] or '' end
      out[#out + 1] = d
    end
  end
  return out
end

function U.split_list(s) -- " | " separated
  local out = {}
  if not s or s == '' then return out end
  for part in (s .. ' | '):gmatch('(.-) | ') do out[#out + 1] = part end
  return out
end

return U
