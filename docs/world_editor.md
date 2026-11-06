# Weltwerkstatt

Öffnen: **Esc → Entwickler → Map-Editor öffnen**. Der Editor ist für die Solo-Welt vorgesehen; im Multiplayer und in der Testarena erscheint ein entsprechender Hinweis. Die Simulation pausiert, die Kamera bewegt sich unabhängig vom Spieler.

- **Auswählen / verschieben:** Objekt in der Nähe seiner Basis anklicken und ziehen. Im Objektbereich Art, Variante, Größe und Spiegelung einstellen und „Übernehmen“ klicken. „Duplizieren“ übernimmt die Auswahl in das Platzierungswerkzeug.
- **Platzieren / löschen:** Auf die Welt klicken. Pro Karten-Zelle kann ein interaktives Objekt stehen. Verschieben funktioniert auch über Abschnittsgrenzen.
- **Boden malen:** Bodenmotiv, Biom und Pinselradius wählen, dann ziehen.
- **Höhe formen:** Zielhöhe 0–3 und Material wählen. Klippenkonturen und Kollision werden zusammen aktualisiert. Bestehende generierte Vegetation wird neu auf ihre Eignung geprüft.
- **Rampe / Treppe:** Drei Zellen breite Verbinder mit oberem und unterem Podest. Sie führen nach Norden von Zielhöhe H nach H+1; H darf höchstens 2 sein. Verbinder ergänzen die Landschaft, verbinden aber nicht automatisch entfernte Plateaus.
- **Terrain zurücksetzen:** Entfernt die örtlichen Terrainänderungen und stellt die generierte Grundlage wieder her.

WASD bewegt die Kamera, Mittel- oder Rechtsziehen verschiebt sie, das Mausrad zoomt am Zeiger. F / „Zum Spieler“ zentriert sie wieder. Strg/Cmd+Z und Strg/Cmd+Shift+Z machen Schritte rückgängig bzw. wiederholen sie; Strg/Cmd+S speichert. Ein vollständiger Pinselstrich ist ein Undo-Schritt, bis zu 80 Schritte bleiben in der Sitzung verfügbar.

Die Karte wird atomar in **user://world_edits.json** gespeichert, unabhängig von **user://save.json**. Sie gilt auch für neue Spielstände derselben Grundkarte. Beim Schließen mit Änderungen stehen Speichern, Verwerfen und Weiterbearbeiten zur Auswahl. Bestehende Ressourcen unter assets/ und die eingefrorene Weltkarte werden nicht überschrieben. Die Küstenlinie bleibt die vorhandene Landfläche; Meer/Leere lassen sich nicht in Land umwandeln.

Die zusätzliche Kartenebene enthält Objektänderungen und Terrainzellen und ist an den SHA-256 der Grundkarte gebunden. Bei einer anderen Grundkarte wird sie nicht automatisch angewendet. Im Multiplayer lädt der Host seine gespeicherte Karte und sendet sie an beitretende Clients. Tritt während einer Editorsitzung jemand bei, werden ungespeicherte Änderungen verworfen und der Solo-Editor geschlossen.

## Prüfung

`Godot --headless --path . tools/test_world_editor.tscn`

Optional mit Grafik: `Godot --path . tools/test_world_editor.tscn -- --capture=/tmp/world-editor.png`

Der Test schreibt nur eine separate Testdatei und entfernt sie wieder. Er prüft Objektzustände über Chunk-Wechsel, Undo/Redo, Höhenfeld und Kollision, Rampen, Speichern/Laden sowie den Wechsel zwischen Editor und Spiel.
