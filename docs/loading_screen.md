# Silhouetten-Ladescreen

Der zentrale `GameLauncher.start` zeigt Ellie und zwei verschiedene, zufällig
gewählte Begleiter aus Valdric, Gustav und Torben auf einem schwebenden,
ausgefransten Felspfad in der Leere (`loading_veil.gdshader`). Alle Elemente
erscheinen im nativen `1×`-Pixelmaßstab in einer einheitlichen, sanft in drei
Mondlicht-Stufen modellierten hellen Silhouette (`silhouette.gdshader`):
vorweg gleitet und schlägt ein Begleiter-Rabe mit den Flügeln, ein kleiner
türkisfarbener Irrlicht-Funke schwebt vor Ellie, und am Pfadrand ziehen
Leerenblüten, Mondglöckchen, Glühfarne und Wegstein-Kristalle vorbei.

Sobald das Laden abgeschlossen ist (`complete()`), erscheint voraus die
Wegstein-Wächterin in heller Silhouette (nach mindestens `1,85 s`, damit kurze
Ladevorgänge die gestaffelten Auftritte ruhig abschließen). Das Irrlicht fliegt
in ihr Herz, lässt ihre Kristallkrone und die geditherte Lichtsäule
(`waystone_beam.gdshader`) samt Runenring erwachen, der Rabe steigt in den
Lichtstrahl auf und die Gruppe schreitet in das Heiligtum, wo sich jede
Silhouette per `4×4`-Bayer-Dither in aufsteigende Sternlichtfunken auflöst
(`2,50 s`), bevor sich der violette Schleier auf die Welt öffnet (`reveal_world()`).

Ressourcen laden über Godots Threaded ResourceLoader. Der Weltaufbau verwendet
den vorhandenen kooperativen Chunk-Stream. Währenddessen pausiert das Spiel;
die UI läuft weiter. Nach dem Wiederherstellen des Spielstands wird auch der
neue Aufenthaltsort fertig gestreamt. Intro und gespeicherte Storyfortsetzung
beginnen erst nach dem Übergang. Verbindungs-/Ressourcenfehler zeigen eine
Rückkehr-Schaltfläche.

Kompakten Atlas neu aus den aktuellen Figuren und dem Raben backen:
`python3 tools/art_loading.py` (`assets/ui/loading_cast.png`). Die
Originalatlanten bleiben unverändert; gebackene Bodenschatten werden dabei
sauber entfernt und alle Stiefelsohlen auf eine gemeinsame Grundlinie gesetzt.

Prüfungen: `tools/test_loading.tscn`, `tools/test_loading_start.tscn`
(mit `-- --skip-intro`, optional `--arena`), visuelle Aufnahmen über
`tools/preview_loading.tscn -- --dir=<Ausgabeordner>`.
