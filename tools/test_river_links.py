"""River links and the Hexenwald lake: joins are exact, water stays on open floor, the lake is in the lake bake."""
import json
from pathlib import Path
import numpy as np
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
read = lambda n: json.loads((ROOT/'data'/f'{n}.json').read_text())
d, links, lakes, lcfg = read('rivers_baked'), read('river_links')['links'], read('lakes_baked'), read('lakes')
relief = np.asarray(Image.open(ROOT/'assets/world/relief.png'))
checks = 0
nodes = {tuple(e['a']) for e in d['edges'] if 'link' not in e} | {tuple(e['b']) for e in d['edges'] if 'link' not in e}
for link in links:
    es = [e for e in d['edges'] if e.get('link') == link['id']]
    assert es, link['id']
    for a, b in zip(es, es[1:]):
        assert a['b'] == b['a'], 'link is not one continuous line'
    ends = [tuple(es[0]['a']), tuple(es[-1]['b'])]
    first_snap = isinstance(link['points'][0], dict)
    last_snap = isinstance(link['points'][-1], dict)
    assert (not first_snap or ends[0] in nodes) and (not last_snap or ends[1] in nodes), 'link does not join an existing river node'
    for e in es:
        for key in ('a', 'b'):
            tx, ty = int(e[key][0] // 16), int(e[key][1] // 16)
            assert relief[ty, tx, 1] & 15 == 0 and relief[ty, tx, 0] == 0, 'link on a cliff or raised ground'
    checks += 3
assert sum(1 for f in d['fords'] if len(f) > 3) > 0, 'links have no crossing band'
pond = [l for l in lakes['lakes'] if l.get('inland')]
assert len(pond) == len(lcfg['ponds']) == 1 and 'shore' in pond[0] and 'dry' in pond[0]
# the lake outflow ends in the lake: its first point is wet in the lake field
first = [e for e in d['edges'] if e.get('link') == 'hex_link_lake'][0]['a']
rec = lakes['chunks'][f'{int(first[0])//512},{int(first[1])//512}']
field = np.asarray(Image.open(ROOT/rec['field'].removeprefix('res://')))
assert field[int(first[1]) % 512, int(first[0]) % 512, 0] == 255
print(f'RIVER LINKS: {checks + 3} checks, PASS; {len(links)} links, lake {pond[0]["id"]} {pond[0]["area_tiles"]} tiles')
