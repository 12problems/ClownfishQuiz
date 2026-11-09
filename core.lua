-- Clownfish Contribution Quiz: entry point (Steamodded main_file).
-- Reads ONLY the scenarios shipped in data/positions.dat; never reads or alters run state.
CFQ = SMODS.current_mod
CFQ.KEY = 'ClownfishQuizV1' -- obfuscation key, see README (not security)
CFQ.DIR = 'config/ClownfishQuiz' -- inside the Balatro save folder

local function load_src(name)
  local chunk, err = SMODS.load_file('src/' .. name .. '.lua', CFQ.id)
  assert(chunk, err)
  return chunk()
end

CFQ_UTIL = load_src('util')
CFQ.util = CFQ_UTIL
CFQ.answers = load_src('answers')
CFQ.data = load_src('data')
CFQ.hooks = load_src('hooks')
CFQ.deckview = load_src('deckview')
CFQ.ui = load_src('ui')

CFQ.config = CFQ.config or {}
CFQ.hooks.install()
CFQ.ui.install_input()
CFQ.ui.install_menu_button()

-- Steamodded config tab: a button that opens the quiz (settings are inside the quiz: press S).
CFQ.config_tab = function()
  return { n = G.UIT.ROOT, config = { align = 'cm', padding = 0.2, colour = G.C.BLACK, r = 0.1 }, nodes = {
    UIBox_button { button = 'cfq_open', colour = G.C.ORANGE, minw = 4, minh = 0.7, label = { 'Open Clownfish Quiz' }, scale = 0.4 },
    { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = { { n = G.UIT.T, config = { text = 'Settings: press S inside the quiz (name, answers folder, import).', scale = 0.3, colour = G.C.UI.TEXT_LIGHT } } } },
  } }
end
