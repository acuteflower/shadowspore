# Gegner-Dossier: Boss 1 – Mornath, der Himmelsspalter

> *„Sieh ihn dir an, Ellie. Kein Nest. Kein Himmel mehr, der ihn trägt. Nur drei kalte Steine über dem Schlund des Nichts – und ein Eid, der selbst den Verfall überdauert hat.“*  
> — **Valdric**, an der Schwelle zum Himmelsplateau

---

### 1. Basis & Physische Präsenz
* **Name & HUD-Titel:** `MORNATH, DER HIMMELSSPALTER` (Gold `#ffd98a`, zweizeilig im Boss-HUD)
* **Interner Bezeichner (ID):** `boss_sky_cleaver`
* **Beiname / Titel:** *Die Schwinge des Letzten Lichts* / *Der Zeuge des Falls*
* **Klassifizierung:** Titanische Fluggestalt / Säulenwächter der Leere (Boss 1)
* **Arena & Habitat:** 
  * Das *Lunarith-Trigon*: Ein windgepeitschtes Hochplateau am Weltrand, auf dem drei uralte, achtseitige Monolithen (die Säulen des Himmelsspiegels) emporragen.
  * Dahinter fällt das Land senkrecht in den bodenlosen Abgrund der Leere ab.
* **Erscheinungsbild, Silhouette & Anatomie:**
  * **Thronend (Sitzpose auf den Säulenkapitellen):** Ca. 56 px hoch, 48 px breit. Eingezogene, gotisch anmutende Wasserspeier-Silhouette; die Schwingen hüllen den Rumpf wie ein geschlossener Lamellenmantel ein, während die Klingen-Federn steil aufragen. Sechs starre Magentaschlitze (je 3 vertikal gestaffelte Augenschlitze pro Kopfseite, `#ff4fd8`) glühen auf den Schläfen seines schmalen, schnabelartigen Basaltschädels.
  * **Im Flug (Gleit- & Sturzflug):** Gewaltige Spannweite von **78–88 px** bei 54–58 px Körperlänge. Seine Schwingen bestehen aus segmentierten, dolchartigen Klingen-Federn aus mineralisiertem Horn (`0d0a17` bis `262440`), verbunden durch dehnbare violette Fleischmembranen. An den Flügelkanten und Flanken wehen 4–6 schleifende Schattenstränge (Void Tendrils) im Fahrtwind.
  * **Brust & Reliquie:** Ein uraltes, korrodiertes Bronzegeschirr mit den verblichenen Gravuren des alten Sonnenordens ist tief in sein schwarzes Fleisch eingewachsen. In der Brustbeinsenke pulsiert der ungeschützte **Resonanz-Void-Kern** (`ecd2ff` bis `fff7ff`), umfasst von rippenartigen Hornspangen.
  * **Greifkrallen & Läufe:** Kräftige Vogelbeine mit vier massiven Spreizzehen und Basaltkrallen, geformt, um die Kanten der Säulenkapitelle formschlüssig zu umklammern.
* **Erster Eindruck auf Ellie & Valdric:**
  * Majestätischer Schrecken. Keine formlose Schattenmasse, sondern ein gefallenes, aristokratisches Wesen – ein königlicher Bote, den die Leere in ein schneidendes Werkzeug aus Pech und Knochen verwandelt hat.

---

### 2. Ursprung & Mythologie des Voids
* **Vor dem Einbruch:**
  * Mornath war ein geweihter *Aethelbussard* (Sonnenadler), das lebendige Wappentier des *Ordens der Hohen Zinne* (Valdrics ehemaligem Ritterorden). Auf den Gipfeln von Lunarith stationiert, diente er den Rittern als himmlischer Kundschafter und entzündete mit dem Reflexionslicht seines Geschirrs die Signalfeuer über den Grenzlanden.
* **Die Verderbnis:**
  * Als der Große Riss das Land aufriss und die Bastionen fielen, weigerte sich Mornath, seinen Horst zu verlassen. Tagelang flog er durch die aufsteigenden Rauch- und Leerenstürme, auf der Suche nach seinen gefallenen Reitern.
  * Die Leere verschlang ihn schleichend: Sie sog das Mark aus seinen Röhrenknochen und ersetzte es durch reines Vakuum. Seine Schwingen wurden zu pechschwarzem Chitin; seine Augen brannten aus. Er wurde unsterblich, doch um den Preis ununterbrochener physischer Entropie.
