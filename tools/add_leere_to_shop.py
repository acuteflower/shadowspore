import json

with open('data/shops.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

# Add leere potions to witch_counter buy list
buy = data['witch_counter']['buy']
buy.append({'item': 'potion_leere_1', 'price': 120, 'trust': 15})
buy.append({'item': 'potion_leere_2', 'price': 250, 'trust': 40})
buy.append({'item': 'potion_leere_3', 'price': 500, 'trust': 65})

with open('data/shops.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=1, ensure_ascii=False)
print('Added leere potions to shop')