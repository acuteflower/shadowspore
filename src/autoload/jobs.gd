extends Node
## Zentrales Multithreading: Rechenarbeit läuft auf Worker-Threads (WorkerThreadPool), das Ergebnis kommt auf dem
## Main-Thread an. Regeln für Arbeit in einem Job:
##  - nur lesen, was nach dem Start unveränderlich ist (DataRegistry, Relief, Karten, Noise), oder eigene Daten benutzen;
##  - Nodes dürfen erzeugt und gebaut, aber NICHT in den Baum gehängt werden (add_child an Baum-Nodes nur auf dem Main-Thread);
##  - nichts am Szenenbaum, an Signalen von Baum-Nodes oder an geteilten Dictionaries ändern.
## Benutzung:
##   var job: Jobs.Job = Jobs.run(func() -> Variant: return teuer(), func(result: Variant) -> void: ..., Jobs.Prio.NORMAL)
##   Jobs.wait(job)      # Ergebnis jetzt sofort (läuft der Job noch nicht, rechnet der Main-Thread ihn selbst)
##   Jobs.cancel(job)    # on_done kommt nie; on_discard bekommt ein schon fertiges Ergebnis zum Aufräumen
## `Jobs.threaded = false` (oder `--no-threads`) lässt alles auf dem Main-Thread laufen, ein Job pro Frame; die Ergebnisse
## sind dieselben (Tests vergleichen beide Wege).

enum Prio { URGENT = 0, HIGH = 1, NORMAL = 2, LOW = 3 }
enum State { PENDING, RUNNING, FINISHED, CANCELLED, DELIVERED }

class Job extends RefCounted:
	var work: Callable
	var on_done: Callable
	var on_discard: Callable
	var prio: int = Prio.NORMAL
	var order: int = 0 ## FIFO inside one priority
	var state: int = State.PENDING
	var task_id: int = -1
	var result: Variant = null
	var cancel_requested: bool = false ## readable by the work itself (cooperative stop)
	var tag: Variant = null
	var started_usec: int = 0
	var work_usec: int = 0

	func is_finished() -> bool:
		return state == State.FINISHED or state == State.DELIVERED

## Ein Job pro Aufruf auf der Hauptseite; kann zur Laufzeit umgeschaltet werden (Einstellungen / Dev-Menü).
var threaded: bool = true
var max_running: int = 3 ## gleichzeitig laufende Jobs (Rest der Kerne bleibt für Render-/Main-Thread und Audio)

var _lock: Mutex = Mutex.new()
var _pending: Array[Job] = []
var _running: Array[Job] = []
var _finished: Array[Job] = []
var _counter: int = 0
var _closing: bool = false

