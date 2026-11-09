-- Answer file: same columns as the Python grader (answers_<name>.csv), plaintext.
-- fs = { read(path)->string|nil, write(path,string)->bool }  (injected so it is testable)
local U = assert(CFQ_UTIL)
local A = {}

A.COLUMNS = {
  'position_id', 'grader', 'timestamp', 'best_move', 'also_fine', 'clearly_wrong', 'confidence',
  'plan', 'why', 'skipped', 'skip_reason', 'revealed_after',
  'tarot_choice', 'tarot_choice2', 'tarot_not_now', 'tarot_also',
  'play_cards', 'discard_cards', 'joker_order',
}
A.PLANS = { '', 'High Card', 'Retriggers', 'Flexible scoring', 'Economy', 'Pivoting', 'Unclear' }

function A.safe_name(name)
  name = tostring(name or ''):gsub('[^%w_%-]', '_')
  if name == '' then name = 'player' end
  return name
end

function A.path(dir, name) return dir .. '/answers_' .. A.safe_name(name) .. '.csv' end

function A.load(fs, path)
  local s = fs.read(path)
  if not s or s == '' then return {} end
  return U.csv_dicts(s)
end

local function normalize(r)
  local o = {}
  for _, c in ipairs(A.COLUMNS) do o[c] = r[c] or '' end
  return o
end

-- Replace the row with the same (position_id, grader) else append. Returns ok.
function A.upsert(fs, path, row)
  local rows, done, out = A.load(fs, path), false, {}
  for _, r in ipairs(rows) do
    if r.position_id == row.position_id and r.grader == row.grader then
      if not done then out[#out + 1] = normalize(row); done = true end
    else out[#out + 1] = normalize(r) end
  end
  if not done then out[#out + 1] = normalize(row) end
  return fs.write(path, U.csv_write(A.COLUMNS, out))
end

-- Import another answers file's contents (string). Existing rows (same id+grader) win.
-- Returns added, skipped.
function A.import_text(fs, path, text, as_grader)
  local have, rows = {}, A.load(fs, path)
  for _, r in ipairs(rows) do have[r.grader .. '\0' .. r.position_id] = true end
  local added, skipped = 0, 0
  for _, r in ipairs(U.csv_dicts(text)) do
    if as_grader and as_grader ~= '' then r.grader = as_grader end -- imported answers become the current name's
    local k = (r.grader or '') .. '\0' .. (r.position_id or '')
    if (r.position_id or '') == '' then skipped = skipped + 1
    elseif have[k] then skipped = skipped + 1
    else have[k] = true; rows[#rows + 1] = normalize(r); added = added + 1 end
  end
  if added > 0 then
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = normalize(r) end
    fs.write(path, U.csv_write(A.COLUMNS, out))
  end
  return added, skipped
end

function A.answered_set(rows, grader)
  local s = {}
  for _, r in ipairs(rows) do if r.grader == grader then s[r.position_id] = true end end
  return s
end

return A
