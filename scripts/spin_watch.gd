class_name SpinWatch
extends RefCounted
## SPEC 110: pays for the QUALITY of a hit, Destruction Derby's way. After a hard hit the victim is
## watched for WINDOW seconds; how far it was turned decides what the hit was worth -- a half spin, a
## full spin, a pirouette -- and the attacker is paid in coins. Doubled when the victim was the leader
## (Destruction Derby's leader tax). The thresholds sit well above what a car turns on its own through
## a corner in that time, so a clean overtake pays nothing and a real spin pays.
##
## Pure: no scene tree, no autoloads. The caller owns the list and the payout.

const WINDOW := 0.8
## [radians turned, coins]: 115, 205 and 345 degrees.
const TIERS := [[6.0, 10], [3.6, 4], [2.0, 2]]

var car: Car
var attacker: Variant          # whatever the caller wants back: a row, a car, an index
var leader: bool = false
var acc: float = 0.0
var t: float = 0.0
var _last: float = 0.0


func _init(victim: Car, who: Variant, was_leader: bool = false) -> void:
	car = victim
	attacker = who
	leader = was_leader
	_last = victim.heading


## Advances the watch. -1 while it is still watching; otherwise the coins the hit earned (0 for none).
func tick(delta: float) -> int:
	if not is_instance_valid(car):
		return 0
	var h := car.heading
	acc += absf(wrapf(h - _last, -PI, PI))
	_last = h
	t += delta
	if t < WINDOW and not car.is_wrecked():
		return -1
	return coins_for(acc) * (2 if leader else 1)


## The coins a turn of `angle` radians is worth.
static func coins_for(angle: float) -> int:
	for tier in TIERS:
		if angle >= float(tier[0]):
			return int(tier[1])
	return 0


## The tier's name, for the word over the car.
static func word_for(angle: float) -> String:
	if angle >= float(TIERS[0][0]):
		return "PIROUETTE"
	if angle >= float(TIERS[1][0]):
		return "FULL SPIN"
	if angle >= float(TIERS[2][0]):
		return "SPIN"
	return ""
