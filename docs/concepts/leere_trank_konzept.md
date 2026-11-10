# Leere-Trank – Konzept

Ein neuer Tranktyp mit 3 Stufen (selten, episch, legendär) statt der üblichen 5.
Thema: Die Leere – ein Riss in der Realität, der Leben saugt und Void-Schaden verursacht.

## Icons

- `assets/items/potion_leere_1.png` – Stufe 1 (selten)
- `assets/items/potion_leere_2.png` – Stufe 2 (episch)
- `assets/items/potion_leere_3.png` – Stufe 3 (legendär)

Gleiche schlanke Hexen-Flasche wie die anderen Tränke. Dunkles Void-Purple mit
leuchtender Rift/Bruchstelle im Inneren, die mit steigender Stufe wächst.

## Trank-Effekte

### Stufe 1 – Seltene Leere (potion_leere_1)
- **Effekt:** Öffnet einen kleinen Riss der Leere um den Spieler (Radius 2m) für 5 Sekunden
- **Schaden:** 8 Void-Schaden pro Sekunde an alle Gegner im Radius
- **Nebenwirkung:** Spieler verliert 2 HP pro Sekunde (die Leere saugt alles)
- **Cooldown:** 60 Sekunden

### Stufe 2 – Epische Leere (potion_leere_2)
- **Effekt:** Größerer Riss (Radius 3m) für 6 Sekunden
- **Schaden:** 12 Void-Schaden pro Sekunde an Gegner
- **Lebensraub:** 50% des Void-Schadens wird als Heilung an den Spieler zurückgegeben
- **Nebenwirkung:** Spieler verliert 1 HP pro Sekunde (effektiv +5 HP/Sek durch Lebensraub)
- **Cooldown:** 90 Sekunden

### Stufe 3 – Legendäre Leere (potion_leere_3)
- **Effekt:** Massive Rift (Radius 4m) für 7 Sekunden
- **Schaden:** 18 Void-Schaden pro Sekunde an Gegner
- **Lebensraub:** 75% des Void-Schadens als Heilung
- **Zusatz:** Gegner im Radius werden leicht zum Riss-Zentrum hingezogen (Slow 30%)
- **Nebenwirkung:** Keine (die Leere ist vollständig kontrolliert)
- **Cooldown:** 120 Sekunden

## Einbau in das Effekt-System

### Neuer Effekt-Typ: `void_rift`

```gdscript
# In src/effects/effect_types.gd (oder entsprechender Datei)
const VOID_RIFT = "void_rift"
```

### Effekt-Datenstruktur

```json
{
  "type": "void_rift",
  "duration": 5.0,
  "radius": 2.0,
  "damage_per_second": 8,
  "damage_type": "void",
  "lifesteal_percent": 0,
  "player_damage_per_second": 2,
  "slow_percent": 0
}
```

### Implementierung

Neue Effekt-Klasse `src/effects/void_rift_effect.gd`:

```gdscript
extends AreaEffect

func _on_tick(delta):
    var enemies = get_overlapping_bodies()
    for enemy in enemies:
        if enemy.is_enemy():
            var dmg = damage_per_second * delta
            enemy.take_damage(dmg, "void", self)
            if lifesteal_percent > 0:
                player.heal(dmg * (lifesteal_percent / 100.0))
    
    if player_damage_per_second > 0:
        player.take_damage(player_damage_per_second * delta, "void", null)
```

### Trank-Integration

In `src/items/potion.gd` (oder entsprechender Trank-Logik):

```gdscript
if potion_type == "leere":
    var rift_data = {
        type = "void_rift",
        duration = [5, 6, 7][tier - 1],
        radius = [2, 3, 4][tier - 1],
        damage_per_second = [8, 12, 18][tier - 1],
        lifesteal_percent = [0, 50, 75][tier - 1],
        player_damage_per_second = [2, 1, 0][tier - 1],
        slow_percent = [0, 0, 30][tier - 1]
    }
    effect_system.apply("void_rift", player.position, rift_data)
```

## Besonderheiten des Tranks

1. **Void-Schaden:** Nutzt den bestehenden Void-Schadentyp, gegen den manche Gegner
   schwach sind (z.B. Lichtwesen) und andere resistent (z.B. Schattenkreaturen).

