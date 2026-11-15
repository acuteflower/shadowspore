/**
 * Authentische Weltkarten-Metadaten von Shadowspore.
 * Extrahiert aus data/world_map.json, data/biomes.json, data/waystones.json,
 * data/vistas.json, data/hallgrat.json, data/meadow_pois.json, data/meadow_wonders.json,
 * data/aurelith_arena.json, data/witch_arena.json und data/town.json.
 */

export const WORLD_TILES = 1100;
export const MAP_CELL = 4;
export const START_TILE = [463, 616];
export const TOWN_NAMES = ["GLIMMRAST", "LICHTHORST", "DÄMMERHAIN", "ASCHENLICHT", "WISPERFURT", "KERZENRAND", "NEBELHERD", "VIOLETTHAIN"];

export const SUPERS = [
  {
    "id": 0,
    "name": "Die Lichtung",
    "biome": "meadow",
    "tier": 1,
    "mood": "warm, mythisch, noch friedlich",
    "color": "#5fb36b",
    "center": [
      495.0,
      555.1
    ],
    "regionCount": 29
  },
  {
    "id": 1,
    "name": "Hexenwald",
    "biome": "witch_forest",
    "tier": 6,
    "mood": "dunkel, kalt, Hexenwerk",
    "color": "#4d5f72",
    "center": [
      821.0,
      892.0
    ],
    "regionCount": 1
  },
  {
    "id": 2,
    "name": "Sonnenquarz-Öde",
    "biome": "quartz_desert",
    "tier": 7,
    "mood": "heiß, weit, Sand und singender Quarz",
    "color": "#d9a45b",
    "center": [
      784.7,
      179.9
    ],
    "regionCount": 5
  }
];

export const BIOMES = {
  "meadow": {
    "index": 0,
    "name": "Die Lichtung",
    "tier": 1,
    "mood": "warm, mythisch, noch friedlich",
    "color": "#5fb36b"
  },
  "mist_forest": {
    "index": 1,
    "name": "Nebelwald",
    "tier": 2,
    "mood": "dicht, dämmrig, Nebel zwischen den Stämmen",
    "color": "#3d8f86"
  },
  "glass_cliffs": {
    "index": 2,
    "name": "Glasklippen",
    "tier": 3,
    "mood": "karg, kühl, violette Kristalle",
    "color": "#8a6fd6"
  },
  "sunken_ruins": {
    "index": 3,
    "name": "Versunkene Ruinen",
    "tier": 4,
    "mood": "still, nass, melancholisch",
    "color": "#d98a4a"
  },
  "void_bloom": {
    "index": 4,
    "name": "Das Leerenblühen",
    "tier": 5,
    "mood": "schwarz, violett, fremd",
    "color": "#c9506f"
  },
  "witch_forest": {
    "index": 5,
    "name": "Hexenwald",
    "tier": 6,
    "mood": "dunkel, kalt, Hexenwerk",
    "color": "#4d5f72"
  },
  "quartz_desert": {
    "index": 6,
    "name": "Sonnenquarz-Öde",
    "tier": 7,
    "mood": "heiß, weit, Sand und singender Quarz",
    "color": "#d9a45b"
  }
};

export const BIOMES_ORDER = ["meadow", "mist_forest", "glass_cliffs", "sunken_ruins", "void_bloom", "witch_forest", "quartz_desert"];