var stats: Dictionary = {"submitted": 0, "completed": 0, "cancelled": 0, "inline": 0, "work_usec": 0, "peak_queue": 0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100 ## Ergebnisse kommen vor allen anderen _process-Aufrufen an
	var cores: int = OS.get_processor_count()
	max_running = clampi(cores / 3, 1, 6)
	if OS.get_cmdline_user_args().has("--no-threads") or OS.get_cmdline_args().has("--no-threads"):
		threaded = false
	if cores <= 1:
		threaded = false


func _process(_delta: float) -> void:
	_deliver()
	_pump()


func _exit_tree() -> void:
	shutdown()


## Reicht `work` ein (läuft auf einem Worker, sobald ein Platz frei ist). `on_done.call(result)` kommt auf dem Main-Thread.
func run(work: Callable, on_done: Callable = Callable(), prio: int = Prio.NORMAL, on_discard: Callable = Callable(), tag: Variant = null) -> Job:
	var job: Job = Job.new()
	job.work = work
	job.on_done = on_done
	job.on_discard = on_discard
	job.prio = prio
	job.tag = tag
	_lock.lock()
	_counter += 1
	job.order = _counter
	_enqueue(job)
	stats.submitted = int(stats.submitted) + 1
	stats.peak_queue = maxi(int(stats.peak_queue), _pending.size() + _running.size())
	_lock.unlock()
	_pump()
	return job


## Wie `run`, aber verteilt `count` Aufrufe von `body(i)` auf alle Kerne und kehrt erst zurück, wenn alle fertig sind (Main-Thread blockiert).
## Für kurze, unabhängige Rechenschritte, deren Ergebnis sofort gebraucht wird; `body` darf nur in eigene Slots schreiben (z.B. Array[i]).
func parallel_for(count: int, body: Callable, min_batch: int = 8) -> void:
	if count <= 0:
		return
	if not threaded or count < min_batch * 2:
		for i: int in count:
			body.call(i)
		return
	var tasks: int = WorkerThreadPool.add_group_task(body, count, -1, true, "Jobs.parallel_for")
	WorkerThreadPool.wait_for_group_task_completion(tasks)


## Wartet auf den Job und liefert sein Ergebnis. Ein Job, der noch nicht läuft, wird vom Main-Thread selbst gerechnet
## (kein Warten auf einen belegten Worker, kein Deadlock gegen den Render-Thread).
func wait(job: Job) -> Variant:
	if job == null:
		return null
	_lock.lock()
	if job.state == State.CANCELLED and job.task_id < 0:
		_lock.unlock()
		return null
	if job.state == State.PENDING:
		_pending.erase(job)
		job.state = State.RUNNING
		_lock.unlock()
		stats.inline = int(stats.inline) + 1
		_execute(job)
		_lock.lock()
		_finished.erase(job)
		_lock.unlock()
		_deliver_job(job)
		return job.result
	_lock.unlock()
	# (blockiert, bis der Worker fertig ist: Szenen/Skripte, die der Job braucht, vorher mit warm() auf dem Main-Thread laden)
	_deliver_job(job) ## liefert (der Worker ist fertig)
	_lock.lock()
	_finished.erase(job)
	_lock.unlock()
	return job.result


## Lädt Szenen und Skripte auf dem Main-Thread vor. Das ERSTE Laden einer Szene/eines Skripts in einem Worker kann gegen den
## Main-Thread blockieren (gemessen: Deadlock, sobald der Main-Thread auf den Job wartet); danach ist alles im Cache und
## `load()` / `instantiate()` im Worker sind sicher. Jeder Job, der Szenen erzeugt, braucht vorher ein `warm`.
func warm(paths: Array) -> void:
	for path: Variant in paths:
		var res: Resource = load(String(path))
		if res is PackedScene: ## (instanziieren übersetzt auch die Skripte der Kinder)
			var probe: Node = (res as PackedScene).instantiate()
			probe.free()


func wait_all(jobs: Array) -> void:
	for job: Variant in jobs:
		wait(job as Job)


## Bricht ab. Liefert true, wenn der Job schon angefangen hatte: dann bekommt `on_discard(result)` (result kann null sein) auf dem
## Main-Thread einmal die Chance, Reste aufzuräumen, sobald der Worker fertig ist. Liefert false, wenn der Job nie lief (oder
## schon geliefert war): der Aufrufer räumt selbst auf, `on_done` und `on_discard` kommen nie.
func cancel(job: Job) -> bool:
	if job == null:
		return false
	_lock.lock()
	job.cancel_requested = true
	match job.state:
		State.PENDING:
			_pending.erase(job)
			job.state = State.CANCELLED
			stats.cancelled = int(stats.cancelled) + 1
			_lock.unlock()
			return false
		State.FINISHED:
			_finished.erase(job)
			job.state = State.CANCELLED
			stats.cancelled = int(stats.cancelled) + 1
			_lock.unlock()
			_deliver_job(job)
			return true
		State.RUNNING:
			stats.cancelled = int(stats.cancelled) + 1
			_lock.unlock()
			return true ## (_execute sieht cancel_requested beim Abschluss)
		_:
			_lock.unlock()
			return false


## Blockiert, bis kein Job mehr läuft oder wartet (Szenenwechsel, Editor-Änderung, Beenden). Laufende Ergebnisse werden verworfen oder geliefert.
func drain(deliver: bool = true) -> void:
	while true:
		_lock.lock()
		var next: Job = null
		if not _pending.is_empty():
			next = _pending[0]
		elif not _running.is_empty():
			next = _running[0]
		_lock.unlock()
		if next == null:
			break
		if deliver:
			wait(next)
		else:
			cancel(next)
			wait(next)
	_deliver()


func shutdown() -> void:
	if _closing:
		return
	_closing = true
	drain(false)


func busy() -> bool:
	_lock.lock()
	var n: int = _pending.size() + _running.size() + _finished.size()
	_lock.unlock()
	return n > 0


func queued() -> int:
	_lock.lock()
	var n: int = _pending.size()
	_lock.unlock()
	return n


func running() -> int:
	_lock.lock()
	var n: int = _running.size()
	_lock.unlock()
	return n


# ------------------------------------------------------------------------------ intern

func _enqueue(job: Job) -> void: ## (Lock gehalten)
	var at: int = _pending.size()
	while at > 0 and (_pending[at - 1].prio > job.prio):
		at -= 1
	_pending.insert(at, job)


## Startet wartende Jobs, solange Platz ist.
func _pump() -> void:
	if _closing:
		return
	if not threaded:
		# Ohne Threads: ein Job pro Frame auf dem Main-Thread (gleiche Reihenfolge, gleiche Ergebnisse).
		_lock.lock()
		var job: Job = null if _pending.is_empty() else _pending.pop_front()
		if job != null:
			job.state = State.RUNNING
		_lock.unlock()
		if job != null:
			stats.inline = int(stats.inline) + 1
			_execute(job)
			_lock.lock()
			_finished.erase(job)
			_lock.unlock()
			_deliver_job(job)
		return
	while true:
		_lock.lock()
		if _pending.is_empty() or _running.size() >= max_running:
			_lock.unlock()
			return
		var job: Job = _pending.pop_front()
		job.state = State.RUNNING
		_running.append(job)
		job.task_id = WorkerThreadPool.add_task(_worker.bind(job), false, "Jobs")
		_lock.unlock()


func _worker(job: Job) -> void:
	_execute(job)


func _execute(job: Job) -> void:
	job.started_usec = Time.get_ticks_usec()
	var out: Variant = null
	if not job.cancel_requested:
		out = job.work.call()
	job.work_usec = Time.get_ticks_usec() - job.started_usec
	_lock.lock()
	job.result = out
	job.state = State.CANCELLED if job.cancel_requested else State.FINISHED
	_running.erase(job)
	_finished.append(job) ## (auch Abgebrochene: der Main-Thread räumt ihr Ergebnis auf)
	_lock.unlock()


## Liefert fertige Ergebnisse (Main-Thread).
func _deliver() -> void:
	while true:
		_lock.lock()
		var job: Job = null
		for candidate: Job in _finished:
			if candidate.task_id < 0 or WorkerThreadPool.is_task_completed(candidate.task_id):
				job = candidate
				break
		if job != null:
			_finished.erase(job)
		_lock.unlock()
		if job == null:
			break
		_deliver_job(job)


func _deliver_job(job: Job) -> void:
	if job.state == State.DELIVERED:
		return
	if job.task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(job.task_id) ## (schon fertig: gibt nur das Task-Handle frei)
		job.task_id = -1
	if job.state == State.CANCELLED:
		job.state = State.DELIVERED ## (erledigt: ein zweiter Aufruf räumt nicht noch einmal auf)
		_discard(job)
		return
	if job.state == State.DELIVERED:
		return
	job.state = State.DELIVERED
	stats.completed = int(stats.completed) + 1
	stats.work_usec = int(stats.work_usec) + job.work_usec
	if job.on_done.is_valid():
		job.on_done.call(job.result)


func _discard(job: Job) -> void:
	var result: Variant = job.result
	job.result = null
	if job.on_discard.is_valid():
		job.on_discard.call(result)
