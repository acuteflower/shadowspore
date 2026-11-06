# Gegner-Dossier: Schattenspinne (Shadow Spider)

> *„Ein trockenes, lautloses Knistern wie splitterndes Eis im Moos. Sechs weiche Glieder, die den Boden nicht betreten, sondern ihn verzerren. Und dann, aus der tiefsten Schwärze: fünf magentafarbene Augen, die dich fixieren, noch bevor dein Schwert den ersten Schwung ansetzt.“*

---

### 1. Basis & Physische Präsenz
* **Name:** Schattenspinne (intern: `shadow_spider`; Story-/Spezial-Varianten: `guard_spider`, `ambush_spider`)
* **Klassifizierung & Rang:** Niedere bis mittlere Leeren-Manifestation / Schattengestalt (Raubtier-Typus)
* **Habitat & Vorkommen:**
  * Waldränder, Nebelwald-Dickichte, das Leerenblühen (*Das Leerenblühen*), Minenstollen (*Mine*) und die Ränder verfallener Ruinen.
  * Tritt nachts vermehrt aus den Randrissen der Welt hervor; kann sich tagsüber an schattigen Geländestufen, Felswänden und Wegmarken verbergen.
* **Rolle im Kampfsystem:**
  * Der **aggressive Nahkampf-Pirscher und Flankierer**.
  * Setzt den Spieler durch unberechenbare Schleichstöße (*Anchor-and-Surge*), weite Sichelhiebe und heranziehende Greifanker (*Grapple Pull*) unter permanenten Positions- und Reaktionsdruck. Überwindet als einzige Einheit Höhenstufen im Gelände durch aktives Erklettern.
* **Erscheinungsbild, Silhouette & Anatomie:**
  * **Körper & Maßstab:** Rumpfsilhouette im Sprite ca. 32×26 px, durch prozedurale Gliedmaßen im Raum auf ca. 48–56 px aufspannend. Flache, bedrohliche Kriechhöhe im 3/4-Perspektiven-Squash (Faktor 0.78, abgestimmt auf Ellies 42-px-Höhe).
  * **Gliedmaßen-Rig (`SpiderRig`):** Sechs kubisch-weiche Tentakelbeine ohne starre Chitingelenke oder Knie-Solver. Sie verankern sich als echte Weltkontakte im Boden, ziehen sich elastisch ein, verformen sich unter Zugspannung und bilden sich beim Vorwärtsschreiten neu.
  * **Die Vordergreifer (`grabber: true`):** Die beiden vorderen Gliedmaßen sind spürbar dicker (Stärke 4.6 vs. 3.8/4.2 der Hinterbeine), tragen drei chitinöse Sporne/Dornen entlang des Verlaufs (Positionen `0.36`, `0.58`, `0.77`) und fungieren je nach Angriff als Klingen oder Greifhaken.
  * **Fleisch & Färbung:** Tiefschwarzes, leicht faseriges Gewebe (`07040d` bis `221740`) mit ultraschmaler, dunkler Kontur (`040208`). Kein grauer Nebel, kein Rauch. Kanten brechen in kaltes Dunkelviolett (`6a3fd0`).
  * **Leucht-DNA (Unshaded Emission):**
    * Fünf unregelmäßig angeordnete magentafarbene Augen (`ff4fd8`) mit weißem Glühkern an der Stirnpartie (`EYE_SPOTS`).
    * Drei im Rumpf pulsierende Leerenkerne (`CORE_SPOTS` in `b06bff` bis `ecd2ff`).
    * Lebendige violette Adern (`8a4dff`), die sich durch die Beinansätze ziehen und bei Angriffen aufglühen.
* **Erster Eindruck auf Ellie / Fremde:**
  * Schauderhafte Beklemmung: Es bewegt sich nicht wie ein Tier aus Fleisch und Knochen, sondern wie ein zähflüssiger, hungriger Schatten, der widernatürlich schnell zupackt.
  * Sensorik: Kein Atemhauch. Ein leises Vibrieren im Brustkorb der Spielfigur, der Geruch nach kaltem Stein, Ozon und faulendem Nadelholz.

---

