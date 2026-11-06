# Schattengeburt an Land

Die drei Story-Spinnen am Wegweiser verwenden jetzt `ShadowSpider.emerge_on_spawn`. Dieses Spawn-Attribut wird mit der Szene repliziert; der zusätzliche Zustand `EMERGE` benutzt dieselben zuverlässigen Zustandsnachrichten und Zeitangaben wie die übrige Gegnersteuerung. Bereits vorhandene Wächter behalten ihr bisheriges Verhalten.

Über 3,2 Sekunden öffnet `ShadowBirth` einen gezackten Bodenriss mit acht ungleichen Abschnitten und seitlichen Verästelungen. Jede Erscheinung erhält einen eigenen kosmetischen Zufallswert für Richtung, Verlauf, Dicke, Ausbreitungsverzögerungen, Fragmente und das Herausziehen der Beine. Die Farbpalette, fleckige Füllung, wandernden Fäden, stippligen Ränder und das zufällige Zerbröseln orientieren sich direkt an `shadow_patch.gdshader` (Fußspuren und Todesbefall). Eine kleine lokale Bildschirmverzerrung begleitet das Aufreißen. Die Fläche bleibt am ursprünglichen Weltpunkt verankert und zerfällt nach insgesamt 4,6 Sekunden. Der Effekt kann auch für andere Schattenwesen als eigenständiger Node verwendet werden.

`SpiderRig.emergence` steuert den Körper und alle sechs Gliedmaßen: Die Masse streckt sich aus dem Boden, Vorderklauen finden zuerst Halt, danach folgen Mittel- und Hinterbeine. Der Rumpf hebt sich mit einer zusätzlichen Zugbewegung an und geht ohne Spritewechsel in die normale Bewegung über. Bodenposition und KI bleiben währenddessen still; Kollision und Trefferfläche werden erst zum Ende freigegeben.

In `AmbushScene` übernimmt die Kreatur nach 0,75 Sekunden die Warnaugen. Die drei Geburten beginnen mit 1,45 Sekunden Abstand. Die erste kann bereits kämpfen, während sich die folgenden noch formen. Der bestehende Kampftimer beginnt, sobald auch die letzte vollständig erschienen ist. Rettung und Ohnmacht bleiben anschließend Teil derselben Szene.

Prüfung: `tools/test_shadow_birth.tscn` prüft drei gültige Spawnstellen am Wegweiser, die Sperre während des Erscheinens, feste Bodenpositionen, Rückkehr in den Kampf und Entfernen der Bodenverzerrung. Mit `-- --capture` speichert der Test fünf Animationsphasen unter `/tmp/shadow-birth-*.png`.

## Besiegbare Gegner im aussichtslosen Überfall

`ambush_spider` hat 150 echte HP. Treffer verringern den Balken regulär; einzelne Spinnen können sterben. Der Überfall bleibt durch Nachrücker offen: Nach 0,65 Sekunden wird ein gefallener Gegner in seinem Platz durch eine neue Spinne an einer freien Stelle rund um Ellie ersetzt. Sie erscheint mit der vollständigen Rissanimation und ist bis zu deren Ende kampfunfähig. Es gibt höchstens drei lebende oder entstehende Spinnen gleichzeitig; auflösende Leichen können kurz zusätzlich sichtbar sein. Die Gegner geben weiterhin keine Beute, Erfahrung oder Münzen.

Mit Beginn der Rettung endet das Nachrücken. Bereits tote Gegner werden aus der Schnittfolge ausgeschlossen. Zeitgrenzen, Ellies Schutz vor dem tatsächlichen Tod und der feste Ausgang durch Rettung bleiben erhalten; das Töten aller drei beendet die Quest nicht.

`Godot --path . tools/test_ambush.tscn -- --fight-back` prüft zwei normale 75-Schadens-Treffer pro Gegner, den Tod der gesamten ersten Gruppe, drei Nachrücker und den Abschluss der vollständigen Rettungssequenz.
