-- UI layer. FIRST PASS / PLACEHOLDER: opens an overlay, saves draft on match found.
-- The real scenario screen (joker sprites, deck viewer clone, move line) is built with Rob
-- iteratively; this file is the integration surface (open / close / on_match_found).
local UI = { open = false }

function UI.on_match_found()
  if not UI.open then return end
  -- TODO: save draft of the in-progress answer, show "Match found - progress saved" for ~1s,
  -- then G.FUNCS.exit_overlay_menu().
  UI.open = false
  G.FUNCS.exit_overlay_menu()
end

function UI.open_quiz()
  UI.open = true
  -- TODO: G.FUNCS.overlay_menu{ definition = create_UIBox_cfq_quiz() }
end

return UI
