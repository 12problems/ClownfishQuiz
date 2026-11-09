-- Queue/match detection. Read-only: only asks MPAPI whether the player is queued/committed
-- and whether the PvP ready flag is set. Polls (cheap) instead of wrapping MPAPI internals so a
-- MPAPI refactor cannot break us; falls back to "never queued" if MPAPI is missing.
local H = { was_queued = false, was_committed = false }

local function mm() return MPAPI and MPAPI.matchmaking end

function H.is_queued() local m = mm(); return m and m.is_queued and m.is_queued() or false end
function H.is_committed() local m = mm(); return m and m.is_committed and m.is_committed() or false end

-- "match found" = was searching, no longer searching, but still committed (joining the lobby).
local function tick()
  local queued, committed = H.is_queued(), H.is_committed()
  if H.was_queued and not queued and committed then
    if CFQ.ui and CFQ.ui.on_match_found then CFQ.ui.on_match_found() end
  end
  H.was_queued, H.was_committed = queued, committed
  if CFQ.ui and CFQ.ui.tick_run then CFQ.ui.tick_run() end
end

-- Driven from love.update (not G.E_MANAGER events): starting a run clears the event queue,
-- which would silently end an event-based poll chain.
function H.install()
  local acc = 0
  local orig = love.update
  love.update = function(dt, ...)
    acc = acc + (dt or 0)
    if acc >= 0.25 then
      acc = 0
      local ok, err = pcall(tick)
      if not ok then sendWarnMessage('ClownfishQuiz tick: ' .. tostring(err), 'ClownfishQuiz') end
    end
    return orig(dt, ...)
  end
end

return H
