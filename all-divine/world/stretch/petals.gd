class_name Petals
extends RefCounted
## The petals he carries and the pile he left (what `SaveData` holds of them, with the rules): foes give petals when they fall; a death
## leaves what he carries where he fell, as one pile; he takes it back by coming near it; a second death before he does wilts it for
## good (or, with a clock set in the tuning, time does). It holds no nodes and no clock of its own: the run draws the pile and ticks it
## with the play frames that pass.

## Petals were gained (a fallen foe's).
signal gained(amount: int)
## A pile was left at `at`.
signal dropped(amount: int, at: Vector3)
## The pile was taken back.
signal taken(amount: int)
## The pile wilted for good.
signal wilted(amount: int)

var data: SaveData
var tuning: PetalTuning


func _init(save_data: SaveData, petal_tuning: PetalTuning) -> void:
	data = save_data
	tuning = petal_tuning if petal_tuning != null else PetalTuning.new()


## The petals he carries.
func carried() -> int:
	return data.petals


## Gains `amount` petals; an amount below 1 is nothing.
func gain(amount: int) -> void:
	if amount < 1:
		return
	data.petals += amount
	gained.emit(amount)


## He fell at `at`: an old pile wilts first; then the share of what he carries that the tuning leaves becomes the pile at `at` (if that
## is anything). The death is counted in every case.
func fall_at(at: Vector3) -> void:
	_wilt()
	var left := floori(float(data.petals) * tuning.drop_share)
	if left > 0:
		data.petals -= left
		data.pile = {x = at.x, y = at.y, z = at.z, amount = left, frames = 0}
		dropped.emit(left, at)
	data.deaths += 1


## Where the pile lies (a Vector3), or null.
func pile_at() -> Variant:
	if data.pile.is_empty():
		return null
	return Vector3(data.pile.x, data.pile.y, data.pile.z)


## How many petals lie in the pile.
func pile_amount() -> int:
	return 0 if data.pile.is_empty() else int(data.pile.amount)


## The pile joins what he carries; the amount (0 with no pile).
func take_back() -> int:
	var amount := pile_amount()
	if amount <= 0:
		return 0
	data.petals += amount
	data.pile = {}
	taken.emit(amount)
	return amount


## `frames` play frames pass: the pile ages, and with a clock set it wilts when its time is up.
func tick(frames := 1) -> void:
	if data.pile.is_empty():
		return
	data.pile.frames = int(data.pile.frames) + frames
	if tuning.wilt_seconds > 0.0 and int(data.pile.frames) >= roundi(tuning.wilt_seconds * Engine.physics_ticks_per_second):
		_wilt()


func _wilt() -> void:
	var amount := pile_amount()
	if data.pile.is_empty():
		return
	data.pile = {}
	wilted.emit(amount)