* **Warum die drei Säulen?**
  * Leerenkreaturen besitzen keine irdische Masse; der Flug in der lebendigen Atmosphäre greift ihre Zellstruktur an (*Sonnenwunde* / atmosphärische Reibung). Mornath kann nicht endlos in der Luft bleiben, ohne zu zerfasern.
  * Die drei Säulen des Himmelsspiegels reichen tief in den Granitsockel der Welt und strahlen als letzte Monumente noch eine uralte, harmonische Erdresonanz aus. Nur wenn Mornath auf ihnen landet, verdichtet sich sein zerfallender Schattenleib wieder. Sie sind seine lebenserhaltenden Anker im Nichts.

---

### 3. Psychologischer Kern (Die innere Mechanik)
* **Grundantrieb (Want):**
  * **Absolute, ungestörte Starre.** Jede Schwingung im Boden – das Hämmern von Werkzeugen, Schritte im Schotter, das Ziehen von Klingen – dringt über das Gestein der Säulen wie brennende Nadeln in seine Klauen. Er stürzt herab, um jede Quelle von Unruhe und Schall auszulöschen.
* **Tiefstes Bedürfnis (Need):**
  * **Die Erlösung von der Schwerelosigkeit.** Mornath will nicht mehr fliegen. Jeder Flügelschlag ist Agonie. Er sehnt sich nach einem echten Boden, der ihn trägt, und nach dem Ende seiner jahrhundertelangen, sinnlosen Wacht.
* **Schmerz & Tragik (Die instabile Form):**
  * In seinen hohlen Knochen herrscht ein zerstörerischer Unterdruck (Kavitation). Bei jedem Richtungswechsel im Flug reißen feine Risse in seinen Flügelhäuten auf, die in Kaltviolett aufflackern. Auf der Säule sitzend zuckt sein Körper in krampfhaften Mikroschwingungen, während er nach Atem ringt.
* **Sollbruchstelle (Urangst & Schwachpunkt):**
  * **Der Bodenabsturz (Verlust der Höhe):** Mornaths Urangst ist der irdische Erdboden. Verfehlt er seinen Sturzflug oder wird er im Flug gekontert/parriert, schlägt er hart auf dem Steinboden der Arena auf.
  * Für 1.4 Sekunden liegt er flügellahm im Staub (`GROUNDED_STUN`): Seine Chitinflügel verkeilen sich, sein Tempo sinkt auf Null, und der Nackenkern liegt offen für kritische Schläge.

---

### 4. Die 3 Säulen: Das Lunarith-Trigon & Phasen-Dramaturgie
Die Arena nutzt die drei Säulen für eine feste Dreiphasen-Architektur, synchron zur Bossleiste (`const PHASES: Array[float] = [1.0 / 3.0, 2.0 / 3.0]`):

* **Säule 1: Säule der Morgendämmerung (Nord, Phase 1: 100 % – 66 % HP)**
  * *Haltung:* Wachsam, hochmütig, lauernd. Mornath beobachtet die Spieler mit schief gelegtem Kopf.
  * *Rhythmus:* Lange Thronphasen auf der Säule, gefolgt von einzelnen, messerscharf telegrafierten Sturzflügen auf das Ziel mit dem meisten Lärm.
* **Säule 2: Säule des Zenits (Ost, Phase 2: 66 % – 33 % HP)**
  * *Haltung:* Aufgeschreckt, gereizt. Violette Adern durchziehen seine Flügel.
  * *Rhythmus:* Mornath wechselt im Flug dynamisch zwischen den Säulen. Er erzeugt beim Vorbeiflug schneidende Unterdruckwellen und schleudert Chitinsplitter über die Arena.
* **Säule 3: Säule des Abgrunds (Südwest, Phase 3: 33 % – 0 % HP)**
  * *Haltung:* Verzweifelt, panisch. Die Südwest-Säule steht unmittelbar an der Abbruchkante zum bodenlosen Void.
  * *Rhythmus:* Mornath klammert sich an den Stein, während Risse durch das Podest schießen. Seine Flugmanöver werden unberechenbar und rasend; er greift mit verzweifeltem Klingenwind an.

---

### 5. Dramaturgische Bindung: Ellie & Valdric