export const WAYSTONES = [
  {
    "id": "hang_wachterin",
    "name": "WÄCHTERIN AM HANG",
    "tile": [
      840,
      649
    ],
    "paved": false
  },
  {
    "id": "ebene_wachterin",
    "name": "WÄCHTERIN DER EBENE",
    "tile": [
      598,
      523
    ],
    "paved": false
  },
  {
    "id": "lichtung_wachterin",
    "name": "WÄCHTERIN DER LICHTUNG",
    "tile": [
      373,
      858
    ],
    "paved": false
  },
  {
    "id": "klippen_wachterin",
    "name": "WÄCHTERIN DER KLIPPEN",
    "tile": [
      215,
      660
    ],
    "paved": false
  },
  {
    "id": "glaskamm_wachterin",
    "name": "WÄCHTERIN DES GLASKAMMS",
    "tile": [
      142,
      355
    ],
    "paved": true
  },
  {
    "id": "bluete_wachterin",
    "name": "WÄCHTERIN DER BLÜTE",
    "tile": [
      408,
      322
    ],
    "paved": false
  },
  {
    "id": "mauern_wachterin",
    "name": "WÄCHTERIN DER ALTEN MAUERN",
    "tile": [
      664,
      390
    ],
    "paved": false
  },
  {
    "id": "versunkene_wachterin",
    "name": "WÄCHTERIN DER VERSUNKENEN",
    "tile": [
      915,
      308
    ],
    "paved": false
  },
  {
    "id": "quarz_wachterin",
    "name": "WÄCHTERIN DER QUARZDÜNEN",
    "tile": [
      712,
      234
    ],
    "paved": false
  },
  {
    "id": "sonnen_wachterin",
    "name": "WÄCHTERIN DER SONNENÖDE",
    "tile": [
      908,
      80
    ],
    "paved": false
  },
  {
    "id": "hexen_wachterin",
    "name": "WÄCHTERIN DES HEXENWALDS",
    "tile": [
      760,
      830
    ],
    "paved": false
  }
];

export const VISTAS = [
  {
    "id": "nebel_seeblick",
    "name": "KANZEL AM SPIEGELSEE",
    "sub": "AUSBLICK ÜBER DEN NEBELWALD",
    "tile": [
      852,
      492
    ]
  },
  {
    "id": "nebel_suedhang",
    "name": "MOOSBANK ÜBER DEM AUENTAL",
    "sub": "AUSBLICK ÜBER DEN SÜDSTROM",
    "tile": [
      644,
      762
    ]
  },
  {
    "id": "nebel_hochgrat",
    "name": "GLIMMRAST-HOCHKANZEL",
    "sub": "AUSBLICK ÜBER DAS HEIMATTAL",
    "tile": [
      694,
      618
    ]
  },
  {
    "id": "glas_ostkante",
    "name": "WÄCHTERSTUFE AM GROSSEN SEE",
    "sub": "AUSBLICK ÜBER DIE GLASKLIPPEN",
    "tile": [
      318,
      416
    ]
  },
  {
    "id": "glas_stromblick",
    "name": "WINDSTEIN AM WESTBECKEN",
    "sub": "AUSBLICK ZWISCHEN KLIPPE UND LICHTUNG",
    "tile": [
      384,
      684
    ]
  },
  {
    "id": "glas_nordsporn",
    "name": "STILLER GRAT ÜBER DEM NORDTAL",
    "sub": "AUSBLICK ÜBER DIE HOHEN KLIPPEN",
    "tile": [
      242,
      258
    ]
  },
  {
    "id": "ruinen_seewarte",
    "name": "ALTE SEEWARTE",
    "sub": "AUSBLICK AUF DAS MITTELMEER DER SEEN",
    "tile": [
      494,
      504
    ]
  },
  {
    "id": "ruinen_mauerblick",
    "name": "RASTSTEIN DER ALTEN MAUERN",
    "sub": "AUSBLICK ÜBER DIE VERSUNKENEN RUINEN",
    "tile": [
      650,
      406
    ]
  },
  {
    "id": "lichtung_hochstein",
    "name": "SONNENKUPPE DER LICHTUNG",
    "sub": "AUSBLICK ÜBER DIE OFFENEN WIESEN",
    "tile": [
      486,
      628
    ]
  },
  {
    "id": "lichtung_suedwacht",
    "name": "WEITBLICK AM SÜDSAUM",
    "sub": "AUSBLICK ÜBER DIE SÜDWIESEN",
    "tile": [
      278,
      868
    ]
  },
  {
    "id": "lichtung_altstamm",
    "name": "RUHESTAMM AM WIESENHANG",
    "sub": "AUSBLICK ÜBER DIE GROSSE SENKE",
    "tile": [
      490,
      764
    ]
  },
  {
    "id": "blueten_suedgrat",
    "name": "SCHWELLENFELS DES LEERENBLÜHENS",
    "sub": "AUSBLICK ÜBER DEN NORDPASS",
    "tile": [
      432,
      352
    ]
  },
  {
    "id": "blueten_hochplatte",
    "name": "HOCHPLATTE DER STILLEN WEITE",
    "sub": "AUSBLICK ÜBER DAS NÖRDLICHE HOCHLAND",
    "tile": [
      358,
      234
    ]
  },
  {
    "id": "blueten_westkliff",
    "name": "ABENDKANTE AM WELTRAND",
    "sub": "AUSBLICK NACH WESTEN",
    "tile": [
      274,
      142
    ]
  }
];

