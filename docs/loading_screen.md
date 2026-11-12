# Silhouetten-Ladescreen

Der zentrale `GameLauncher.start` zeigt Ellie und zwei verschiedene, zufällig
gewählte Begleiter aus Valdric, Gustav und Torben. Alle kommen von links und
laufen in der Bildmitte nach rechts. Ihre echten Ostansichten werden als reine
elfenbeinhelle Silhouetten verwendet. Nach fertigem Laden jagt die echte
Void-Spinne die Gruppe nach rechts aus dem Bild. Die Flucht dauert 1,35 Sekunden,
danach schließt die Tür-Iris in 0,3 Sekunden und öffnet in 0,4 Sekunden auf die Welt. Bei sehr kurzen
Ladevorgängen werden zuerst die gestaffelten Auftritte abgeschlossen (1,65 s).

Ressourcen laden über Godots Threaded ResourceLoader. Der Weltaufbau verwendet
den vorhandenen kooperativen Chunk-Stream. Währenddessen pausiert das Spiel;
die UI läuft weiter. Nach dem Wiederherstellen des Spielstands wird auch der
neue Aufenthaltsort fertig gestreamt. Intro und gespeicherte Storyfortsetzung
beginnen erst nach der Flucht. Verbindungs-/Ressourcenfehler zeigen eine
Rückkehr-Schaltfläche statt einer erfolgreichen Flucht.

Grafik neu aus den aktuellen Figuren backen: `py -3 tools/art_loading.py`.
Die Originalatlanten bleiben unverändert. Die Auswahl ist rein dekorativ und
verändert weder Begleiter noch Spielstand.

Die Gestaltung übernimmt `door_wipe.gdshader` unverändert: warmes Violettschwarz,
Kupferglut und ausgefranste Dither-Iris. `loading_land.gdshader` malt einen
scrollenden Erd-/Steinpfad in derselben Palette, ergänzt durch schwankendes
Gras, türkisfarbene Lebenslichter und aufsteigende Glut. Die Spinne verwendet
`SpiderRig`, `shadow_spider_body.png`, die originale Emissionsmaske und Glows.
Ein kleiner transparenter SubViewport hält die bodenverankerten Beine in
einem eigenen bewegten Raum; die UI-Bewegung verzerrt ihre Schrittgeometrie nicht.
Es gibt keine KI, Kollisionen, Beute oder Netzwerkobjekte im Ladescreen.

Prüfungen: `tools/test_loading.tscn`, `tools/test_loading_start.tscn`
(mit `-- --skip-intro`, optional `--arena`), visuelle Aufnahmen über
`tools/preview_loading.tscn -- --dir=<Ausgabeordner>`.

Animierte Vorschau: [Ladescreen](img/loading_screen_v2.gif).

Verifiziert: Ablauf-Test bestanden, echter neuer Solo-Weltstart mit 535
weiterlaufenden Animationsframes bestanden, Streaming-Regression mit null
fehlgeschlagenen Prüfungen. Screenshots für Auftritte, Lauf und Verfolgung
visuell geprüft. Der Headless-Lauf meldet daneben bestehende Probleme bei
Torben (fehlendes `assets/world/iron_rock.png`, Polygon-Triangulation),
Headless-Tastennamen sowie Ressourcenreste beim Beenden. Ein kompletter
Mehrspieler-Durchlauf wurde hierfür nicht ausgeführt. Die visuelle Überarbeitung
wurde erneut mit dem Ablauf-Test, echtem Arena-Start einschließlich Iris-Übergabe
und gerenderten Animationsframes geprüft.