### 2. Psychologischer Kern (Die innere Mechanik & Jagdtrieb)
* **Grundantrieb (Want / Jagdtrieb):**
  * **Tilgung von Licht und organischer Wärme.** Das Wesen existiert als Manifestation der Leere, die danach strebt, lebendige Materie aufzubrechen und in Leersplitter zu zersetzen.
* **Tiefstes Bedürfnis (Need):**
  * **Physische Verankerung.** Die Spinne leidet unter der Entropie ihrer eigenen instabilen Form. Durch das Schlagen von Krallen in Erde, Stein und Fleisch versucht sie, sich in der materiellen Realität festzukrallen, bevor sie wieder zerfließt.
* **Die Sollbruchstelle (Schwachpunkt & Urangst):**
  * **Wuchtige Konter & Schwungunterbrechung:** Leichte Treffer zucken wirkungslos durch ihr Gewebe, doch schwere Schläge mit massivem Rückstoß (Knockback $\ge 70$, wie der finale Stoß von Ellies Dreier-Schwertkombo) brechen ihre Angriffsvorbereitung ab und werfen sie in eine taumelnde Starre (`State.HURT`, 0.24 s Stun).
  * **Das Fenster nach dem Fehlschlag:** Sowohl nach dem Sichelschlag (0.72 s) als auch nach dem Verankerungszug (0.82 s) verharrt die Spinne in einer unbeweglichen Erholungsphase (`RECOVER`) – die goldene Sekunde für den Gegenangriff.
* **Der innere Widerspruch:**
  * **Lauernde Geduld vs. hysterische Raubtiergier:** Sie nähert sich zunächst im seitlich tänzelnden Beobachtungsorbit (`stalk`), explodiert dann jedoch in ruckartigen Vorstößen (`surge`) und schießt ohne Selbsterhaltungstrieb auf das Ziel zu.
* **Jagdmuster & Verhaltenslogik:**
  * Greift selten frontal im geraden Lauf an. Nutzt Winkel, Klippen und Hindernisse, flankiert das Ziel und schneidet Rückzugswege ab.

---

### 3. Akustik & Signal-DNA (Die sensorische Sprache)
* **Klangbild & Resonanz:**
  * Kein tierisches Fauchen oder Zischen.
  * Trockenes, kratzendes Schleifen der Klauen auf dem Untergrund, dumpfes Schwingen beim Spannen des Rumpfes, ein scharfes, peitschendes Zischen beim Vorwärtsschnellen des Greifhakens.
* **Körpersprache & Mikrobewegungen:**
  * **Im Lauerzustand (`IDLE` / `OBSERVE`):** Unruhiges Heben einzelner Beine (`twitch`), sanftes Schlingern des Rumpfes (`_yaw` und `_sway`), langsames Glühen der fünf Augen.
  * **Beim Bemerken (`NOTICE`, 0.38 s):** Rumpf hebt sich ruckartig, vordere Greifarme spreizen sich seitlich ab, Augen blitzen auf Warnhelligkeit (`ff4fd8`).
  * **Im Kletterzustand (`CLIMB`):** Vorderkrallen haken sich fest in die Felslippe, der Körper zieht sich mit sichtbarem Kraftaufwand hoch, während die Hinterbeine an der Wand tastend nachgreifen.
* **Telegraphing & Warnflächen (Visuelle Fairness):**
  * **Pixel-Fluss am Boden:** Rote Warnpixel fließen organisch vom Ursprung nach außen (`ZONE_DARK` $\rightarrow$ `ZONE_HOT` $\rightarrow$ `ZONE_FLASH`).
  * **Sichelschlag:** Roter 100°-Bodenfächer mit 40 px Radius.
  * **Verankerungszug:** Rote Verbindungslinie plus pulsierender Landekreis (13 px Radius) am Zielpunkt.
  * **Aim-Lock:** Exakt 0.30 Sekunden vor dem Zuschlagen friert die Ausrichtung der Spinne ein (`aim_locked = true`). Die Warnfläche flackert grell auf – das unmissverständliche Signal für den Spieler, zur Seite auszuweichen oder wegzusprinten.