export const WONDERS = [
  {
    "id": "wonder_bell_pond",
    "name": "DER GLOCKENTEICH",
    "sub": "DIE VERSUNKENEN TRITTSTEINE SIND ERWACHT",
    "tile": [
      795,
      525
    ],
    "tier": "legendary"
  },
  {
    "id": "wonder_sleeping_guardians",
    "name": "KREIS DER SCHLAFENDEN WÄCHTER",
    "sub": "EIN URALTES SEGENS-ECHO DURCHSTRÖMT DAS PLATEAU",
    "tile": [
      256,
      205
    ],
    "tier": "legendary"
  },
  {
    "id": "wonder_flower_amphitheater",
    "name": "DAS BLUMEN-AMPHITHEATER",
    "sub": "DIE IRRLICHTER TANZEN AUF DER STILLEN BÜHNE",
    "tile": [
      421,
      667
    ],
    "tier": "rare"
  }
];

export const WATCHTOWERS = [
  {
    "id": "order_tower_nordgrat",
    "name": "WACHTURM DES ROTEN ORDENS",
    "sub": "HALB EINGESTÜRZTE KLIPPENBASTION",
    "tile": [
      368,
      188
    ],
    "speaker": "STEININSCHRIFT",
    "text": "»DRITTE NORDWACHT DES ROTEN ORDENS. SOLANGE EIN FUNKE IN DER LATERNE GLÜHT, SCHWEIGT DER ABGRUND UNTER DEM GRAT.«",
    "thought": "Die Zinnen sind längst gebrochen… aber in der Nische glimmt noch immer ein warmer Splitter. Valdric hat einst genau solche Türme gehütet."
  },
  {
    "id": "order_tower_seeblick",
    "name": "RUINENTURM DER SEEWACHT",
    "sub": "VERLASSENER AUSSENPOSTEN ÜBER DEN ALTEN MAUERN",
    "tile": [
      548,
      404
    ],
    "speaker": "ORDENSCHRONIK",
    "text": "»HERBST DES LETZTEN JAHRES: WIR ZIEHEN DIE BESATZUNG NACH SÜDEN AB. WER NACH UNS KOMMT, MÖGE DAS SIEGEL IN EHREN HALTEN.«",
    "thought": "Weinroter Mörtel zwischen bemoostem Stein. Sie sind nicht im Kampf gefallen – sie mussten ihre Posten vor der wachsenden Leere räumen."
  },
  {
    "id": "order_tower_westklamm",
    "name": "BASTION AM GLASKAMM",
    "sub": "ORDENSWACHT ÜBER DEM WESTLICHEN PASS",
    "tile": [
      254,
      446
    ],
    "speaker": "WACHSTEIN",
    "text": "»KEIN SCHATTEN ÜBERSCHREITE DIE FURT UNBEMERKT. KOMMANDANT V. HAT DIE SPÄHER INS TAL GESANDT.«",
    "thought": "Kommandant V.… Das muss Valdric gewesen sein, lange bevor Glimmrast gegründet wurde."
  }
];

export const BORDER_STONES = [];

