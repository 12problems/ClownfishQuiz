-- Deck viewer clone: builds FAKE cards from the scenario's deck list (never touches G.playing_cards
-- or any real run state) and shows them per suit like the game's own deck viewer.
local V = {}

local SUIT_LETTER = { Spades = 'S', Hearts = 'H', Clubs = 'C', Diamonds = 'D' }
local RANK_LETTER = { Ace = 'A', King = 'K', Queen = 'Q', Jack = 'J', ['10'] = 'T' }
local ENH = { Lucky = 'm_lucky', Gold = 'm_gold', Steel = 'm_steel', Stone = 'm_stone', Mult = 'm_mult', Bonus = 'm_bonus', Wild = 'm_wild', Glass = 'm_glass' }
local SEAL = { ['Gold Seal'] = 'Gold', ['Red Seal'] = 'Red', ['Blue Seal'] = 'Blue', ['Purple Seal'] = 'Purple' }
local EDITION = { Foil = 'foil', Holographic = 'holo', Polychrome = 'polychrome' }
local SUIT_ORDER = { 'Spades', 'Hearts', 'Clubs', 'Diamonds' }

-- "King of Spades [Steel, Gold Seal, +10 chips] x2" -> { suit, rank, enh, seal, edition, bonus, count }
function V.parse_entry(s)
  local raw = s
  s = s:gsub('^#%d+%s+', ''):gsub('%s*%(in hand%)', '')
  local count = tonumber(s:match(' x(%d+)$')) or 1
  s = s:gsub(' x%d+$', '')
  local rank, suit, rest = s:match('^(%w+) of (%a+)%s*(.*)$')
  if not rank then return nil end
  local e = { rank = rank, suit = suit, count = count, raw = raw }
  local inner = rest:match('%[(.*)%]')
  if inner then
    for tok in (inner .. ', '):gmatch('(.-), ') do
      if ENH[tok] then e.enh = ENH[tok]
      elseif SEAL[tok] then e.seal = SEAL[tok]
      elseif EDITION[tok] then e.edition = EDITION[tok]
      else local n = tok:match('^%+(%d+) chips$'); if n then e.bonus = tonumber(n) end end
    end
  end
  return e
end

function V.parse_deck(text)
  local out = {}
  for _, item in ipairs(CFQ.util.split_list(text)) do
    local e = V.parse_entry(item)
    if e then out[#out + 1] = e end
  end
  return out
end

local function make_card(e, scale)
  local key = (SUIT_LETTER[e.suit] or 'S') .. '_' .. (RANK_LETTER[e.rank] or e.rank)
  local proto = G.P_CARDS[key]
  if not proto then return nil end
  local card = Card(0, 0, G.CARD_W * scale, G.CARD_H * scale, proto, G.P_CENTERS[e.enh or 'c_base'])
  if e.seal then pcall(function() card:set_seal(e.seal, true, true) end) end
  if e.edition then pcall(function() card:set_edition({ [e.edition] = true }, true, true) end) end
  if e.bonus then card.ability.perma_bonus = e.bonus end
  return card
end

V.cards = {} -- { {card=, entry=} } of the currently open viewer

-- Dim every card except the selected ones (when anything is selected).
function V.refresh_selection(is_selected)
  local any = false
  for _, it in ipairs(V.cards) do if is_selected(it.entry) then any = true end end
  for _, it in ipairs(V.cards) do
    local sel = is_selected(it.entry)
    it.card.greyed = any and not sel or false
    pcall(function() it.card:highlight(sel) end)
    if sel and it.card.juice_up then pcall(function() it.card:juice_up(0.3, 0.3) end) end
  end
end

-- Returns a UIBox definition for the viewer. back_func: G.FUNCS name run by the Back button.
-- o (optional): { on_pick = fn(entry, card), is_selected = fn(entry), ref = table with .deckhint/.targets text }
function V.definition(deck_text, back_func, title, o)
  o = o or {}
  V.cards = {}
  local entries = V.parse_deck(deck_text)
  local by_suit, total = { Spades = {}, Hearts = {}, Clubs = {}, Diamonds = {} }, 0
  for _, e in ipairs(entries) do
    if by_suit[e.suit] then
      for _ = 1, e.count do table.insert(by_suit[e.suit], e); total = total + 1 end
    end
  end
  local rights = {}
  local rank_n = { Ace = 14, King = 13, Queen = 12, Jack = 11 }
  for _, suit in ipairs(SUIT_ORDER) do
    local list = by_suit[suit]
    table.sort(list, function(a, b) return (rank_n[a.rank] or tonumber(a.rank) or 0) > (rank_n[b.rank] or tonumber(b.rank) or 0) end)
    if #list > 0 then
      local area = CardArea(G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h, 6.5 * G.CARD_W, 0.6 * G.CARD_H,
        { card_limit = #list, type = 'title', view_deck = true, highlight_limit = 0, card_w = G.CARD_W * 0.7, draw_layers = { 'card' } })
      for _, e in ipairs(list) do
        local c = make_card(e, 0.7)
        if c then
          c.T.x = area.T.x + area.T.w / 2
          c.T.y = area.T.y
          c:hard_set_T()
          area:emplace(c)
          V.cards[#V.cards + 1] = { card = c, entry = e }
          if o.on_pick then
            c.states.click.can = true
            c.states.hover.can = true
            c.click = function(self) o.on_pick(e, self) end
          end
        end
      end
      rights[#rights + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.08 }, nodes = { { n = G.UIT.O, config = { object = area } } } }
    end
  end
  return create_UIBox_generic_options({
    back_func = back_func, back_label = 'Back (Esc)', minw = 12,
    contents = {
      { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = {
        { n = G.UIT.R, config = { align = 'cm', minh = 0.9, padding = 0.1 }, nodes = { { n = G.UIT.T, config = { text = (title or 'Deck') .. ' - ' .. total .. ' cards', scale = 0.4, colour = G.C.UI.TEXT_LIGHT, shadow = true } } } },
        o.ref and { n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.T, config = { ref_table = o.ref, ref_value = 'deckhint', scale = 0.3, colour = G.C.GOLD, shadow = true } } } } or nil,
        o.ref and { n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.T, config = { ref_table = o.ref, ref_value = 'targets', scale = 0.26, colour = G.C.WHITE, shadow = true } } } } or nil,
        { n = G.UIT.R, config = { align = 'cm', padding = 0.12 }, nodes = rights },
      } },
    },
  })
end

return V
