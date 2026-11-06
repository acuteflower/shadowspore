# Leerenbrecher – Sprite-Assets

Die PNG-Paare enthalten die weltbeleuchtete Basis und den deckungsgleichen
Leuchtpass. Die Konzeptstudie unter `docs/img/void_crusher_concept.png` ist
nur eine Entwurfsreferenz und kein Sprite oder Glow-Layer.

## Raster und Animationen

Jede Zelle ist **80 × 80 px** groß; der Weltanker liegt bei **(40, 70)**
innerhalb jeder Zelle. Die Zeilen sind von oben nach unten **E, SE, S, SW,
W, NW, N, NE**; die Spalten enthalten die Frames in zeitlicher Reihenfolge.
Die Ansichten werden einzeln aus derselben asymmetrischen Geometrie
projiziert, nicht gespiegelt. Frame-Indizes unten beginnen bei 0.

| Dateiname | Frames pro Richtung | Verwendung |
|---|---:|---|
| `void_crusher_idle` | 4 | Atemzyklus, Loop; ca. 1,5 s pro Zyklus |
| `void_crusher_walk` | 6 | langsamer Schrittzyklus, Loop; Kontaktphasen 0 und 3 |
| `void_crusher_windup` | 3 | Ausholen des Felsarms |
| `void_crusher_lock` | 1 | eingefrorene Zielrichtung vor dem Schlag |
| `void_crusher_strike` | 2 | Einschlag und kurze Folgepose |
| `void_crusher_hurt` | 3 | kurze Trefferreaktion |
| `void_crusher_death` | 4 | einfacher Zusammenbruch zum Bodenanker |

Zu jedem Namen gibt es `<name>.png` und `<name>_glow.png`. Die Zeitsteuerung
für Windup, Lock und Strike soll die Zustandsmaschine anhand der Zeiten im
Gegnerdossier übernehmen. Die Sequenzen sind grafische Grundposen: separate
Animationen für Rammstoß, Abwehrfeger, abrupte Felsfragmente und Bodenrisse
sind noch nicht enthalten.

## Godot-Einbindung

Für beide Sprite2D-Knoten dieselbe Region bzw. dieselben Frame-Indizes
verwenden. Bei `centered = false` ist `offset = Vector2(-40, -70)`; bei
`centered = true` ist `offset = Vector2(0, -30)`. Der Glow-Sprite liegt
positionsgleich über dem Basis-Sprite und verwendet ein `CanvasItemMaterial`
mit `light_mode = LIGHT_MODE_UNSHADED` und `blend_mode = BLEND_MODE_ADD`.
Die Basis bleibt weltbeleuchtet. Nearest-Filter ohne Mipmaps verwenden und
beide Ebenen bei Animation und Richtungswechsel synchron halten.

Der Rückenkern ist in rückwärtigen und seitlichen Ansichten sichtbar; seine
Darstellung befindet sich ungefähr 32 px oberhalb des Ankers. Die Hitbox,
Pulsanimation, Bodenwarnungen und der Gegner selbst sind nicht Teil dieser
Texturen. Erzeugung: `python3 tools/create_void_crusher_sprites.py` mit Pillow.
