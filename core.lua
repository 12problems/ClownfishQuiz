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
CFQ.ui = load_src('ui')

CFQ.config = CFQ.config or {}
CFQ.hooks.install()
