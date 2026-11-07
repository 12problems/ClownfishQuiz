"""Runs the pure Lua modules under lupa. python -I tests/test_pure.py (from repo root)."""
import csv, io, os, sys, tempfile
from lupa import LuaRuntime
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lua = LuaRuntime(unpack_returned_tuples=True)
BITSHIM = """
bit = {bxor = function(a,b) local r,p=0,1 while a>0 or b>0 do local x,y=a%2,b%2 if x~=y then r=r+p end a=(a-x)/2 b=(b-y)/2 p=p*2 end return r end}
"""
lua.execute(BITSHIM)
def load(name):
    return open(os.path.join(root, 'src', name), encoding='utf-8').read()
lua.execute("CFQ_UTIL = (function() " + load('util.lua') + " end)()")
A = lua.execute("return (function() " + load('answers.lua') + " end)()")
U = lua.globals().CFQ_UTIL

# xor roundtrip against the python builder (bytes runtime)
sys.path.insert(0, os.path.join(root, 'tools'))
from build_data import xor
blua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
blua.execute(BITSHIM)
bU = blua.execute("return (function() " + load('util.lua') + " end)()")
data = bytes(range(256)) * 3
key = b"ClownfishQuizV1"
assert bU.xor(xor(data, key), key) == data, "xor mismatch"

# csv roundtrip incl. quotes/newlines/commas
cols = ['a', 'b', 'c']
recs = [{'a': 'x,y', 'b': 'he said "hi"', 'c': 'line1\nline2'}, {'a': '', 'b': '1', 'c': '|'}]
text = U.csv_write(lua.table_from(cols), lua.table_from([lua.table_from(r) for r in recs]))
back = list(csv.DictReader(io.StringIO(text, newline='')))
assert back == recs, back
d = U.csv_dicts(text)
assert d[1]['c'] == 'line1\nline2'.replace('line1\nline2', 'line1\nline2') or True
assert d[1]['a'] == 'x,y' and d[1]['b'] == 'he said "hi"' and d[1]['c'] == 'line1\nline2'

# answers upsert / import
store = {}
fs = lua.table_from({})
fs['read'] = lambda p: store.get(p)
fs['write'] = lambda p, s: (store.__setitem__(p, s) or True)
p = A.path('d', 'Rob')
A.upsert(fs, p, lua.table_from({'position_id': 'q1', 'grader': 'Rob', 'best_move': 'Buy X', 'why': 'a, "b"'}))
A.upsert(fs, p, lua.table_from({'position_id': 'q1', 'grader': 'Rob', 'best_move': 'Sell Y'}))
A.upsert(fs, p, lua.table_from({'position_id': 'q2', 'grader': 'Rob', 'best_move': 'Z'}))
rows = list(csv.DictReader(io.StringIO(store[p], newline='')))
assert [r['best_move'] for r in rows] == ['Sell Y', 'Z'] and list(rows[0].keys()) == list(A.COLUMNS.values()), rows
old = open('/tmp/oldans.csv', 'w', newline='')
w = csv.DictWriter(old, fieldnames=list(A.COLUMNS.values())); w.writeheader()
w.writerow({'position_id': 'q1', 'grader': 'Rob', 'best_move': 'OLD'}); w.writerow({'position_id': 'q9', 'grader': 'Rob', 'best_move': 'NEW'}); old.close()
added, skipped = A.import_text(fs, p, open('/tmp/oldans.csv', newline='').read())
assert (added, skipped) == (1, 1), (added, skipped)
rows = list(csv.DictReader(io.StringIO(store[p], newline='')))
assert [r['position_id'] for r in rows] == ['q1', 'q2', 'q9'] and rows[0]['best_move'] == 'Sell Y'
print("all pure tests passed")
