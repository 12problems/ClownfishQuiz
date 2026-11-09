-- Loads the shipped scenarios (XOR-obfuscated JSON) lazily on first open.
local D = { positions = nil }

function D.load()
  if D.positions then return D.positions end
  local path = CFQ.path .. 'data/positions.dat'
  local raw = NFS.read(path)
  assert(raw and #raw > 0, 'ClownfishQuiz: positions.dat missing')
  local ok, parsed = pcall(function() return JSON.decode(CFQ.util.xor(raw, CFQ.KEY)) end)
  assert(ok and parsed and parsed.positions, 'ClownfishQuiz: positions.dat unreadable')
  D.positions = parsed.positions
  return D.positions
end

-- Shop-phase decisions only (tarot_targets, hand_play, joker_order were dropped by Rob, 2026-11-09).
D.PHASE1 = { buy_or_save = true, sell_to_replace = true, reroll_or_leave = true, pack_pick = true, tarot_use = true }

function D.playable(positions)
  local out = {}
  for _, p in ipairs(positions) do if D.PHASE1[p.category] then out[#out + 1] = p end end
  return out
end

return D
