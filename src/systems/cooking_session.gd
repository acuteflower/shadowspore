class_name CookingSession
extends RefCounted
## Two considered decisions surround one timing gesture. No inventory mutation.
var recipe: Dictionary
var stage: int = 0
var started: bool = false
var dry_batch: bool = false
var history: Array[Dictionary] = []
var timing_grade: String = ""
var traits: Dictionary = {"roast":0,"heat":0,"bitter":0,"broth":0,"fruit":0,"body":0,"clear":0,"late":0,"fresh":0}

func _init(recipe_id: String = "glimmer_pot",dry: bool = false) -> void:
	recipe = DataRegistry.get_entry("cooking",recipe_id)
	dry_batch = dry

func begin() -> void:
	if (recipe.get("moments",[]) as Array).is_empty(): return
	started = true

func done() -> bool:
	return started and stage >= (recipe.get("moments",[]) as Array).size()

func moment_name() -> String:
	if done(): return "DEIN GERICHT"
	var moments: Array = recipe.get("moments", []) as Array
	if stage >= moments.size(): return ""
	return String((moments[stage] as Dictionary).get("name", ""))

func choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not started or done(): return out
	var moments: Array = recipe.get("moments", []) as Array
	if stage >= moments.size(): return out
	for raw: Dictionary in (moments[stage] as Dictionary).get("choices", []) as Array:
		var choice: Dictionary = raw.duplicate(true)
		if stage==1 and int(traits.roast)==0 and choice.id=="deglaze":
			choice.name = "BEEREN FÜR DEN SCHLUSS AUFHEBEN"
			choice.hint = "EIN WENIG WASSER, SPÄTER FRISCHE"
			choice.feedback = "Die helle Brühe bleibt auf dem Feuer. Die Beeren warten noch auf dem Brett."
		out.append(choice)
	return out

func choose(index: int) -> Dictionary:
	if stage==1: return {}
	return _apply_choice(index)

func resolve_timing(position: float) -> Dictionary:
	if not started or stage!=1: return {}
	timing_grade = CookingTiming.grade(position)
	var action: Dictionary = _apply_choice(0 if timing_grade=="rough" else 1)
	if timing_grade=="perfect":
		traits.bitter = maxi(0,int(traits.bitter)-1)
		traits.body = int(traits.body)+1
		action.name = "BEEREN: GOLDENE MITTE"
		action.feedback = "Genau im richtigen Moment! Die Beeren gleiten weich hinein und mildern den kräftigen Ansatz."
	elif timing_grade=="good":
		action.name = "BEEREN: SANFT GELANDET"
		action.feedback = "Die Beeren landen sanft in der Brühe. Ihr Schimmer zieht zwischen die Pilzstücke."
	else:
		if int(traits.heat)<2: traits.bitter = int(traits.bitter)+1
		action.name = "BEEREN: ETWAS ZU HASTIG"
		action.feedback = "Ein kleiner Spritzer! Die Beeren platzen auf. Ein sanfter Abschluss kann die herbe Note noch abrunden."
	history[-1].name = action.name
	history[-1].id = "timing_"+timing_grade
	return action

func _apply_choice(index: int) -> Dictionary:
	var available: Array[Dictionary] = choices()
	if index<0 or index>=available.size(): return {}
	var choice: Dictionary = available[index]
	for key: String in choice.effects as Dictionary:
		traits[key] = maxi(0,int(traits.get(key,0))+int(choice.effects[key]))
	if stage==0 and dry_batch and choice.id=="bold": traits.bitter = int(traits.bitter)+1
	if stage==1 and choice.id=="crush" and int(traits.heat)>=2: traits.bitter = int(traits.bitter)+1
	if stage==2 and int(traits.late)>0:
		traits.fruit = 1
		if choice.id=="rest": traits.clear = 1
	history.append({"id":choice.id,"name":choice.name,"moment":moment_name()})
	stage += 1
	return choice

