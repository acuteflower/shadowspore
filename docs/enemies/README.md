# Voidbloom – Gegner-Kompendium & Dossiers

Dieses Verzeichnis versammelt die verbindlichen Charakter- und Verhaltensdossiers sämtlicher Gegner und Schattenkreaturen in *Voidbloom*. Sie folgen dem Standard der Figuren-Dossiers aus [`docs/characters/`](../characters/) und dienen als gestalterische, animatische und systemische Richtschnur für Enemy Artists, Gameplay-Programmierer und Level-Designer.

---

### Verfügbare Gegner-Dossiers

1. **[Schattenspinne (Shadow Spider)](schattenspinne.md)**
   * **Typ:** Aggressiver Nahkampf-Pirscher & Kletterer (*Pouncer / Harasser*)
   * **Mechaniken:** Stalking-Orbit, Surge-and-Settle, 100°-Sichelschlag, Verankerungszug (Grapple Pull mit 310 px/s), Klippenklettern über Höhenstufen, Schattengeburt.
   * **Rig:** Prozedurales 6-Bein-Rig (`SpiderRig`) ohne starre Kniegelenke, dehnende Gliedmaßen, 5 magentafarbene Augen, pulsierende Kerne.

2. **[Leerenhorcher (Void Listener)](leerenhorcher.md)**
   * **Typ:** Akustischer Distanz-Scharfschütze & Zonen-Disrupter (*Sniper / Area Denial*)
   * **Mechaniken:** Vollständige Hörmatrix (Gehen 180 px, Sprinten 255 px, Waffenschwung 240 px, Schleichen 48 px), Distanzhaltung (95–133 px), Spaltprojektil (Resonance Wave), Abwehrschockwelle (115° Druckschrei mit Screen-Verzerrung).
   * **Rig:** 100 % prozedurale Pixelgeometrie (`ListenerRig`), 2 Standbeine, 2 tastende Fühlerbeine, dreilappiges Haupt mit aufspringendem Resonanzrachen.

3. **[Leerenbrecher (Void Crusher)](leerenbrecher.md)**
   * **Typ:** Schwerer Frontlinien-Koloss, Tank & Raumverdränger (*Juggernaut / Vanguard*)
   * **Mechaniken:** 80 HP, frontale 75%-Schadensreduktion, spaltender Bodenschlag (120°-Bodenfächer mit 54 px Radius), Rammstoß (Bull Rush mit Kollisions-Stun an Felsen/Bäumen), freiliegender Nackenkern (300 % Kritischer Schaden bei Flankenangriffen).
   * **Rig:** Asymmetrisches Hybrid-Rig (massiver Basaltkeulen-Arm rechts, Tasttentakeln links, Chitin-Schildkragen, pulsierender Kern-Glowpass im Nacken).

*(Vorgemerkt für spätere Realisierung: **Der Schattengleiter** – flüssiger Schatten-Assassine / Bodenphantom).*

---

### Verbindliche Kernstandards für alle Schattenwesen
* **Kein Rauch, kein Hellgrau-Nebel:** Schattenwesen bestehen aus pechschwarzem, weltbeleuchtetem Fleisch (`07040d`–`221740`) mit 1 px Kontur (`040208`).
* **Unshaded Emission:** Nur magentafarbene Augen (`ff4fd8`), violette Adern (`8a4dff`) und helle Kerne (`ecd2ff` / `b06bff` / `fff7ff`) glühen nachts ungetönt und pulsieren synchron zur Angriffsaufladung.
* **Bodenbefall statt Rauch:** Jeder Schritt hinterlässt kurzlebige Schattenflecken; der Tod erzeugt einen 16–20 s nachwehenden Tentakel-Befall (`ShadowTrailComponent` / `shadow_patch.gdshader`).
* **Visuelle Vorankündigung (Telegraphing):** Rote Pixel fließen organisch in den Boden (`ZONE_DARK` $\rightarrow$ `ZONE_HOT` $\rightarrow$ `ZONE_FLASH`). Der Aim-Lock friert vor Schuss/Schlag ein (0.3 s Spinne, 0.25 s Horcher, 0.35 s Brecher), um faire Ausweichmanöver zu garantieren.
* **Schwungunterbrechung:** Schwere Treffer mit Knockback $\ge 70$ (wie Ellies dritter Schwertstreich) brechen Ladephasen ab.
