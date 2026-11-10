#!/usr/bin/env python3
"""Add leere potion items to items.json."""
import json

with open('data/items.json', 'r', encoding='utf-8') as f:
    items = json.load(f)

items['potion_leere_1'] = {
    'name': 'Trübe Leere',
    'kind': 'potion',
    'rarity': 'uncommon',
    'enchant_slots': 0,
    'max_stack': 5,
    'hotbar': True,
    'icon': 'res://assets/items/potion_leere_1.png',
    'potion': {'type': 'leere', 'tier': 1},
    'description': 'Esmas Spezialsud, Stufe I. 5 Sekunden ein Riss der Leere. Gegner erleiden Void-Schaden, du verlierst etwas Gesundheit. Danach 20 Sekunden Pause.'
}
items['potion_leere_2'] = {
    'name': 'Klare Leere',
    'kind': 'potion',
    'rarity': 'rare',
    'enchant_slots': 0,
    'max_stack': 5,
    'hotbar': True,
    'icon': 'res://assets/items/potion_leere_2.png',
    'potion': {'type': 'leere', 'tier': 2},
    'description': 'Esmas Spezialsud, Stufe II. 6 Sekunden ein großer Riss. Hoher Void-Schaden an Gegnern, 50% als Lebensraub. Danach 20 Sekunden Pause.'
}
items['potion_leere_3'] = {
    'name': 'Leere-Meistersud',
    'kind': 'potion',
    'rarity': 'epic',
    'enchant_slots': 0,
    'max_stack': 5,
    'hotbar': True,
    'icon': 'res://assets/items/potion_leere_3.png',
    'potion': {'type': 'leere', 'tier': 3},
    'description': 'Esmas Spezialsud, Stufe III. 7 Sekunden massive Rift. Enorme Void-Schaden, 75% Lebensraub, Gegner verlangsamt. Danach 20 Sekunden Pause.'
}

with open('data/items.json', 'w', encoding='utf-8') as f:
    json.dump(items, f, indent=1, ensure_ascii=False)
print('Added 3 leere potion items')