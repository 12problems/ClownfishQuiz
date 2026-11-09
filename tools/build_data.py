"""Build the shipped positions file from a v6 positions.csv.
Strips bot/engine fields and ids, then obfuscates with a repeating-key XOR (not real security).
usage: python build_data.py positions.csv out/positions.dat [--key CLOWNFISH]
Keep the plaintext CSV OUT of the repo.
"""
import argparse, csv, io, json, sys
KEEP_CATEGORIES = {"buy_or_save", "sell_to_replace", "reroll_or_leave", "pack_pick", "tarot_use"}  # shop-phase decisions only
DROP = {"play_hand", "tarot_name", "tarot_need", "bot_top3", "play_table", "joker_order_scores", "game_id", "decision_index", "notes", "seen_before", "retrigger", "source"}

def xor(data: bytes, key: bytes) -> bytes:
    return bytes(b ^ key[i % len(key)] for i, b in enumerate(data))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("dst"); ap.add_argument("--key", default="ClownfishQuizV1")
    a = ap.parse_args()
    rows = [r for r in csv.DictReader(open(a.src, encoding="utf-8-sig", newline="")) if r["category"] in KEEP_CATEGORIES]
    out = [{k: v for k, v in r.items() if k not in DROP} for r in rows]
    payload = json.dumps({"v": 1, "positions": out}, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    open(a.dst, "wb").write(xor(payload, a.key.encode()))
    print("wrote", a.dst, len(out), "positions,", len(payload), "bytes")

if __name__ == "__main__":
    main()