func observation(mode: String = "look") -> String:
	if not started: return "Auf dem Brett liegen zwei Glimmerbeeren und eine Glimmkappe. Drei Handgriffe geben dem Gericht seinen Charakter."
	if done(): return String(result().description)
	if mode=="smell":
		if stage==0: return "Der Pilz riecht konzentriert und trocken. Die Beeren bringen einen kühlen, süssen Duft." if dry_batch else "Ein feuchter Waldduft steigt aus der Pilzschale. Die Beeren riechen frisch und leicht süss."
		if stage==1:
			if int(traits.bitter)>=2: return "Beissender Rauch überdeckt den Pilz. Ein sanfter Beereneinwurf und weniger Hitze könnten helfen."
			if int(traits.roast)>=2: return "Es duftet nussig und warm. Eine herbe Note verrät den dunklen Ansatz am Boden."
			return "Milder Pilzduft und warmer Dampf. Die Fruchtnote fehlt noch."
		if int(traits.late)>0: return "Der Duft ist wieder weich und erdig. Die frischen Beeren warten noch auf ihren Moment."
		if int(traits.bitter)>=2: return "Süsser Beerenduft, darunter eine scharfe Röstnote. Sanfte Hitze könnte das Gericht noch abrunden."
		return "Frucht und Waldboden duften zusammen. Der Beerenduft ist kräftig." if int(traits.fruit)>=2 else "Ein feiner Beerenduft liegt über der hellen Pilzbrühe."
	if mode=="taste" and stage==1:
		if int(traits.bitter)>0: return "Der Pilz schmeckt kräftig, aber etwas herb. Behutsam zugegebene Beeren würden den Ansatz mildern."
		return "Mild und erdig. Die Pilzbasis ist weich, ihr fehlt noch die süsse Fruchtnote."
	if stage==0:
		if mode=="taste": return "Erst garen, dann probieren. Der Duft der Zutaten verrät dir schon etwas."
		return "Die Kappe ist etwas trocken. Sie wird schnell braun. Die Beeren duften kühl und süss." if dry_batch else "Saftige Pilzstücke liegen bereit. Die Beeren schimmern kühl. Zuerst braucht der Pilz eine Basis."
	if stage==1:
		if int(traits.bitter)>=2: return "Der Duft ist scharf und rauchig. Am Boden sitzt ein sehr dunkler Ansatz. Triff den goldenen Moment, um die Beeren sanft zuzugeben."
		if int(traits.roast)>=2: return "Es riecht nussig und kräftig. Am Boden haftet ein dunkler Ansatz. Gib die zarten Beeren möglichst sanft hinein."
		if int(traits.roast)==0: return "Eine helle, erdige Brühe zieht durch. Die Pilzstücke sind weich. Jetzt fehlt noch die Frucht."
		return "Die Pilze glänzen goldbraun. Es duftet mild und erdig. Die Glimmerbeeren liegen noch bereit."
	if int(traits.late)>0:
		return "Der Ansatz hat sich gelöst. Die Brühe schmeckt milder. Mit den Beeren am Schluss bleibt ein frischer Schimmer."
	if int(traits.bitter)>=2:
		return "Viel Frucht, aber ein herber Nachgeschmack. Die Brühe braucht einen sanften Abschluss." if mode=="taste" else "Der Dampf ist schwer und dunkel. Fruchtsüsse und Röstaromen drängen sich nach vorn."
	if int(traits.fruit)>=2:
		return "Süsse und Pilzaroma sind deutlich zu schmecken. Sanfte Hitze könnte sie noch verbinden." if mode=="taste" else "Feine violette Fäden ziehen durch den Saft. Kleine Blasen sammeln sich am Rand."
	return "Einzelne Beeren platzen weich zwischen den Pilzen. Die Brühe schmeckt leicht und frisch." if mode=="taste" else "Ganze Beeren treiben in der klaren Brühe. Ihr Schimmer ist noch fein und hell."

func result() -> Dictionary:
	if not done(): return {}
	var variant: String
	var name: String
	var quality: String = "RUND GELUNGEN"
	var description: String
	if int(traits.bitter)>=2:
		variant="smoky"; name="RAUCHIGES WALDTÖPFCHEN"; quality="ETWAS HERB GERATEN"
		description="Die Frucht ist dicht, der Pilz kräftig. Zu viel Hitze hat eine herbe Spur hinterlassen. Nächstes Mal sanfter abschliessen."
	elif int(traits.roast)>=2 and (int(traits.late)>0 or timing_grade=="perfect"):
		variant="rescued"; name="SAMTIGES GLIMMERTÖPFCHEN"; quality="SCHÖN AUSGEGLICHEN"
		description="Der kräftige Ansatz gibt Tiefe. Im richtigen Moment zugegebene Beeren verbinden sich mit dem Pilz zu einem runden Geschmack."
	elif int(traits.fresh)>0:
		variant="fresh"; name="FRISCHES LICHTUNGSTÖPFCHEN"
		description="Feine Pilzaromen und kühle Beerensüsse. Der sanfte Abschluss bewahrt den frischen Schimmer."
	elif int(traits.fruit)>=2:
		variant="fruity"; name="FRUCHTIGES WALDRAGOUT"
		description="Zerdrückte Beeren verbinden sich mit der erdigen Basis. Ein dichtes, wohliges Gericht mit violettem Glanz."
	elif int(traits.roast)==0:
		variant="clear"; name="LEICHTE GLIMMERBRÜHE"
		description="Eine leichte Brühe mit weichen Pilzen und einzelnen süssen Beeren. Die Zutaten bleiben gut erkennbar."
	else:
		variant="warm"; name="WÄRMENDES PILZTÖPFCHEN"
		description="Milde Röstaromen, ein wenig Frucht und eine weiche Brühe. Ein ruhiger Begleiter für einen langen Waldweg."
	var notes: Array[String] = []
	for step: Dictionary in history: notes.append(String(step.name))
	return {"recipe":"glimmer_pot","variant":variant,"name":name,"quality":quality,"description":description,"notes":notes,"dry_batch":dry_batch,"timing_grade":timing_grade,"traits":traits.duplicate(true)}
