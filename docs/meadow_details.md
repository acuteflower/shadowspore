# Kleine dekorative Pflanzen

`src/world/meadow_details.gd` erzeugt 24 kleine Pixelvarianten direkt als gemeinsamen Atlas: Gräser und Samenhalme, Wildblumen, Farne, Blattrosetten sowie trockene Stängel. `assets/shaders/meadow_details.gdshader` bewegt die oberen Teile mit dem gemeinsamen Weltwind und einem lokalen Kontaktfeld in ganzen Pixeln. Die Wurzeln bleiben fest. Details zur Umsetzung: [wind_and_vegetation_plan.md](wind_and_vegetation_plan.md).

`WorldLevel._place_meadow_details` verteilt die Pflanzen in lockeren, rauschgesteuerten Gruppen. Eine eigene Zufallsfolge pro Chunk hält bestehende Weltobjekte unverändert. Verteilung und Varianten bleiben beim erneuten Laden gleich. Nebelwald bevorzugt Farne; Glasklippen sind sparsamer; die übrigen Biome erhalten passende Farbtönungen. Gebackene Wege, Steinflächen, gesperrte Storybereiche, Klippen und die Grundflächen größerer Pflanzen werden ausgespart.

Die Dekoration wird gemeinsam pro Chunk gezeichnet und mit diesem entfernt. Sie besitzt keine Kollision, Interaktion, Sammelressourcen, individuellen Prozessfunktionen oder permanenten Speicherzustände. Kontaktreaktionen werden in einem kleinen temporären Feld pro Chunk gesammelt und automatisch zurückgesetzt.

Prüfung: Godot 4.7.2 importiert und rendert fehlerfrei; Ingame-Vorschau bei Nacht und Tageslicht kontrolliert.
