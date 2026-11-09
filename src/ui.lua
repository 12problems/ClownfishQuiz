-- Quiz UI (keyboard-first, mouse works). Phase 1: "pick a move" categories.
-- Reads only shipped scenarios; never touches run state.
local UI = { open = false }
local R = { name = '', setmsg = '', deckhint = '', targets = '', slots = {}, pagetxt = '', banner = '', rev1 = '', rev2 = '', rev3 = '', rev4 = '', line = '', other = '', why = '', conf = '-', skip = '', status = '', reveal = '', focus_label = '', pos = '' }
local PAGE = 8
local S = { name = '', name_focus = false, tcards = {}, page = 0, idx = 1, moves = {}, other = '', why = '', conf = '', skipped = false, skip_reason = '', focus = 'moves', saved = false }
local list, answered, grader
local open_settings -- forward declaration (defined below)

local FIELDS = { 'moves', 'other', 'why', 'conf', 'skip' }
local FIELD_LABEL = { moves = 'Moves (press 1-9 or click)', other = 'Other move (type)', why = 'Why (type)', conf = 'Confidence (press 1-5)', skip = 'Skip reason (type)' }

-- ---------- tarot targets ----------
local function is_tarot(p) return p and p.category == 'tarot_targets' end
local function tarot_max(p)
  if p.tarot_name == 'Death' then return 2 end
  return tonumber(tostring(p.tarot_need or '1'):match('(%d+)$')) or 1
