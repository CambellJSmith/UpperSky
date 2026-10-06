extends RefCounted
class_name AffectionState
# A directed affection score, used for the player and individual NPC relationships.
signal changed(previous: float, current: float)
const HATE: float = 0.0
const NEUTRAL: float = 100.0
const ADORATION: float = 200.0
const STARTING_SCORES = {"human":100.0,"orc":50.0,"zombie":0.0,"demon":0.0,"fish_man":0.0,"ghost":25.0,"wizard":100.0,"werewolf":0.0,"vampire":0.0,"knight":11.0}
var _score: float = NEUTRAL
var score: float:
    get: return _score
    set(value): set_score(value)

func _init(starting_score: float = NEUTRAL):
    if is_finite(starting_score): _score = clampf(starting_score,HATE,ADORATION)

static func starting_score(species: String) -> float:
    return STARTING_SCORES.get(species,NEUTRAL)

func get_score() -> float: return _score
func set_score(value: float):
    if not is_finite(value): return
    var next = clampf(value,HATE,ADORATION)
    if next == _score: return
    var previous = _score
    _score = next
    changed.emit(previous,_score)

func change_score(amount: float):
    if is_finite(amount): set_score(_score+amount)
