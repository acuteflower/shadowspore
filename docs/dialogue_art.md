# Verbindliche Vorgaben für Dialog-Charakterbilder

Ellies aktuell im Spiel gerendertes Porträt ist die Maßreferenz. Diese Regeln gelten für alle neuen Sprecher und Varianten. Pose, Ausdruck, Blickrichtung innerhalb der Dreiviertelansicht und Gestik dürfen zur Szene passen.

| Merkmal | Feste Vorgabe |
|---|---|
| Logisches Bild | 103 × 153 Pixel pro Zustand, transparenter Hintergrund |
| Anzeige | Exakt 206 × 306 Pixel im 640 × 360-Spielbild; Nearest Neighbor, keine geglätteten Kanten |
| Ausschnitt | Kompletter Kopf bis Hüfte; am unteren Rand angeschnitten. Keine Knie, Beine oder Füße. |
| Kamera | Augenhöhe, Dreiviertelansicht zum Dialogtext; keine isometrische Ansicht des Spielsprites |
| Kopfgröße | Kopf inklusive Haar/Helm ungefähr 45–53 Pixel hoch; voluminöse Frisuren oder kleine Helmaufsätze zählen mit |
| Vertikale Anker | Kopfoberkante etwa Y 3–8; Augen/Visier etwa Y 30–40; Kinn etwa Y 52–60; Schultern etwa Y 58–70 |
| Breite | Schultern/Kleidung füllen ungefähr 85–95 % der Bildbreite; seitliche Ausläufer dürfen den Bildrand berühren |
| Unterkante | Hüfte bei Y 145–152; Hände, Gürtel und Waffenknauf dürfen hier sichtbar sein |
| Stil | Große bewusst gesetzte Pixelgruppen, eckige Konturen, ungefähr 24–32 Farben, 3–4 flache Stufen je Material |
| Licht | Links oben; Formen auch auf dunklem UI-Grund lesbar, keine reine Silhouette |
| Animation | Höchstens etwa ein logischer Pixel Atmung/Schwanken; Kopfgröße und Ausschnitt bleiben zwischen Zuständen gleich |

Rüstung darf breitere Schultern als Ellie haben. Helmaufsätze dürfen die Kopfgröße nicht durch viel Leerraum verkleinern. Die Gesichtspartie beziehungsweise das Visier bleibt auf vergleichbarer Höhe. Dramatische Posen dürfen diese anatomischen Anker leicht verschieben, aber niemals einen anderen Bildmaßstab erzeugen.

## Frei wählbar

Gefühlsausdruck, Armhaltung, Handgesten, Verletzungen und Accessoires folgen der Figur und Szene. Ein geschlossener Helm muss nicht künstlich ein menschliches Gesicht bekommen. Eine Waffe darf zum Bild gehören, soll aber die Gesichtspartie nicht verdecken und keinen Ganzkörperausschnitt erzwingen.

## Umsetzung und Abnahme

`DialogueArt` hält Bildraster, Anzeigemaß und Verankerung zentral. Ellie wird aus ihrem bestehenden Zustandsatlas auf genau dieses Raster gerendert. Weitere Sprecher liefern normalisierte Einzelbilder in 103 × 153 Pixeln; Sprite-Sheets müssen ausdrücklich ihre einzelnen Zustandsrechtecke angeben. Kein Sprecher erhält eine eigene Streckung oder einen abweichenden Zoom als nachträgliche Größenkorrektur.

Vor Übernahme das neue Bild mit Ellie in identischer Anzeigegröße nebeneinander auf dem echten Dialoghintergrund prüfen: Kopf-/Augenhöhe, Schulterlinie, Hüftanschnitt, sichtbare Pixelgröße und Helligkeit. Bei Abweichungen den Bildausschnitt beziehungsweise die Illustration korrigieren.

## Unbekannte Personen

Der Silhouettenfilter `unknown_portrait.gdshader` arbeitet auf demselben Porträt und Raster. Er entfernt sämtliche Erkennungsfarben einschließlich Leuchtvisier und lässt nur zwei dunkle Violettstufen für Silhouette und angedeutetes Volumen übrig. Transparenz, Bildmaß und Animation bleiben erhalten.

Dialogzeilen mit `speaker: "???"` sind automatisch unbekannt. `unknown: true` kann andere Sprecher ausdrücklich verbergen. Mit `known_flag` wird stattdessen der gespeicherte Queststatus geprüft; nach Setzen dieses Flags erscheinen Originalbild und `known_name`. Die Rettung verwendet `knows_adventurer` und `known_name: "RITTER"`. Das Flag wird in der Rettung noch nicht gesetzt, weil Ellie ihn dort noch nicht kennt. Der spätere Kennenlerndialog kann es setzen, ohne das Bild zu wechseln.

Prüfung/Vorschau: `Godot --path . tools/preview_dialogue_art.tscn` kontrolliert Raster, unbekannte/bekannte Darstellung, Ellie und den gespeicherten Identitätsstatus. Vergleich unter `/tmp/dialogportraits-v2-vergleich.png`, Dialog unter `/tmp/ritter-unbekannt-dialog.png`.

## Ritter, Revision 2

Mit dem eingebauten Imagegen-Tool generiert, mit Ellie als Stil-/Ausschnittreferenz und dem alten Ritter als Identitätsreferenz. Original mit Alpha: `assets/ui/sources/adventurer_dialogue_v2.png`. Spielasset: `assets/ui/portrait_adventurer_v2.png`. Normalisierung: `tools/prepare_dialogue_portrait.gd` setzt proportionale Einpassung ohne Streckung, Nearest Neighbor, harte Transparenz und 30 feste Materialfarben um. Das alte Porträt bleibt als Vorgänger erhalten und wird im Dialog nicht mehr verwendet.

Generierungsprompt: Ein einzelnes transparentes Pixel-Art-Dialogporträt des erwachsenen Ritters/Retters, Ellies grobe Pixelcluster und Kopf-bis-Hüfte-Ausschnitt als Maßreferenz. Dreiviertelansicht nach rechts, große Helmpartie, breite Schultern, geschlossener dunkelstahlfarbener Helm mit kurzem zurückgelegtem Kamm und schmalem weißviolettem Sehschlitz. Weinroter Mantel und Wappenrock, abgenutzte dunkle Plattenrüstung mit lesbaren lavendelgrauen Lichtflächen, sparsame Goldakzente. Beide Handschuhe ruhen auf dem Schwertknauf an der Hüfte; die Klinge läuft unten aus dem Bild. Ruhig, beschützend und geheimnisvoll. Wie auf 103×153 Pixeln handgezeichnet, deutlich eckige Pixelstufen, ungefähr 30 Farben und 3–4 flache Töne pro Material, Licht links oben, keine Glättung oder Verläufe. Kein Hintergrund, Text, Rahmen, Ganzkörperbild oder reine dunkle Silhouette im Originalasset.
