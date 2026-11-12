extends Node
## Port of Unity Assets/Scripts/Game/GameTypes.cs
## Battle royale data tables: weapons, consumables, building rules, rarity.

enum Stance { RIFLE, PISTOL, MELEE, UNARMED }
enum FireKind { HITSCAN, ROCKET, MELEE, GRENADE, CONSUME }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
enum AmmoType { NONE, LIGHT, MEDIUM, HEAVY, SHELLS, ROCKETS }
enum BuildMat { WOOD, BRICK, METAL }
enum PieceType { WALL, FLOOR, STAIRS, CONE }

const GRID := 4.0
const LEVEL := 4.0
const BUILD_COST := 10
const MAX_MATS := 999

const RARITY_COLORS := {
	0: Color(0.55, 0.57, 0.60),   # common
	1: Color(0.32, 0.70, 0.16),   # uncommon
	2: Color(0.16, 0.52, 0.93),   # rare
	3: Color(0.62, 0.27, 0.90),   # epic
	4: Color(0.93, 0.55, 0.15),   # legendary
}

## max hp / build-up seconds / materials per pickaxe hit
const MAX_HP := {0: 150.0, 1: 300.0, 2: 450.0}
const BUILD_TIME := {0: 2.5, 1: 4.5, 2: 6.5}
const PER_HIT := {0: 8, 1: 6, 2: 5}
const MAT_LABEL := {0: "WOOD", 1: "BRICK", 2: "METAL"}

const WEAPONS := [
	{   # assault rifle
		"id": "assault_rifle", "label": "Assault Rifle", "stance": Stance.RIFLE,
		"kind": FireKind.HITSCAN, "ammo": AmmoType.MEDIUM, "damage": 30.0,
		"head_mult": 1.5, "interval": 0.18, "auto": true, "pellets": 1, "mag": 30,
		"reload": 2.2, "spread_hip": 2.2, "spread_ads": 0.45, "bloom": 0.55,
		"bloom_max": 4.0, "range": 350.0, "falloff_start": 60.0, "ads_fov": 50.0,
		"scope": false, "recoil": 0.9, "speed": 0.0, "radius": 0.0, "bot_range": 35.0,
	},
	{   # pump shotgun
		"id": "shotgun", "label": "Pump Shotgun", "stance": Stance.RIFLE,
		"kind": FireKind.HITSCAN, "ammo": AmmoType.SHELLS, "damage": 11.0,
		"head_mult": 1.5, "interval": 0.95, "auto": false, "pellets": 10, "mag": 5,
		"reload": 3.2, "spread_hip": 5.5, "spread_ads": 4.5, "bloom": 0.0,
		"bloom_max": 0.0, "range": 60.0, "falloff_start": 8.0, "ads_fov": 60.0,
		"scope": false, "recoil": 4.0, "speed": 0.0, "radius": 0.0, "bot_range": 8.0,
	},
	{   # sniper
		"id": "sniper_rifle", "label": "Sniper Rifle", "stance": Stance.RIFLE,
		"kind": FireKind.HITSCAN, "ammo": AmmoType.HEAVY, "damage": 105.0,
		"head_mult": 2.5, "interval": 1.5, "auto": false, "pellets": 1, "mag": 1,
		"reload": 2.6, "spread_hip": 6.0, "spread_ads": 0.0, "bloom": 0.0,
		"bloom_max": 0.0, "range": 900.0, "falloff_start": 1000.0, "ads_fov": 14.0,
		"scope": true, "recoil": 5.0, "speed": 0.0, "radius": 0.0, "bot_range": 80.0,
	},
	{   # rocket launcher
		"id": "rocket_launcher", "label": "Rocket Launcher", "stance": Stance.RIFLE,
		"kind": FireKind.ROCKET, "ammo": AmmoType.ROCKETS, "damage": 110.0,
		"head_mult": 1.0, "interval": 1.2, "auto": false, "pellets": 1, "mag": 1,
		"reload": 2.8, "spread_hip": 0.6, "spread_ads": 0.15, "bloom": 0.0,
		"bloom_max": 0.0, "range": 400.0, "falloff_start": 1000.0, "ads_fov": 55.0,
		"scope": false, "recoil": 5.0, "speed": 45.0, "radius": 5.0, "bot_range": 30.0,
	},
	{   # pistol
		"id": "pistol", "label": "Pistol", "stance": Stance.PISTOL,
		"kind": FireKind.HITSCAN, "ammo": AmmoType.LIGHT, "damage": 24.0,
		"head_mult": 2.0, "interval": 0.2, "auto": false, "pellets": 1, "mag": 16,
		"reload": 1.5, "spread_hip": 1.6, "spread_ads": 0.5, "bloom": 0.8,
		"bloom_max": 4.0, "range": 150.0, "falloff_start": 30.0, "ads_fov": 58.0,
		"scope": false, "recoil": 1.4, "speed": 0.0, "radius": 0.0, "bot_range": 20.0,
	},
	{   # pickaxe
		"id": "pickaxe", "label": "Pickaxe", "stance": Stance.MELEE,
		"kind": FireKind.MELEE, "ammo": AmmoType.NONE, "damage": 20.0,
		"head_mult": 1.0, "interval": 0.8, "auto": true, "pellets": 1, "mag": 0,
		"reload": 0.0, "spread_hip": 0.0, "spread_ads": 0.0, "bloom": 0.0,
		"bloom_max": 0.0, "range": 2.4, "falloff_start": 1000.0, "ads_fov": 70.0,
		"scope": false, "recoil": 0.0, "speed": 0.0, "radius": 0.0, "bot_range": 1.5,
	},
	{   # grenade
		"id": "grenade", "label": "Grenade", "stance": Stance.UNARMED,
		"kind": FireKind.GRENADE, "ammo": AmmoType.NONE, "damage": 100.0,
		"head_mult": 1.0, "interval": 1.1, "auto": false, "pellets": 1, "mag": 0,
		"reload": 0.0, "spread_hip": 0.0, "spread_ads": 0.0, "bloom": 0.0,
		"bloom_max": 0.0, "range": 0.0, "falloff_start": 1000.0, "ads_fov": 70.0,
		"scope": false, "recoil": 0.0, "speed": 17.0, "radius": 4.5, "bot_range": 18.0,
	},
]

