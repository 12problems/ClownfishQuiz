-- Quiz UI (keyboard-first, mouse works). Phase 1: "pick a move" categories.
-- Reads only shipped scenarios; never touches run state.
local UI = { open = false }
local R = { slots = {}, pagetxt = '', banner = '', rev1 = '', rev2 = '', rev3 = '', rev4 = '', line = '', other = '', why = '', conf = '-', skip = '', status = '', reveal = '', focus_label = '', pos = '' }
local PAGE = 8
local S = { page = 0, idx = 1, moves = {}, other = '', why = '', conf = '', skipped = false, skip_reason = '', focus = 'moves', saved = false }
local list, answered, grader

local FIELDS = { 'moves', 'other', 'why', 'conf', 'skip' }
local FIELD_LABEL = { moves = 'Moves (press 1-9 or click)', other = 'Other move (type)', why = 'Why (type)', conf = 'Confidence (press 1-5)', skip = 'Skip reason (type)' }

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
  local d = { position_id = p.position_id, moves = S.moves, other = S.other, why = S.why, conf = S.conf, skipped = S.skipped, skip_reason = S.skip_reason }
  fs.write(draft_path(), JSON.encode(d))
end
function write_draft_clear() fs.write(draft_path(), '') end
local function load_draft(p)
  S.moves, S.other, S.why, S.conf, S.skipped, S.skip_reason, S.saved = {}, '', '', '', false, '', false
  local raw = fs.read(draft_path())
  if raw and raw ~= '' then
    local ok, d = pcall(JSON.decode, raw)
    if ok and d and d.position_id == p.position_id then
      S.moves, S.other, S.why, S.conf = d.moves or {}, d.other or '', d.why or '', d.conf or ''
      S.skipped, S.skip_reason = d.skipped and true or false, d.skip_reason or ''
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
    { n = G.UIT.C, config = { align = 'cm', padding = 0.08, r = 0.1, hover = true, colour = G.C.PURPLE, button = 'cfq_deck', shadow = true, minw = 2.8 }, nodes = { T('View deck (D)', 0.26) } } }, { align = 'cm', padding = 0.05 })
  left[#left + 1] = row({ T('Drag a saved answers_<name>.csv onto the game window to import old answers.', 0.2, LABEL) }, { padding = 0.05 })

  local head
  if p.category == 'tarot_targets' then
    head = { row({ T('You hold ' .. tostring(p.tarot_name) .. '. Would you use it for value or for scoring?', 0.3, G.C.GOLD) }),
             row({ T('Look at the deck (press D). Then fill in "Why" below: say which cards you would target.', 0.26, G.C.WHITE) }) }
  else
    head = { row({ T('What would you do? Order matters.', 0.3) }) }
  end
  local right = { head[1], head[2] or row({}), row({ TREF(R, 'line', 0.26, G.C.GOLD) }, { padding = 0.04 }) }
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
    grader = grader_name()
    local all = CFQ.data.load()
    list = CFQ.data.playable(all)
    table.sort(list, function(a, b) return a.position_id < b.position_id end)
    answered = CFQ.answers.answered_set(CFQ.answers.load(fs, answers_path()), grader)
    S.idx = first_unanswered(1)
    UI.open = true
    UI.prev_repeat = love.keyboard.hasKeyRepeat()
    love.keyboard.setKeyRepeat(true)
    show_position()
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
  S.moves[#S.moves + 1] = o
  refresh_text(); write_draft()
end

local function save_and_next()
  local p = list[S.idx]
  if not S.saved then
    local best = table.concat(S.moves, ' > ')
    if S.other ~= '' then best = (best ~= '' and best .. ' > ' or '') .. 'Other: ' .. S.other end
    if best == '' and not S.skipped then R.status = 'Pick at least one move (or Skip with a reason)'; return end
    if S.skipped and S.skip_reason == '' then R.status = 'Skipping needs a reason'; S.focus = 'skip'; refresh_text(); return end
    local row_ = { position_id = p.position_id, grader = grader, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
      best_move = S.skipped and '' or best, confidence = S.conf, why = S.why, skipped = S.skipped and '1' or '0',
      skip_reason = S.skip_reason, revealed_after = '1' }
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

local DV = nil
local function open_deck()
  if not UI.open or UI.view == 'deck' then return end
  write_draft()
  UI.view = 'deck'
  local p = list[S.idx]
  local ok, def = pcall(function() return CFQ.deckview.definition(p.deck_cards, 'cfq_deck_back', (p.deck and p.deck ~= '?') and p.deck or 'Deck') end)
  if ok then G.FUNCS.overlay_menu { definition = def } else UI.view = nil; R.status = 'Deck viewer failed'; sendWarnMessage('ClownfishQuiz deck: ' .. tostring(def), 'ClownfishQuiz') end
end
local function close_deck()
  if UI.view ~= 'deck' then return end
  UI.view = nil
  show_position(true)
end
G.FUNCS.cfq_deck = function() open_deck() end
G.FUNCS.cfq_deck_back = function() close_deck() end
G.FUNCS.cfq_open = function() UI.open_quiz() end
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

-- ---------- keyboard ----------
local function next_field(dir)
  local at = 1
  for i, f in ipairs(FIELDS) do if f == S.focus then at = i end end
  S.focus = FIELDS[(at - 1 + dir) % #FIELDS + 1]
  refresh_text()
end
local function field_key(name) return ({ other = 'other', why = 'why', skip = 'skip_reason' })[name] end

function UI.handle_key(key, scancode, isrepeat)
  if key == 'f8' then if isrepeat then return true end if UI.open then UI.close() else UI.open_quiz() end return true end
  if not UI.open then return false end
  local ctrl = love.keyboard.isDown('lctrl', 'rctrl')
  if UI.view == 'deck' then
    if not isrepeat and (key == 'escape' or key == 'd') then close_deck() end
    return true
  end
  if isrepeat and key ~= 'backspace' and key ~= 'pagedown' and key ~= 'pageup' then return true end
  if key == 'escape' then UI.close(); return true end
  if key == 'd' and (S.focus == 'moves' or S.focus == 'conf') then open_deck(); return true end
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
