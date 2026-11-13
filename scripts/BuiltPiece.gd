extends StaticBody3D
## A placed build piece: takes damage, can be harvested with the pickaxe.

func take_damage(amount: float, source, _point: Vector3, _dir: Vector3, _w) -> void:
	var hp: float = get_meta("hp", 100.0) - amount
	set_meta("hp", hp)
	if hp <= 0.0:
		queue_free()

func harvest(who) -> void:
	var mat: int = get_meta("mat", 0)
	var per: int = GameTypes.PER_HIT[mat]
	who.add_mats(mat, per)
	take_damage(float(per * 5), who, global_position, Vector3.ZERO, null)