const CONSUMABLES := [
	{"id": "bandage", "label": "Bandages", "rarity": Rarity.COMMON,
	 "use_time": 3.5, "heal": 15.0, "heal_cap": 75.0, "shield": 0.0,
	 "shield_cap": 0.0, "max_stack": 15, "action": ""},
	{"id": "med_kit", "label": "Med Kit", "rarity": Rarity.UNCOMMON,
	 "use_time": 8.0, "heal": 100.0, "heal_cap": 100.0, "shield": 0.0,
	 "shield_cap": 0.0, "max_stack": 3, "action": ""},
	{"id": "shield_potion", "label": "Shield Potion", "rarity": Rarity.RARE,
	 "use_time": 4.0, "heal": 0.0, "heal_cap": 0.0, "shield": 50.0,
	 "shield_cap": 100.0, "max_stack": 3, "action": ""},
	{"id": "launch_pad", "label": "Launch Pad", "rarity": Rarity.RARE,
	 "use_time": 0.6, "heal": 0.0, "heal_cap": 0.0, "shield": 0.0,
	 "shield_cap": 0.0, "max_stack": 1, "action": "pad"},
	{"id": "rift_to_go", "label": "Rift-To-Go", "rarity": Rarity.EPIC,
	 "use_time": 0.5, "heal": 0.0, "heal_cap": 0.0, "shield": 0.0,
	 "shield_cap": 0.0, "max_stack": 1, "action": "rift"},
]

const AMMO_LABEL := {
	AmmoType.NONE: "", AmmoType.LIGHT: "Light Bullets",
	AmmoType.MEDIUM: "Medium Bullets", AmmoType.HEAVY: "Heavy Bullets",
	AmmoType.SHELLS: "Shells", AmmoType.ROCKETS: "Rockets",
}

const AMMO_PILE := {
	AmmoType.LIGHT: 36, AmmoType.MEDIUM: 30, AmmoType.HEAVY: 6,
	AmmoType.SHELLS: 10, AmmoType.ROCKETS: 3,
}

const AMMO_CAP := {
	AmmoType.LIGHT: 500, AmmoType.MEDIUM: 500, AmmoType.HEAVY: 60,
	AmmoType.SHELLS: 60, AmmoType.ROCKETS: 30,
}

func weapon(id: String) -> Dictionary:
	for w in WEAPONS:
		if w["id"] == id:
			return w
	return WEAPONS[5]  # pickaxe fallback

func consumable(id: String) -> Dictionary:
	for c in CONSUMABLES:
		if c["id"] == id:
			return c
	return CONSUMABLES[0]

func damage_mult(r: int) -> float:
	return 1.0 + 0.06 * r

func reload_mult(r: int) -> float:
	return 1.0 - 0.05 * r

## floor loot rarity: mostly common..rare; chests roll one tier better
func roll_rarity(chest: bool) -> int:
	var r := randf()
	var tier := 0
	if r < 0.38: tier = 0
	elif r < 0.68: tier = 1
	elif r < 0.88: tier = 2
	elif r < 0.97: tier = 3
	else: tier = 4
	if chest: tier = min(4, tier + 1)
	return tier

func new_item_weapon(def: Dictionary, rarity: int) -> Dictionary:
	return {
		"weapon": def, "consumable": null, "rarity": rarity,
		"mag": 3 if def["kind"] == FireKind.GRENADE else def["mag"],
	}

func new_item_consumable(def: Dictionary, count: int) -> Dictionary:
	return {"weapon": null, "consumable": def, "rarity": def["rarity"], "mag": count}

func item_is_weapon(it: Dictionary) -> bool:
	return it["weapon"] != null

func item_label(it: Dictionary) -> String:
	return it["weapon"]["label"] if it["weapon"] != null else it["consumable"]["label"]

func item_stacks(it: Dictionary) -> bool:
	if it["consumable"] != null:
		return true
	return it["weapon"] != null and it["weapon"]["kind"] == FireKind.GRENADE

func item_max_stack(it: Dictionary) -> int:
	if it["consumable"] != null:
		return it["consumable"]["max_stack"]
	if it["weapon"] != null and it["weapon"]["kind"] == FireKind.GRENADE:
		return 6
	return 1

func piece_prefab(t: int, m: int) -> String:
	var base := "wall_"
	if t == PieceType.FLOOR: base = "floor_"
	elif t == PieceType.STAIRS: base = "ramp_"
	elif t == PieceType.CONE: base = "pyramid_roof_"
	return base + ["wood", "brick", "metal"][m]