export const WATERMILLS = [
  {
    "id": "mill_auental",
    "name": "ALTE AUENMÜHLE",
    "sub": "DAS MÜHLRAD DREHT SICH WIEDER IM STROM",
    "tile": [
      789,
      725
    ]
  },
  {
    "id": "mill_nebelbach",
    "name": "MOOSMÜHLE AM NEBELBACH",
    "sub": "DIE ALTE MÜHLENKAMMER IST GEÖFFNET",
    "tile": [
      857,
      561
    ]
  },
  {
    "id": "mill_suedfurt",
    "name": "VERLASSENE KORNMÜHLE",
    "sub": "WASSERRAD VOM TREIBHOLZ BEFREIT",
    "tile": [
      643,
      803
    ]
  }
];

export const PIERS = [{"id": "pier_glassee", "tile": [347, 467]}, {"id": "pier_mittelsee_ost", "tile": [629, 487]}, {"id": "pier_ruinensee", "tile": [775, 439]}, {"id": "pier_mittelsee_west", "tile": [527, 487]}, {"id": "pier_spiegelsee", "tile": [829, 507]}, {"id": "pier_klippenteich", "tile": [255, 475]}];

export const ARENAS = [
  {
    "id": "singing_basin",
    "name": "DAS SINGENDE BECKEN",
    "sub": "ARENA VON AURELITH · HERZ DES SONNENQUARZES",
    "tile": [
      626,
      69
    ],
    "boss": "Aurelith",
    "superName": "Sonnenquarz-Öde"
  },
  {
    "id": "raven_hollow",
    "name": "DER SCHIEFERKESSEL AM RABENBAUM",
    "sub": "ARENA VON MORWENNA · DIE SPIEGELHEXE",
    "tile": [
      814,
      920
    ],
    "boss": "Morwenna",
    "superName": "Hexenwald"
  }
];

export const HALLGRAT = {
  "name": "HALLGRAT",
  "title": "DIE STILLE STADT",
  "about": "Steinstadt auf dem westlichen Glaskamm — Forum der Wächterin, Terrassen der Arbeit, Geisterzeile und Kristallmine.",
  "tile": [
    142,
    355
  ],
  "bounds": [
    94,
    290,
    246,
    412
  ],
  "districts": [
    {
      "id": "fuss",
      "name": "DER FUSS",
      "level": 0,
      "color": "#c9a26b",
      "about": "Unterstadt vor dem Osttor: Steinmarkt, Gasthaus, Karrenhof und die Stallungen, Felder am Nordostrand, die Geisterzeile."
    },
    {
      "id": "staffeln",
      "name": "DIE STAFFELN",
      "level": 2,
      "color": "#d98f6a",
      "about": "Die Terrassen der Arbeit (Ebene 1 und 2): Torgasse, Werkgasse, Steinmetzhof, Glasschleiferei, Lampenmacherei, darunter die Brunnenmulde mit Gärten und dem Zisterneneingang."
    },
    {
      "id": "stille",
      "name": "DIE STILLE",
      "level": 3,
      "color": "#8fd9d0",
      "about": "Die Oberstadt auf dem Gipfel: das Forum um die Wächterin, Hüterhalle, Rothalle, Steinarchiv, Vogtshaus, Mondturm."
    },
    {
      "id": "rand",
      "name": "DIE RANDPROMENADE",
      "level": 1,
      "color": "#a99be0",
      "about": "Die Westmauer auf dem äußeren Ring (Ebene 1), der Wehrgang, die Leerenfenster und darunter der Küstenstreifen bis zur Leere; im Süden der Gedenkgarten."
    },
    {
      "id": "verloren",
      "name": "DAS VERLORENE VIERTEL",
      "level": 1,
      "color": "#e05c9a",
      "about": "Die Nordwestflanke hinter der Schwarzen Mauer (versiegelt; Stufe 8 des Konzepts)."
    },
    {
      "id": "glasbruch",
      "name": "DER GLASBRUCH",
      "level": 1,
      "color": "#7fb2ff",
      "about": "Der Nordhang mit der Mulde, in der der alte Kristallbruch in den Berg führt (Mine, Stufe 7)."
    }
  ]
};