* **Was die Spinne NIE tun würde:**
  * Fliegen, schweben oder aus der Luft abseilen.
  * Graue Staub- oder Rauchwolken erzeugen (Verstoß gegen die Voidbloom-Designregeln).
  * Wie eine gewöhnliche Chitinspinne mit starren Kniegelenken mechanisch tippeln.

---

### 4. Kampfmechanik & Verhaltensdynamiken (Die KI-DNA)
* **Sensorik & Zielerfassung (Host-autoritativ):**
  * **Sichtweite:** 170 px (halbiert auf 85 px bei schleichender Ellie!).
  * **Verlustweite:** 260 px.
  * **Klippensicht (`_sees_over_cliff`):** Erkennt Beute auch über Felskanten hinweg, wenn keine massiven Hindernisse dazwischenliegen.
* **Pirsch- und Bewegungsmuster (`_chase`):**
  * **1. Stalking-Phase (0.42 s):** Tänzelt mit 28 px/s im Halbkreis um die Beute (`orbit_side`), tastet nach Lücken.
  * **2. Surge-and-Settle:** Wechselt rhythmisch zwischen Vorstoß (100 px/s für 0.38 s) und kurzem Verharren (12 px/s für 0.22 s).
  * **3. Hindernisfühler (`_steer`):** Sechs Fühlerstrahlen prüfen das Vorfeld (bis 24 px) und navigieren weich um Bäume und Felsen herum.
* **Vollständiges Moveset:**

| Aktion | Reichweite | Windup (Aim-Lock) | Ausführung | Recovery | Schaden / Effekt |
|---|---|---|---|---|---|
| **Sichelschlag** (*Melee Cleave*) | $\le 34$ px (Hitbox bis 40 px, 100° Bogen) | 0.58 s (Lock bei 0.28 s) | 0.24 s (Treffer bei 0.14 s) | 0.72 s | **14 Schaden**, 95 Knockback. Alterniert links/rechts. |
| **Verankerungszug** (*Grapple Pull*) | 66–150 px Distanz | 0.70 s (Lock bei 0.40 s) | 0.20 s Wurf | 0.82 s | **17 Schaden** im Landekreis (13 px Radius). Zieht Ellie mit $-150$ Kraft heran, katapultiert die Spinne mit **310 px/s** zum Anker! |
| **Klippenklettern** (*Climb Traverse*) | 1 Geländestufe ($\le 88$ px Felsspanne) | 0.52 s Vorbereitung | Variabel (55 px/s Tempo, $\ge 0.65$ s) | 0.52 s | Reine Mobilität, 0 Schaden. Überwindet Höhenstufen. Bricht ab (`CLIMB_RETREAT`), falls Landeplatz blockiert ist. Cooldown: 3.5 s. |
| **Schattengeburt** (*Emergence*) | Bodengebunden | 3.20 s Gesamtdauer | Rissöffnung $\rightarrow$ Krallenzug $\rightarrow$ Aufrichten | Direkt in `IDLE` | Unverwundbar während des Erscheinens; bindet Warnaugen nach 0.75 s ein. |

* **Reaktion auf Treffer & Tod:**
  * **Trefferblitz (`hit_flash`):** Kurzes weißes Aufblitzen des Rigs, gefolgt von zuckender Gewebedeformation (`agitation`).
  * **Tod:** Bei 0 HP erlöschen Augen und Kerne. Void-Splitter stieben auf (`CPUParticles2D`). Die Spinne triggert `ShadowTrailComponent.infest()`, wodurch ein großer, pulsierender Schattenfleck mit acht Tentakeln entsteht, der 16 Sekunden lang im Boden nachzuckt.

---

### 5. Lore, Ursprung & Welt-Verflechtung
* **Die Wurzel im Void:**
  * Die Schattenspinne ist das erste Anzeichen des fortschreitenden Leerenbefalls der Wiesen. Sie manifestiert sich bevorzugt dort, wo das Gewebe der Welt dünn wird oder alte Leerenkrater die Erde aufbrechen.