2. **Risiko/Rendite:** Stufe 1 schädigt den Spieler – macht den Trank strategisch
   interessant (nur bei hoher HP oder gegen starke Gegner einsetzen).

3. **Areal-Effekt:** Im Gegensatz zu den meisten Tränken, die nur den Spieler betreffen,
   wirkt der Leere-Trank auf die Umgebung – ideal für Gruppenkampf.

4. **Nur 3 Stufen:** Anders als Heil-/Ausdauertränke (5 Stufen) zeigt dies die
   experimentelle, seltene Natur des Tranks.

## Einbau in Esmas Alchemie-Laden

### items.json Einträge

```json
{
  "potion_leere_1": {
    "name": "Seltene Leere",
    "kind": "potion",
    "rarity": "rare",
    "potion": { "type": "leere", "tier": 1 },
    "icon": "res://assets/items/potion_leere_1.png",
    "description": "Esmas experimenteller Leere-Trank. Öffnet einen kleinen Riss, der Gegner mit Void-Schaden trifft – aber auch dich selbst.",
    "buy_price": 250,
    "sell_price": 125
  },
  "potion_leere_2": {
    "name": "Epische Leere",
    "kind": "potion",
    "rarity": "epic",
    "potion": { "type": "leere", "tier": 2 },
    "icon": "res://assets/items/potion_leere_2.png",
    "description": "Verbesserter Leere-Trank. Die Rift saugt Leben von Gegnern und gibt es dir zurück. Sehr gefährlich, sehr effektiv.",
    "buy_price": 500,
    "sell_price": 250
  },
  "potion_leere_3": {
    "name": "Legendäre Leere",
    "kind": "potion",
    "rarity": "legendary",
    "potion": { "type": "leere", "tier": 3 },
    "icon": "res://assets/items/potion_leere_3.png",
    "description": "Esmas Meisterwerk. Eine vollständig kontrollierte Rift, die Gegner zum Zentrum zieht und massiven Void-Schaden verursacht.",
    "buy_price": 1000,
    "sell_price": 500
  }
}
```

### Laden-Integration

In `src/shops/esma_shop.gd` (oder entsprechend):

```gdscript
// Leere-Tränke erst ab bestimmtem Spielstand verfügbar
if player.get_reputation("esma") >= 3:
    shop_items.append("potion_leere_1")
if player.get_reputation("esma") >= 5:
    shop_items.append("potion_leere_2")
if player.get_reputation("esma") >= 8:
    shop_items.append("potion_leere_3")
```

### Dialog-Fragmente

Esmas Kommentare beim Kauf:

- **Stufe 1:** "Vorsichtig mit dem hier. Die Leere ist... unbeständig. Aber gegen die Dinger im Hexenwald – unübertroffen."
- **Stufe 2:** "Endlich habe ich das Lebensraubelement stabilisiert. Tränke den Tod von deinen Feinden, speiste dich davon."
- **Stufe 3:** "Mein Lebenswerk. Eine Rift, die nicht einmal mich selbst frisst. Du wirst die Gegner zum Riss hinziehen sehen... wie Wasser in ein Loch."

## Balance-Überlegungen

- Void-Schaden sollte gegen bestimmte Gegnertypen besonders effektiv sein
- Cooldowns verhindern Spam
- Stufe 1 ist riskant – Spieler muss HP-Management beachten
- Stufe 3 ist stark, aber teuer und erst spät verfügbar
- Slow-Effekt auf Stufe 3 ist subtil (30%) – hilft bei Bosskämpfen

## TODO / Nächste Schritte

- [ ] Effekt-System um `void_rift` erweitern
- [ ] Void-Schadentyp in Gegnerrüstungen implementieren (falls nicht vorhanden)
- [ ] Partikeleffekt für die Rift erstellen (schwarzer Kreis mit lila Rand)
- [ ] Sound-Effekt: tiefes Summen + Riss-Geräusch
- [ ] In items.json eintragen
- [ ] In Esmas Laden einbauen
- [ ] Testen: Schaden, Lebensraub, Cooldowns
