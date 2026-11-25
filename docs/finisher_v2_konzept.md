# Finisher V2: „Abgrund-Pfähler“ (Move #1), Ausbau

Stand 2026-11-24. Grundlage: der gebaute V2-Finisher (`src/components/finisher_component.gd`, `src/systems/finisher_rules.gd`, `data/finishers.json`, `src/fx/finisher_fx.gd`, Spinne `shadow_spider.gd` / `spider_rig.gd`, Ellie `tools/art_hero_finisher.py`).

## 1. Ziel

Der erste Finisher soll sich wie ein **verdienter, besonderer Moment** anfühlen, nicht wie ein schwerer Hieb mit Zoom. Dabei darf er sich nicht abnutzen: Er bleibt **≤ 1,3 s**, ist nach dem Herausreißen per Bewegung abbrechbar, und einmalige Extras gibt es nur einmal.

## 2. Entscheidungen

| Frage | Entscheidung |
|---|---|
| Auslösung | tödlicher Schwerttreffer (wie bisher) **und** bewusst per Interaktionstaste, wenn die Spinne `EXPOSED` (Haltung gebrochen) und der letzte Gegner ist |
| Perfekt-Fenster | später; das Grundgerüst lässt Platz dafür (Phase `press`) |
| Lohn | Ausdauer zurück (35 %) und „Schattenrausch“: Bewegung +10 % für 3 s |
| Klinge abschütteln (Flick) | erst ab Story-Flag `rescued` (sie hat den Ritter gesehen), davor die bisherige Rückkehr in die Kampfhaltung |

## 3. Ablauf (Zeitleiste, `data/finishers.json`)

| Phase | Zeit (s) | Ellie | Spinne / Welt |
|---|---|---|---|
| Absprung | 0,00–0,16 | ansetzen und abspringen (Sprung bis 13 px, Schatten bleibt am Boden) | Spinne wird festgesetzt, die Welt beginnt abzudunkeln |
| **Apex-Hang** | 0,16–0,30 | schwebt, die Klinge zeigt senkrecht nach unten, ein Glanzstern läuft über die Klinge | Zeitlupe (nur Einzelspiel), Letterbox rastet ein, Ton gedämpft |
| Einstoß | 0,34 | Aufprall, Hit-Stop 90 ms | Spinne flach, weißer Frame, Splitter |
| Nachdrücken | 0,34–0,72 | Mahlen, das Zittern wächst | Adern kriechen über den Panzer, Tonhöhe steigt |
| Herausreißen | 0,80 | Hit-Stop 120 ms, Weißblitz am Rand | der Kern reißt mit heraus und zerspringt in der Luft |
| Ausklang | 0,95–1,25 | Rückkehr in die Kampfhaltung oder **Flick** | Kern-Bruch: Panzer zerfällt, Staub wird eingesogen, Brandnarbe, Funken fliegen zu Ellie (Lohn) |

## 4. Bausteine

- **Ankündigung „Kern entblößt“:** Der Host prüft alle 0,1 s, ob der nächste Schwerttreffer eines Spielers in der Nähe den Finisher auslösen würde. Das ist der Fall, wenn die Spinne unter dem Trefferschaden liegt oder `EXPOSED` ist, sie die letzte Bedrohung ist und der Spieler ein Schwert hält. Dann setzt er `finisher_ready` (synchronisiert). Der `SpiderRig` zeigt ein pulsierendes magentafarbenes Kernglimmen auf dem Hinterleib (unlit) und dazu leise einen Herzschlag.
- **EXPOSED per Taste:** Liegt die Spinne `EXPOSED` und ist `finisher_ready`, löst `interact` in Reichweite den Finisher aus (Request an den Host, der prüft dieselben Regeln).
- **Welt:** `FinisherStage` (src/fx) ist ein lokaler CanvasLayer mit Abdunklung (Vignette in Void-Tönen) und Letterbox. Dazu Ducking der Busse `Music`/`Ambience`/`Weather`, wo vorhanden. Zeitlupe (`Engine.time_scale`) gibt es nur ohne verbundene Peers.
- **Kern-Bruch:** Spinnenpose `CORE_BREAK` statt des normalen Todes, `FinisherFx.trigger_core_break`, Brandnarbe `FinisherScar` (verglimmt in 25 s).
- **Lohn:** Host gibt Ausdauer zurück, Status-Effekt `shadow_rush` (data/status_effects.json).
- **Namenskarte:** beim ersten Finisher eines Spielstands (Flag `finisher_seen_impale`) kleine Glitch-Karte „ABGRUND-PFÄHLER“.

## 5. Vorlagen mit Google Flow

Ablage: `docs/img/finisher_ref/`. Die Vorlagen sind **Referenz** für Timing, Silhouetten und Ton, nicht Asset. Alles wird in unsere Pixelart- und Audio-Generatoren übersetzt.

**Video 1, Timing (3–4 s):**
> Top-down three-quarter view action game camera, dark forest clearing at night. A slim young woman with a one-handed sword sprints at a giant black spider with glowing violet veins, leaps onto it, hangs for a heartbeat at the top of her jump with the blade pointing straight down, plunges the sword vertically into the spider's back, grinds it deeper while violet cracks spread across the black carapace, then rips the blade out in a rising arc, tearing out a glowing magenta crystal core that shatters in mid-air; she lands in a low stance and flicks the blade clean with a sharp wrist snap. Dramatic slow motion at the apex and the rip, hit-stop feel, cinematic, high contrast, violet and magenta on near-black.

**Bild 1, Posenblatt:**
> Character pose sheet, side view, plain flat grey background, same young swordswoman in 6 key poses left to right: crouch before jump, airborne apex with sword held reverse-grip pointing down overhead, impact plunge with both hands on the hilt, leaning her weight into the hilt grinding down, explosive upward rip-out with the sword above her shoulder, relaxed low stance flicking the blade to the side. Clean silhouettes, readable limbs, no background.

**Bild 2, Kern-Bruch:**
> Close-up concept art of a giant spider's black chitin carapace cracking apart along glowing violet fissures, a magenta crystal heart being torn out on a sword tip, shards and violet dust being sucked back into the wound, dark background, game VFX concept, strong silhouettes.

**Musik/Sound, Sting (2 s):**
> Short cinematic combat sting: a sharp inhale and a high metallic shimmer, a heartbeat of near-silence, then a deep sub-bass impact with a crunchy chitin crack, a rising grinding tone, and a final bright crystal shatter that rings out into a soft dark reverb tail. No melody, no drums loop.

## 6. Prüfung

`tools/test_finisher.tscn` (headless): Zeitleiste, Ready-Flag, EXPOSED-Auslösung, Lohn, kein `time_scale` mit Peers, Flick-Ende per Flag. Vorschau `tools/preview_finisher.tscn -- --dir=/abs` speichert die Schlüsselmomente.