* **Beute & Verwertung:**
  * **Erfahrung:** 12 XP (wird direkt an den Bezwinger vergeben).
  * **Währung:** 4–10 Kupferstücke.
  * **Materialien:**
    * 70 % Chance: 1–2× **Leersplitter** (`void_splinter`) – sprödes, pechschwarzes Kristallfragment, essenziell für spätere Veredelungen.
    * 10 % Chance: 1× **Schattenkern** (`shadow_core`) – seltener, pulsierender violetter Energiekern.
* **Beziehung zu den Hauptfiguren:**
  * **Zu Ellie:**
    * Ellies persönlicher Albtraum. Am Alten Zugang wurde sie beinahe von ihnen überwältigt. Das Bild der zuckenden Beine hat sich tief in ihre Erinnerung gebrannt. Im Kampf neigt Ellie dazu, kurz in Panik zu geraten, bevor ihr Überlebensinstinkt zuschlägt.
  * **Zu Valdric:**
    * Valdric verabscheut die Kreaturen zutiefst. Während er Banditen und Wölfe mit stoischer Gelassenheit pariert, spannt sich seine Haltung bei Schattenspinnen sofort an. Ihre unnatürlichen Kletterfähigkeiten und ihr Greifhaken verletzen jede ehrliche Fechtordnung.

---

### 6. Voice-Check (In-Game Encounter Momente)

> **Begegnung im Unterholz (Atmosphäre & Witterung):**
> *(Ein dumpfes Knacken im dichten Farn. Fünf magentafarbene Punkte öffnen sich lautlos in Bodenhöhe. Die Spinne wiegt ihren flachen Körper nach links, die vorderen Sporne schaben zart über den Moosboden, während die rote Warnfläche beginnt, das Heidekraut blutrot zu färben.)*

> **Im Kampf (Ellies Panik & Umkehrpunkt):**
> *„Valdric, sie... sie ist an der Klippe hochgezogen! Sie springt von oben! — WEG DA, DU BIEST!“* *(Ellie weicht im letzten Zehntelbruchteil des Aim-Locks zur Seite aus; die Klauen der Spinne schlagen zentimetertief in die Erde, wo Ellie eben noch stand.)*

> **Valdrics Zorn (Die Klingen kollidieren):**
> *„Hinter mich, Ellie! Fass nicht nach den Fäden! Wenn sie den Rumpf senkt, will sie den Greifhaken werfen – warte, bis sie landet, DANN schlag auf den Spalt!“*

> **Auflösung (Der Tod der Kreatur):**
> *(Das Schwert trifft mit voller Wucht das Rumpfzentrum. Die violetten Adern reißen mit einem sirrenden Ton auf. Fünf Augen flackern hektisch und verlöschen. Der Körper kollabiert wie flüssiges Pech in sich zusammen und hinterlässt einen dunklen, von feinen Fäden durchzogenen Fleck auf dem Gras.)*

---

### 7. Enemy Artist & Rigging Notes (Für 2D/3D-Artists & Animatoren)
1. **Keine Chitingelenke!** Das Modell darf niemals wie eine mechanische Tausendfüßler- oder Standard-Insekten-Krabbe gerendert werden. Die Beine müssen weich, biegsam und spannungsgeladen wie zähe Pechkabel wirken (`SpiderRig.Leg`).
2. **Palette strikt einhalten:**
   * Körpergewebe: `07040d` $\rightarrow$ `0e0919` $\rightarrow$ `1a1030` $\rightarrow$ `221740`.
   * Kontur: `040208` (1 px).
   * Rimlight: `6a3fd0`.
   * Leuchtmaske (unshaded): Augen `ff4fd8`, Kerne `b06bff` / `ecd2ff`, Adern `8a4dff`.
3. **Multiplayer-Synchronisation:**
   * Sämtliche Angriffsursprünge (`attack_origin`), Zielrichtungen (`attack_dir`), Ankerpunkte (`anchor`) und Seiten (`attack_side`) werden atomar via RPC übertragen. Lokale Clients interpolieren nur die kosmetische Beinanpassung.
4. **Kein Partikel-Rauch:**
   * Niemals Standard-Rauch-Emitter an die Beine hängen. Schattenmanifestationen in Voidbloom hinterlassen stattdessen Bodenbefall über Shader-Materialien (`ShadowTrailComponent` / `shadow_patch.gdshader`).