end
local function short_card(raw) return (raw or ''):gsub('%s*%(in hand%)', '') end
local function targets_text(p)
  if not is_tarot(p) then return '' end
  if #S.tcards == 0 then return 'No target cards chosen yet' end
  if p.tarot_name == 'Death' then
    return 'Copy: ' .. short_card(S.tcards[1]) .. (S.tcards[2] and ('   Overwrite: ' .. short_card(S.tcards[2])) or '   (now click the card to overwrite)')
  end
  local t = {}
  for _, c in ipairs(S.tcards) do t[#t + 1] = short_card(c) end
  return 'Target: ' .. table.concat(t, ' ; ')
end

-- ---------- file helpers ----------
local fs = {
  read = function(p) local s = love.filesystem.read(p); return s end,
  write = function(p, s) love.filesystem.createDirectory(CFQ.DIR); return love.filesystem.write(p, s) end,
}
local function grader_name()
  if CFQ.config and CFQ.config.grader_name and CFQ.config.grader_name ~= '' then return CFQ.config.grader_name end
  local n = MPAPI and MPAPI.connection_state and MPAPI.connection_state.display_name
  return (n and n ~= '') and n or 'player'
end
local SETTINGS_PATH = CFQ.DIR .. '/settings.json'
local function load_settings()
  CFQ.config = CFQ.config or {}
  local raw = fs.read(SETTINGS_PATH)
  if raw and raw ~= '' then
    local ok, d = pcall(JSON.decode, raw)
    if ok and type(d) == 'table' then CFQ.config.grader_name = d.grader_name; CFQ.config.import_prompted = d.import_prompted end
  end
end
local function save_settings()
  fs.write(SETTINGS_PATH, JSON.encode({ grader_name = CFQ.config.grader_name or '', import_prompted = CFQ.config.import_prompted and true or false }))
end
local function answers_path() return CFQ.answers.path(CFQ.DIR, grader) end
local function draft_path() return CFQ.DIR .. '/draft_' .. CFQ.answers.safe_name(grader) .. '.json' end

-- ---------- joker sprites ----------
local name_index
local function norm(s) return (tostring(s):lower():gsub('%s*%(mp%)%s*$', ''):gsub('[^%w]', '')) end
local function build_index()
  name_index = {}
  for k, c in pairs(G.P_CENTERS or {}) do
    if c.set == 'Joker' then
      local nm
      local ok = pcall(function() nm = localize { type = 'name_text', set = 'Joker', key = k } end)
      if ok and nm and nm ~= 'ERROR' then
        local n = norm(nm)
        if not name_index[n] or k:find('mp') then name_index[n] = c end -- prefer MP variants on collision
      end
    end
  end
end
local key_index
local function find_center(name)
  if not name_index then build_index() end
  local n = norm(name)
  if name_index[n] then return name_index[n] end
  if not key_index then
    key_index = {}
    for k, c in pairs(G.P_CENTERS or {}) do
      if c.set == 'Joker' then
        local base = k:lower():gsub('^j_', ''):gsub('^mp_', ''):gsub('^mpj_', ''):gsub('[^%w]', '')
        if not key_index[base] or k:find('mp') then key_index[base] = c end
      end
    end
  end
  return key_index[n]
end
local function mini_sprite(name)
  local c = find_center(name)
  if not c or not c.pos then return nil end
  local atlas = G.ASSET_ATLAS[c.atlas or 'Joker'] or G.ASSET_ATLAS['Joker']
  local ok, sp = pcall(function() return Sprite(0, 0, 0.62, 0.83, atlas, c.pos) end)
  if not ok or not sp then return nil end
  sp.states.drag.can = false
  return sp
end

-- ---------- node helpers ----------
local function T(text, scale, colour)
  return { n = G.UIT.T, config = { text = text, scale = scale or 0.3, colour = colour or G.C.UI.TEXT_LIGHT, shadow = true } }
end
local function TREF(tbl, key, scale, colour)
  return { n = G.UIT.T, config = { ref_table = tbl, ref_value = key, scale = scale or 0.3, colour = colour or G.C.UI.TEXT_LIGHT, shadow = true } }
end
local function row(nodes, cfg) cfg = cfg or {}; cfg.align = cfg.align or 'cl'; return { n = G.UIT.R, config = cfg, nodes = nodes } end
local function col(nodes, cfg) cfg = cfg or {}; cfg.align = cfg.align or 'cl'; return { n = G.UIT.C, config = cfg, nodes = nodes } end

local LABEL = { 0.78, 0.8, 0.85, 1 }
local function wrap(s, n)
  local lines, cur = {}, ''
  for w in tostring(s or ''):gmatch('%S+') do
    if #cur + #w + 1 > n and cur ~= '' then lines[#lines + 1] = cur; cur = w else cur = (cur == '' and w) or (cur .. ' ' .. w) end
  end
  if cur ~= '' then lines[#lines + 1] = cur end
  return lines
end

local function trunc(s, n) s = tostring(s or ''); if #s > n then return s:sub(1, n - 1) .. '..' end return s end

local function joker_boxes(p)
  local boxes = {}
  for _, item in ipairs(CFQ.util.split_list(p.jokers)) do
    local name = item:match('^(.-)%s*%[') or item
    local sell = item:match('sells %$(%d+)')
    local kids = {}
    local sp = mini_sprite(name)
    if sp then kids[#kids + 1] = row({ { n = G.UIT.O, config = { object = sp } } }, { align = 'cm' }) end
    kids[#kids + 1] = row({ T(trunc(name, 18), 0.19) }, { align = 'cm', maxw = 1.1 })
    if sell then kids[#kids + 1] = row({ T('$' .. sell, 0.18, G.C.MONEY) }, { align = 'cm' }) end
    boxes[#boxes + 1] = col(kids, { align = 'tm', padding = 0.04, minw = 0.9 })
  end
  if #boxes == 0 then boxes[1] = T('(no jokers)', 0.25) end
  return boxes
end

local function info_rows(p)
  local rows = {}
  local function add(label, val)
    if val and val ~= '' then
      local lines = wrap(val, 70)
      for i, ln in ipairs(lines) do
        rows[#rows + 1] = row({ T(i == 1 and (label .. ' ') or '    ', 0.26, LABEL), T(ln, 0.26) })
      end
    end
  end
  add('Money', '$' .. tostring(p.money))
  add('Lives', tostring(p.lives_me) .. ' vs ' .. tostring(p.lives_opp))
  add('Next', tostring(p.next_blind))
  add('Hands/discards', tostring(p.hands) .. ' / ' .. tostring(p.discards) .. '   hand size ' .. tostring(p.hand_size) .. '   joker slots ' .. tostring(p.joker_slots))
  add('PvP history', p.pvp_history)
  add('Vouchers', p.vouchers)
  add('Consumables', p.consumables)
  add('Hand levels', p.hand_levels)
  add('In shop/pack', p.offers)
  do local short = tostring(p.deck_summary or ''):match('^(.-;.-);') or tostring(p.deck_summary or ''); add('Deck', short) end
  return rows
end

-- ---------- state ----------
local function refresh_text()
  local parts = {}
  for i, m in ipairs(S.moves) do parts[#parts + 1] = i .. '. ' .. m end
  R.line = #parts > 0 and table.concat(parts, '   ') or '(click or press a number)'
  R.other = S.other .. (S.focus == 'other' and '_' or '')
  R.why = S.why .. (S.focus == 'why' and '_' or '')
  R.conf = (S.conf ~= '' and S.conf or '-') .. (S.focus == 'conf' and ' (type 1-5)' or '')
  R.skip = S.skip_reason .. (S.focus == 'skip' and '_' or '')
  do local pp = list and list[S.idx]; R.targets = targets_text(pp) end
  R.focus_label = 'Typing in: ' .. FIELD_LABEL[S.focus] .. '   (Tab = next field)'
  local pos = list and list[S.idx]
  R.pos = pos and ('Question ' .. S.idx .. ' of ' .. #list .. '   (' .. pos.category .. ')   answered ' .. (function() local n = 0 for _ in pairs(answered or {}) do n = n + 1 end return n end)()) or ''
  if S.opts then
    local npages = math.max(1, math.ceil(#S.opts / PAGE))
    R.pagetxt = 'Options ' .. (S.page * PAGE + 1) .. '-' .. math.min(#S.opts, (S.page + 1) * PAGE) .. ' of ' .. #S.opts .. '   (PgUp/PgDn or arrows for more)'
    for k = 1, math.min(PAGE, #S.opts) do
      local i = S.page * PAGE + k
      local o = S.opts[i]
      local sl = R.slots[k]
      if not sl then sl = {}; R.slots[k] = sl end
      if o then
        local at
        for j, m in ipairs(S.moves) do if m == o then at = j end end
        local ls = wrap(o, 50)
        local l2 = ls[2] or ''
        if #ls > 2 then l2 = trunc(l2 .. ' ' .. table.concat(ls, ' ', 3), 50) end
        sl.l1, sl.l2, sl.mark, sl.key = ls[1] or '', l2, at and ('<< ' .. at) or '', k .. ')'
      else
        sl.l1, sl.l2, sl.mark, sl.key = '', '', '', ''
      end
    end
  end
end

local function write_draft()
  local p = list and list[S.idx]
  if not p then return end
  local d = { position_id = p.position_id, moves = S.moves, other = S.other, why = S.why, conf = S.conf, skipped = S.skipped, skip_reason = S.skip_reason, tcards = S.tcards }
  fs.write(draft_path(), JSON.encode(d))
end
function write_draft_clear() fs.write(draft_path(), '') end
local function load_draft(p)
  S.moves, S.other, S.why, S.conf, S.skipped, S.skip_reason, S.saved, S.tcards = {}, '', '', '', false, '', false, {}
  local raw = fs.read(draft_path())
  if raw and raw ~= '' then
    local ok, d = pcall(JSON.decode, raw)
    if ok and d and d.position_id == p.position_id then
      S.moves, S.other, S.why, S.conf = d.moves or {}, d.other or '', d.why or '', d.conf or ''
      S.skipped, S.skip_reason = d.skipped and true or false, d.skip_reason or ''
      S.tcards = d.tcards or {}
    end
  end
end

local function first_unanswered(from)
  for k = 0, #list - 1 do
    local i = (from - 1 + k) % #list + 1
    if not answered[list[i].position_id] then return i end
  end
  return from
end

local function build_screen()
  local p = list[S.idx]
  S.opts = {}
  S.page = 0
  R.slots = {}
  do
    local all = CFQ.util.split_list(p.options)
    local function base(o) return (o:gsub('%s*%(.*$', '')) end
    for i, o in ipairs(all) do
      local dup = false
      if i == #all and i > 1 then for j = 1, i - 1 do if base(all[j]) == base(o) then dup = true end end end
      if not dup then S.opts[#S.opts + 1] = o end
    end
  end
  R.opts = {}
  refresh_text()
  local left = {
    row({ TREF(R, 'banner', 0.4, G.C.GOLD) }, { align = 'cm', minh = 0.5 }),
    row({ TREF(R, 'pos', 0.28, LABEL) }),
    row({ T(p.stake .. ((p.deck and p.deck ~= '?') and (' - ' .. p.deck) or '') .. ' - ante ' .. tostring(p.ante), 0.3) }),
    row(joker_boxes(p), { align = 'tl', padding = 0.05 }),
  }
  for _, r in ipairs(info_rows(p)) do left[#left + 1] = r end
  left[#left + 1] = row({
    { n = G.UIT.C, config = { align = 'cm', padding = 0.08, r = 0.1, hover = true, colour = G.C.PURPLE, button = 'cfq_deck', shadow = true, minw = 2.8 }, nodes = { T('View deck (D)', 0.26) } },
    { n = G.UIT.C, config = { align = 'cm', padding = 0.08, r = 0.1, hover = true, colour = G.C.GREY, button = 'cfq_settings', shadow = true, minw = 2.2 }, nodes = { T('Settings (S)', 0.26) } } }, { align = 'cm', padding = 0.05 })
  left[#left + 1] = row({ T('Drag a saved answers_<name>.csv onto the game window to import old answers.', 0.2, LABEL) }, { padding = 0.05 })

  local head
  if p.category == 'tarot_targets' then
    head = { row({ T('You hold ' .. tostring(p.tarot_name) .. '. Would you use it for value or for scoring?', 0.3, G.C.GOLD) }),
             row({ T('Look at the deck (press D). Then fill in "Why" below: say which cards you would target.', 0.26, G.C.WHITE) }) }
  else
    head = { row({ T('What would you do? Order matters.', 0.3) }) }
  end
  local right = { head[1], head[2] or row({}), row({ TREF(R, 'line', 0.26, G.C.GOLD) }, { padding = 0.04 }) }
  if is_tarot(p) then right[#right + 1] = row({ TREF(R, 'targets', 0.26, G.C.WHITE) }, { padding = 0.04 }) end
  for k = 1, math.min(PAGE, #S.opts) do
    R.slots[k] = R.slots[k] or {}
    local sl = R.slots[k]
    right[#right + 1] = row({
      col({ TREF(sl, 'key', 0.26, LABEL) }, { align = 'tl', minw = 0.55 }),
      col({ row({ TREF(sl, 'l1', 0.26) }, { minh = 0.3 }), row({ TREF(sl, 'l2', 0.26) }, { minh = 0.3 }) }, { align = 'tl', minw = 5.4 }),
      col({ TREF(sl, 'mark', 0.26, G.C.GOLD) }, { align = 'tr', minw = 0.7 }),
    }, { padding = 0.03, r = 0.05, hover = true, colour = G.C.BLUE, button = 'cfq_opt', ref_table = { k = k }, minw = 6.8, shadow = true })
  end
  if #S.opts > PAGE then right[#right + 1] = row({
    { n = G.UIT.C, config = { align = 'cm', padding = 0.05, r = 0.1, hover = true, colour = G.C.GREY, button = 'cfq_prev', minw = 1.2 }, nodes = { T('< Prev', 0.24) } },
    { n = G.UIT.C, config = { align = 'cm', padding = 0.05, r = 0.1, hover = true, colour = G.C.GREY, button = 'cfq_next_page', minw = 1.2 }, nodes = { T('More >', 0.24) } },
    col({ TREF(R, 'pagetxt', 0.2, LABEL) }, { align = 'cl', padding = 0.05 }),
  }, { padding = 0.02 }) end
  local function field(name, key)
    return row({ T(FIELD_LABEL[name] .. ': ', 0.22, LABEL), TREF(R, key, 0.26) },
      { padding = 0.04, r = 0.05, hover = true, colour = G.C.BLACK, button = 'cfq_focus', ref_table = { f = name }, minw = 6.8 })
  end
  right[#right + 1] = field('other', 'other')
  right[#right + 1] = field('why', 'why')
  right[#right + 1] = field('conf', 'conf')
  right[#right + 1] = field('skip', 'skip')
  right[#right + 1] = row({ TREF(R, 'focus_label', 0.2, LABEL) })
  right[#right + 1] = row({
    { n = G.UIT.C, config = { align = 'cm', padding = 0.08, r = 0.1, hover = true, colour = G.C.GREEN, button = 'cfq_save', shadow = true, minw = 2.8 }, nodes = { T('Save + next (Ctrl+Enter)', 0.26) } },
    { n = G.UIT.C, config = { align = 'cm', padding = 0.08, r = 0.1, hover = true, colour = G.C.GREY, button = 'cfq_skip', shadow = true, minw = 2.2 }, nodes = { T('Skip (needs reason)', 0.26) } },
  }, { align = 'cm', padding = 0.05 })
  right[#right + 1] = row({ TREF(R, 'status', 0.28, G.C.GOLD) })
  for _, k in ipairs({ 'rev1', 'rev2', 'rev3', 'rev4' }) do right[#right + 1] = row({ TREF(R, k, 0.24, G.C.UI.TEXT_LIGHT) }) end
  right[#right + 1] = row({ TREF(R, 'reveal', 0.22, LABEL) })

  return create_UIBox_generic_options({
    back_func = 'cfq_close', back_label = 'Close (Esc)', minw = 15, padding = 0.05,
    contents = { col(left, { align = 'tl', padding = 0.08, minw = 7.5 }), col(right, { align = 'tl', padding = 0.08, minw = 7.5 }) },
  })
end

local function show_position(keep)
  local p = list[S.idx]
  if not keep then load_draft(p) end
  S.focus = 'moves'
  R.status, R.reveal, R.banner, R.rev1, R.rev2, R.rev3, R.rev4 = '', '', '', '', '', '', ''
  G.FUNCS.overlay_menu { definition = build_screen() }
end

function UI.open_quiz()
  if UI.open then return end
  local ok, err = pcall(function()
    load_settings()
    grader = grader_name()
    local all = CFQ.data.load()
    list = CFQ.data.playable(all)
    table.sort(list, function(a, b) return a.position_id < b.position_id end)
    answered = CFQ.answers.answered_set(CFQ.answers.load(fs, answers_path()), grader)
    S.idx = first_unanswered(1)
    UI.open = true
    UI.first_run = not CFQ.config.import_prompted
    UI.prev_repeat = love.keyboard.hasKeyRepeat()
    love.keyboard.setKeyRepeat(true)
    show_position()
    if UI.first_run then open_settings(true) end
  end)
  if not ok then UI.open = false; sendWarnMessage('ClownfishQuiz open: ' .. tostring(err), 'ClownfishQuiz') end
end

function UI.close()
  if UI.open then write_draft() end
  UI.open = false
  UI.view = nil
  if UI.prev_repeat ~= nil then love.keyboard.setKeyRepeat(UI.prev_repeat); UI.prev_repeat = nil end
  if G.OVERLAY_MENU then G.FUNCS.exit_overlay_menu() end
end

function UI.on_match_found()
  if not UI.open then return end
  write_draft()
  R.status = 'Match found - progress saved'
  R.banner = 'MATCH FOUND - progress saved'
  refresh_text()
  G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 2.0, blockable = false, func = function() UI.close(); return true end }))
end

-- ---------- actions ----------
local function toggle_move(i)
  local o = S.opts and S.opts[i]
  if not o then return end
  for j, m in ipairs(S.moves) do
    if m == o then table.remove(S.moves, j); refresh_text(); write_draft(); return end
  end
  local pp = list[S.idx]
  if pp and pp.category == 'tarot_targets' then S.moves = {} end -- one intent only
  S.moves[#S.moves + 1] = o
  refresh_text(); write_draft()
end

local function save_and_next()
  local p = list[S.idx]
  if not S.saved then
    local best = table.concat(S.moves, ' > ')
    if S.other ~= '' then best = (best ~= '' and best .. ' > ' or '') .. 'Other: ' .. S.other end
    if best == '' and not S.skipped then R.status = 'Pick at least one move (or Skip with a reason)'; return end
    local notnow = is_tarot(p) and best:find("Don't use it now", 1, true) ~= nil
    if is_tarot(p) and not S.skipped and not notnow then
      local need = (p.tarot_name == 'Death') and 2 or 1
      if #S.tcards < need then R.status = 'Press D and click the target card' .. (need > 1 and 's (copy, then overwrite)' or '') .. ' in the deck first'; return end
    end
    if S.skipped and S.skip_reason == '' then R.status = 'Skipping needs a reason'; S.focus = 'skip'; refresh_text(); return end
    local row_ = { position_id = p.position_id, grader = grader, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
      best_move = S.skipped and '' or best, confidence = S.conf, why = S.why, skipped = S.skipped and '1' or '0',
      skip_reason = S.skip_reason, revealed_after = '1' }
    if is_tarot(p) and not S.skipped then
      if notnow then row_.tarot_not_now = '1'
      else
        row_.tarot_not_now = '0'
        if p.tarot_name == 'Death' then row_.tarot_choice, row_.tarot_choice2 = S.tcards[1] or '', S.tcards[2] or ''
        else row_.tarot_choice = table.concat(S.tcards, ' | ') end
      end
    end
    CFQ.answers.upsert(fs, answers_path(), row_)
    answered[p.position_id] = true
    S.saved = true
    local ls = wrap('The original player did: ' .. tostring(p.human_action), 60)
    R.rev1, R.rev2, R.rev3, R.rev4 = ls[1] or '', ls[2] or '', ls[3] or '', (ls[4] or '') .. (#ls > 4 and ' ..' or '')
    R.reveal = 'Ctrl+Enter for next question'
    write_draft_clear()
    R.status = 'Saved'
    refresh_text()
    return
  end
  S.idx = first_unanswered(S.idx + 1)
  show_position()
end

local function picked_raw(raw)
  for _, c in ipairs(S.tcards) do if c == raw then return true end end
  return false
end
local function deck_opts(p)
  if not is_tarot(p) then return nil end
  local mx = tarot_max(p)
  local function hint()
    if p.tarot_name == 'Death' then R.deckhint = 'Death: click the card to COPY, then the card to OVERWRITE (click a chosen card to remove it)'
    else R.deckhint = 'Click up to ' .. mx .. ' target card(s) for ' .. tostring(p.tarot_name) .. ' (click a chosen card again to remove it)' end
  end
  hint()
  R.targets = targets_text(p)
  return {
    ref = R,
    is_selected = function(e) return picked_raw(e.raw) end,
    on_pick = function(e, card)
      if picked_raw(e.raw) then
        for i, c in ipairs(S.tcards) do if c == e.raw then table.remove(S.tcards, i); break end end
        hint()
      elseif #S.tcards >= mx then
        R.deckhint = 'Already ' .. mx .. ' card(s) chosen - click a chosen card to remove it first'
      else
        S.tcards[#S.tcards + 1] = e.raw
        hint()
      end
      R.targets = targets_text(p)
      write_draft()
      CFQ.deckview.refresh_selection(function(en) return picked_raw(en.raw) end)
    end,
  }
end

local DV = nil
local function open_deck()
  if not UI.open or UI.view == 'deck' then return end
  write_draft()
  UI.view = 'deck'
  local p = list[S.idx]
  local ok, def = pcall(function() return CFQ.deckview.definition(p.deck_cards, 'cfq_deck_back', (p.deck and p.deck ~= '?') and p.deck or 'Deck', deck_opts(p)) end)
  if ok then
    G.FUNCS.overlay_menu { definition = def }
    if is_tarot(p) and #S.tcards > 0 then CFQ.deckview.refresh_selection(function(en) return picked_raw(en.raw) end) end
  else UI.view = nil; R.status = 'Deck viewer failed'; sendWarnMessage('ClownfishQuiz deck: ' .. tostring(def), 'ClownfishQuiz') end
end
local function close_deck()
  if UI.view ~= 'deck' then return end
  UI.view = nil
  show_position(true)
end
G.FUNCS.cfq_deck = function() open_deck() end
G.FUNCS.cfq_deck_back = function() close_deck() end
G.FUNCS.cfq_open = function() if UI.allowed_now() then UI.open_quiz() end end
G.FUNCS.cfq_close = function() UI.close() end
local function turn_page(d)
  if not S.opts then return end
  local npages = math.max(1, math.ceil(#S.opts / PAGE))
  S.page = (S.page + d) % npages
  refresh_text()
end
G.FUNCS.cfq_opt = function(e) toggle_move(S.page * PAGE + e.config.ref_table.k) end
G.FUNCS.cfq_prev = function() turn_page(-1) end
G.FUNCS.cfq_next_page = function() turn_page(1) end
G.FUNCS.cfq_focus = function(e) S.focus = e.config.ref_table.f; refresh_text() end
G.FUNCS.cfq_save = function() save_and_next() end
G.FUNCS.cfq_skip = function() S.skipped = true; S.focus = 'skip'; refresh_text() end


-- ---------- settings view ----------
local function name_text() return S.name .. (UI.view == 'settings' and S.name_focus and '_' or '') end
local function build_settings(first_run)
  R.name, R.setmsg = name_text(), R.setmsg or ''
  local path_line = 'Answers file: ' .. 'Balatro/' .. CFQ.DIR .. '/answers_' .. CFQ.answers.safe_name(grader_name()) .. '.csv'
  local lines = {}
  local function para(txt, scale, colour)
    for _, ln in ipairs(wrap(txt, 78)) do lines[#lines + 1] = row({ T(ln, scale or 0.26, colour or G.C.WHITE) }) end
  end
  if first_run then
    para('Welcome! If you already answered questions with the earlier grader tool, you can import that file now.', 0.3, G.C.GOLD)
  else
    para('Settings', 0.34, G.C.GOLD)
  end
  lines[#lines + 1] = row({ T('Name for your answers file: ', 0.26, LABEL), TREF(R, 'name', 0.3, G.C.WHITE) },
    { padding = 0.06, r = 0.05, hover = true, colour = G.C.BLACK, button = 'cfq_name_focus', minw = 7 })
  para('Type to change it. By default it is your account name. Use the same name as before so your old answers are recognised.', 0.22, LABEL)
  para(path_line, 0.22, LABEL)
  lines[#lines + 1] = row({
    { n = G.UIT.C, config = { align = 'cm', padding = 0.08, r = 0.1, hover = true, colour = G.C.BLUE, button = 'cfq_open_folder', shadow = true, minw = 3 }, nodes = { T('Open answers folder', 0.26) } },
    { n = G.UIT.C, config = { align = 'cm', padding = 0.08, r = 0.1, hover = true, colour = G.C.GREEN, button = 'cfq_import_folder', shadow = true, minw = 3 }, nodes = { T('Import answers now', 0.26) } },
  }, { align = 'cm', padding = 0.06 })
  para('To import old answers: 1) press "Open answers folder". 2) Inside it create a folder named import (if it does not exist). 3) Copy your old answers_<name>.csv file into that import folder. 4) Come back and press "Import answers now". Answers you already have in this mod are never overwritten.', 0.22, G.C.WHITE)
  para('Shortcut: you can also drag the old answers_<name>.csv file onto the game window while this menu is open.', 0.22, LABEL)
  lines[#lines + 1] = row({ TREF(R, 'setmsg', 0.28, G.C.GOLD) })
  return create_UIBox_generic_options({ back_func = 'cfq_settings_back', back_label = first_run and 'Continue (Esc)' or 'Back (Esc)', minw = 10,
    contents = { col(lines, { align = 'tl', padding = 0.05 }) } })
end

open_settings = function(first_run)
  if not UI.open then return end
  write_draft()
  UI.view = 'settings'
  S.name = CFQ.config.grader_name or ''
  S.name_focus = true
  R.setmsg = ''
  G.FUNCS.overlay_menu { definition = build_settings(first_run) }
end
local function close_settings()
  if UI.view ~= 'settings' then return end
  local n = S.name:gsub('^%s+', ''):gsub('%s+$', '')
  CFQ.config.grader_name = (n ~= '') and n or nil
  CFQ.config.import_prompted = true
  save_settings()
  UI.view = nil
  grader = grader_name()
  answered = CFQ.answers.answered_set(CFQ.answers.load(fs, answers_path()), grader)
  S.idx = first_unanswered(S.idx)
  show_position()
end
local function import_folder()
  local dir = CFQ.DIR .. '/import'
  love.filesystem.createDirectory(dir)
  local added, skipped, files = 0, 0, 0
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
    if name:lower():match('^answers.*%.csv$') then
      local text = love.filesystem.read(dir .. '/' .. name)
      if text then
        local a, s_ = CFQ.answers.import_text(fs, answers_path(), text)
        added, skipped, files = added + a, skipped + s_, files + 1
      end
    end
  end
  if files == 0 then R.setmsg = 'No answers*.csv found in the import folder yet. Press "Open answers folder", create/open "import", copy your file in, then try again.'
  else R.setmsg = 'Imported ' .. added .. ' answers from ' .. files .. ' file(s) (' .. skipped .. ' already present).' end
  answered = CFQ.answers.answered_set(CFQ.answers.load(fs, answers_path()), grader)
end
G.FUNCS.cfq_settings = function() open_settings(false) end
G.FUNCS.cfq_settings_back = function() close_settings() end
G.FUNCS.cfq_name_focus = function() S.name_focus = true; R.name = name_text() end
G.FUNCS.cfq_open_folder = function()
  love.filesystem.createDirectory(CFQ.DIR .. '/import')
  love.system.openURL('file://' .. love.filesystem.getSaveDirectory() .. '/' .. CFQ.DIR)
end
G.FUNCS.cfq_import_folder = function() import_folder() end

-- ---------- in-run (PvP ready) gating ----------
local function in_pvp_downtime()
  return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT
    and PVP and PVP.GAME and PVP.GAME.ready_blind and true or false
end
function UI.allowed_now()
  if G.STAGE ~= G.STAGES.RUN then return true end -- menus / queue screens
  return in_pvp_downtime()
end
function UI.tick_run()
  local downtime = in_pvp_downtime()
  local in_run = G.STAGE == G.STAGES.RUN
  if downtime and not UI.open and not UI.icon then
    UI.icon = UIBox {
      definition = { n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR }, nodes = {
        UIBox_button { id = 'cfq_icon', button = 'cfq_open', colour = G.C.ORANGE, minw = 1.7, minh = 0.5, label = { 'Quiz (F8)' }, scale = 0.28 } } },
      config = { align = 'tr', offset = { x = -0.2, y = 0.3 }, major = G.ROOM_ATTACH, bond = 'Weak' },
    }
  elseif (not downtime or UI.open) and UI.icon then
    UI.icon:remove(); UI.icon = nil
  end
  if UI.open and in_run and not downtime and not UI.leaving then
    UI.leaving = true
    write_draft()
    R.banner = 'GAME STARTING - progress saved'
    R.status = R.banner
    refresh_text()
    G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 2.0, blockable = false, func = function() UI.leaving = false; UI.close(); return true end }))
  end
end

-- ---------- keyboard ----------
local function next_field(dir)
  local at = 1
  for i, f in ipairs(FIELDS) do if f == S.focus then at = i end end
  S.focus = FIELDS[(at - 1 + dir) % #FIELDS + 1]
  refresh_text()
end
local function field_key(name) return ({ other = 'other', why = 'why', skip = 'skip_reason' })[name] end

function UI.handle_key(key, scancode, isrepeat)
  if key == 'f8' then
    if isrepeat then return true end
    if UI.open then UI.close() elseif UI.allowed_now() then UI.open_quiz() end
    return true
  end
  if not UI.open then return false end
  local ctrl = love.keyboard.isDown('lctrl', 'rctrl')
  if UI.view == 'deck' then
    if not isrepeat and (key == 'escape' or key == 'd') then close_deck() end
    return true
  end
  if UI.view == 'settings' then
    if key == 'backspace' then S.name = S.name:sub(1, math.max(0, #S.name - 1)); R.name = name_text()
    elseif not isrepeat and (key == 'escape' or key == 'return' or key == 'kpenter') then close_settings() end
    return true
  end
  if isrepeat and key ~= 'backspace' and key ~= 'pagedown' and key ~= 'pageup' then return true end
  if key == 'escape' then UI.close(); return true end
  if key == 'd' and (S.focus == 'moves' or S.focus == 'conf') then open_deck(); return true end
  if key == 's' and (S.focus == 'moves' or S.focus == 'conf') then open_settings(false); return true end
  if key == 'tab' then next_field(love.keyboard.isDown('lshift', 'rshift') and -1 or 1); return true end
  if (key == 'return' or key == 'kpenter') and ctrl then save_and_next(); return true end
  local f = S.focus
  if f == 'moves' then
    local d = tonumber(key:match('^kp(%d)$') or key:match('^(%d)$') or '')
    if key == 'pagedown' or key == 'down' then turn_page(1) elseif key == 'pageup' or key == 'up' then turn_page(-1) elseif d and d >= 1 and d <= PAGE then toggle_move(S.page * PAGE + d) elseif key == 'backspace' then table.remove(S.moves); refresh_text(); write_draft() end
  elseif f == 'conf' then
    local d = tonumber(key:match('^kp(%d)$') or key:match('^(%d)$') or '')
    if d and d >= 1 and d <= 5 then S.conf = tostring(d); refresh_text(); write_draft() end
  else
    local k = field_key(f)
    if key == 'backspace' then
      local s = (f == 'other' and S.other) or (f == 'why' and S.why) or S.skip_reason
      s = s:sub(1, math.max(0, #s - 1)); if f == 'other' then S.other = s elseif f == 'why' then S.why = s else S.skip_reason = s; S.skipped = s ~= '' end
      refresh_text(); write_draft()
    end
  end
  return true -- swallow all keys while open so the game's shortcuts don't fire
end

function UI.handle_text(t)
  if not UI.open then return false end
  if UI.view == 'settings' then if #S.name < 24 then S.name = S.name .. t; R.name = name_text() end return true end
  if UI.view == 'deck' then return true end
  local f = S.focus
  if f == 'other' then S.other = S.other .. t
  elseif f == 'why' then S.why = S.why .. t
  elseif f == 'skip' then S.skip_reason = S.skip_reason .. t; S.skipped = true
  else return true end
  refresh_text(); write_draft()
  return true
end

function UI.handle_drop(file)
  local name = file:getFilename() or ''
  if not name:lower():match('answers.*%.csv$') then return false end
  file:open('r'); local text = file:read(); file:close()
  grader = grader_name()
  local added, skipped = CFQ.answers.import_text(fs, answers_path(), text)
  if answered then answered = CFQ.answers.answered_set(CFQ.answers.load(fs, answers_path()), grader) end
  R.status = 'Imported ' .. added .. ' answers (' .. skipped .. ' already present)'
  R.setmsg = R.status
  return true
end

function UI.install_input()
  local kp, ti, fd = love.keypressed, love.textinput, love.filedropped
  love.keypressed = function(key, sc, isrepeat) if UI.handle_key(key, sc, isrepeat) then return end return kp(key, sc, isrepeat) end
  love.textinput = function(t) if UI.handle_text(t) then return end if ti then return ti(t) end end
  love.filedropped = function(file) if UI.handle_drop(file) then return end if fd then return fd(file) end end
end

-- ---------- main-menu button ----------
function UI.install_menu_button()
  local orig = create_UIBox_main_menu_buttons
  create_UIBox_main_menu_buttons = function(...)
    local t = orig(...)
    local ok = pcall(function()
      local right = t.nodes[2]
      local keep = {}
      for i = 1, 3 do if right.nodes[i] then keep[#keep + 1] = right.nodes[i] end end
      table.insert(keep, 1, { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
        UIBox_button { id = 'cfq_menu_button', button = 'cfq_open', colour = G.C.ORANGE, minw = 3, minh = 0.7, label = { 'Clownfish Quiz' }, scale = 0.35 } } })
      right.nodes = keep
    end)
    return t
  end
end

return UI
