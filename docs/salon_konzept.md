# Freiluftsalon – „Spiegelplatz“ (Konzept)

Ein kleines, offenes Stück der Stadt (Kategorie WOHNEN), an dem Ellie später ihr Aussehen ändert
(Frisur, Haarfarbe, Kleidung). **Stufe 1 (jetzt):** Textur, Animationen, Platz nehmen und
Kamerafahrt. **Stufe 2 (später):** das Anpassungsfenster.

## Die Idee

Kein Haus, sondern ein **Plätzchen unter freiem Himmel**, wie ein Wanderfriseur, der sich am Dorfrand
niedergelassen hat: ein niedriges Holzpodest mit gewebtem Teppich, darauf ein kleiner Frisierstuhl,
daneben ein großer, stehender Spiegel in einem Messing-/Goldrahmen mit vorspringender Ablage voller
Kämme, Bürsten und Fläschchen, dahinter ein offenes Regal mit Tüchern, Tiegeln und Bändern. Darüber
ein **leichter Pergola-Rahmen** aus zwei Pfosten mit einem Stoffsegel, das im Wind atmet, und einer
Laterne. Kein Dach, keine Wände: man sieht durch, es gehört zur Wiese.

Der Spiegel ist das Herz: Im Glas spiegelt sich nicht die Welt, sondern ein **sanfter Abendhimmel in
Türkis und Violett** (die zwei Lichtfarben des Spiels). Ein Glanzstreifen wandert in Abständen über das
Glas. Nachts glimmen der Spiegelrand, die Fläschchen und die Laterne.

## Aufbau (von vorne gesehen, 3/4-Ansicht)

| Ort | Was | Detail |
|---|---|---|
| vorne links-mittig | **Frisierstuhl** | kleiner Holzstuhl auf einem Drehfuß, Sitzpolster in Samtviolett, niedrige, geschwungene Lehne; steht an der Vorderkante des Podests |
| rechts daneben | **Standspiegel** | hoch (größer als Ellie), ovales Glas, Goldrahmen mit kleinen Blattranken; darunter eine vorspringende **Ablage**: Kamm, Bürste, Schere, 2–3 Fläschchen (eins türkis glimmend), ein Tiegel, ein Väschen mit einer Blume |
| hinten | **offenes Regal** | zwei Bretter zwischen schlanken Pfosten: gefaltete Tücher (Creme, Rosé), Tiegel, Bänderrollen, ein Bund Trockenblumen; von der oberen Kante hängen Bänder |
| links hinten | **Topfpflanzen** | ein bauchiger Tontopf mit Farn, ein kleinerer mit Blüten |
| oben | **Pergola** | zwei dünne Pfosten an den Ecken, ein Querbalken, darunter ein Stoffsegel (Creme mit Rosé-Saum, Wellenkante) |
| am Balken | **Laterne** | kleine Messinglaterne mit warmem Licht |
| Boden | **Podest + Teppich** | runde Holzbohlen, gewebter Teppich (Violett/Türkis-Muster) unter dem Stuhl |

## Animationen

1. **Spiegelglanz** (Glow-Bogen, 8 Bilder): ein schräger heller Streifen wandert über das Glas, danach Ruhe.
2. **Funkelnde Fläschchen** (im selben Glow-Bogen): versetztes Aufblitzen.
3. **Stoffsegel** (Part mit Sway): atmet im Wind, Wellenkante flattert.
4. **Laterne** (Part mit Sway + Glow): pendelt leicht, Licht flackert.
5. **Bänder am Regal** (Part mit Sway): flattern.
6. **Wenn Ellie Platz nimmt:** der Spiegel „erwacht“ – das Glimmen wird heller, ein paar Funken steigen auf.

## Platz nehmen (Stufe 1)

- **E → „PLATZ NEHMEN“** am Stuhl (ein Sitzplatz, Blick nach Süden zur Kamera).
- Ellie geht hin, setzt sich (bestehende Sitz-Posen, die „Haar“-Geste passt perfekt).
- Nur auf ihrem eigenen Bildschirm: die Kamera **fährt nah an sie heran** (Zoom ≈ 2,2×, leicht
  zum Spiegel versetzt), die HUD blendet aus. Ein kleiner Schriftzug: „HIER KANNST DU BALD DEIN
  AUSSEHEN ÄNDERN“.
- **E / Bewegen → aufstehen**, die Kamera fährt zurück.

## Daten

`data/town.json` → `pieces.salon`: Kategorie `living`, braucht den Brunnenplatz, einmal pro Stadt,
`"salon": true` (der Sitzplatz wird ein `SalonSeat`). Kosten: Holz, Stein, Pflanzenfasern, ein
Leuchtpilz für das Glimmen im Spiegel.

## Stufe 2 (später)

Ein `SalonWindow`, das sich öffnet, sobald sie sitzt: links Ellie groß im Spiegelbild, rechts
Ranken mit Frisuren, Farben und Kleidung (wie die Escape-Menü-Ranken). Änderungen gehen an den Host
und werden mit dem Spieler gespeichert.
