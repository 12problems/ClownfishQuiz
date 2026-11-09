# Clownfish Contribution Quiz

A Balatro mod for Multiplayer 1.0.5+ (MultiplayerAPI + Steamodded 26.1002). While you wait in the queue you can answer real
(anonymised) ranked decisions. When a match is found your progress is saved and the quiz closes.

- Reads only the scenarios shipped in `data/positions.dat`. It never reads or changes your run.
- Answers are plaintext CSV in `<Balatro save folder>/config/ClownfishQuiz/answers_<name>.csv`. Send that file to Rob.
- `data/positions.dat` is lightly obfuscated (repeating-key XOR, key in `core.lua`). This only stops casual reading; it is not security.

## Scope
Shop-phase decisions only: buy/save, sell to replace, reroll/leave, pack pick, tarot use (370 positions). Hand-play, joker-order and tarot-target questions were intentionally dropped.

## Status
Scaffold: pure modules (CSV, answers, loader) are tested with `python -I tests/test_pure.py` (needs `pip install lupa`).
Queue/match-found polling is written but not yet run in game. UI is a placeholder.

## Building the data file
`python -I tools/build_data.py positions.csv data/positions.dat` (strips bot/engine fields and ids). Never commit the plaintext CSV.