* **Bedeutung für Ellie (Persönliche Prüfung):**
  * *Freiheit vs. Zerrissenheit:* Ellie floh aus der königlichen Festung, weil sie die Vögel auf den Zinnen als Inbegriff uneingeschränkter Freiheit sah. Mornath zerstört diese kindliche Romantik: Er kann fliegen, doch er ist der gefangenste Sklave von allen.
  * *Überwindung der Höhenangst:* Die Arena am Rand des Abgrunds zwingt Ellie, ihren Schwindel zu überwinden und ihren `Blink` präzise an der tödlichen Klippenkante einzusetzen.
* **Bedeutung für Valdric (Der Orden & alte Eide):**
  * Valdric erkennt das Emblem an Mornaths Hals: Es ist das Wappentier seines eigenen gefallenen Ordens.
  * Mornath ist ein warnender Spiegel für Valdric selbst: Ein Diener, der nicht loslassen konnte und an toten Eiden zugrunde ging. Valdrics Gnadenstoß für Mornath befreit nicht nur den Vogel, sondern markiert Valdrics inneren Übergang: Er dient nicht mehr toten Mauern, sondern den lebenden Menschen um Ellie.

---

### 6. Voice-Check: Dialoge an der Schwelle

```dialogue
[VOR DEM KAMPF - BETRETEN DES PLATEAUS]
Ellie:   "Valdric... sieh mal nach oben. Auf der linken Säule... da sitzt etwas.
          Ist das... ein Vogel? Nein, Vögel klingen nicht wie klirrendes Fensterglas..."
Valdric: "Tritt zurück, Ellie. Sofort. Nicht weiter vorstoßen...
          Bei den Ahnen der Zinne. Das ist kein Tier aus dem Wald.
          Das ist ein Aethelbussard... Er trägt noch das Geschirr der Wacht."
Ellie:   "Er sieht uns an. Valdric... er hat keine Augen. Nur dieses brennende Violett..."
Valdric: "Er steht seit dem Fall hier oben. Allein.
          Zieh die Klinge, Kleines. Er kennt keine Freunde mehr. Nur noch das Fleisch der Leere."

[PHASENWECHSEL - DIE SÄULE DES ABGRUNDS]
Ellie:   "Er weicht zurück! Er klammert sich an die Kante über dem Nichts!
          Er will gar nicht wegfliegen... Er hat Angst vor dem Absturz!"
Valdric: "Er kann nicht mehr fliegen, Ellie! Seine Knochen tragen ihn nicht mehr!
          Wenn er herabstößt, weich zur Seite aus – bring ihn auf den Stein!"

[NACH DEM SIEG - DER GNADENSCHLAG]
Ellie:   "Es... es ist vorbei. Er hat sich einfach aufgelöst.
          Kein Schrei mehr. Nur... Wind. Er wollte die ganze Zeit nur schlafen, oder?"
Valdric: (kniet nieder, berührt mit dem Eisenhandschuh das gefallene Bronzegeschirr)
         "Er stand auf Posten, als der Himmel fiel. Niemand hat ihm befohlen abzutreten.
          Deine Wacht ist beendet, Himmelsspalter. Ruh dich aus. Ich übernehme von hier."
```

---

### 7. Sensorik & Klang-Architektur
* **Olfaktorik (Geruch):**
  * Scharfes, gefrorenes Ozon wie nach einem Höhenblitz.
  * Trockener, kalter Quarzitstaub, untermalt von einer schwachen, schwelenden Note von versengtem Horn. Keinerlei Fäulnis oder Aasgeruch!
* **Schwingen-Klang:**
  * Kein weiches Daunenflattern.
  * Schneidendes Schmirgeln von Chitinlamellen (`4.2 kHz bis 6.8 kHz`), wie das synchrone Ziehen dutzender Klingen aus der Scheide.
  * Beim Gleiten ein hohler, saugender Sub-Bass (`36 Hz`), der den Raum akustisch entleert, gefolgt von peitschendem Zischen.
* **Die unheimliche Stille auf den Säulen:**
  * Sobald Mornaths Krallen auf dem Säulenkapitell aufsetzen, bricht der peitschende Gebirgswind abrupt ab.
  * Totenstille, in der nur das eigene Herzklopfen (Night-UI-Puls) und das feine, glasige Knistern (`Tick-Krrr-Tick`) von gefrierendem Schattenplasma an seinen Krallen zu hören sind.
