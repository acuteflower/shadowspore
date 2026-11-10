#!/usr/bin/env python3
"""Add void_rift status effect to status_effects.json."""
import json

with open('data/status_effects.json', 'r', encoding='utf-8') as f:
    d = json.load(f)

d['void_rift'] = {
    'name': 'LEERE',
    'seconds': 5.0,
    'tick': 99.0,
    'damage_ratio': 0.0,
    'min_damage': 0,
    'color': '6a3fa0',
    'hot': 'c8b4f0',
    'glyph': 'drop',
    'tiered': True
}

with open('data/status_effects.json', 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
print('Added void_rift status effect')