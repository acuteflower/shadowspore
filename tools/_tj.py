"""Scratch helper (not part of the game): load data/town.json, apply a function, write it back in the same format (1-space indent, CRLF, no ASCII escaping)."""
import json, sys
def edit(fn, path='data/town.json'):
    d = json.loads(open(path, encoding='utf-8').read())
    fn(d)
    open(path, 'w', encoding='utf-8', newline='\r\n').write(json.dumps(d, indent=1, ensure_ascii=False) + '\n')
