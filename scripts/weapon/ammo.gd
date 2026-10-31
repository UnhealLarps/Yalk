extends Node

var rep := Reporter.new("AmmoBox")

@export_range(0, 1000000, 1) var ammo_amount: int = 24

func interact_with_weapon(weapon: Node) -> bool:
	if NetworkManager.is_client():
		return false
	if weapon == null:
		return false
	if ammo_amount <= 0:
		return false

	var gun_component: Node = weapon.find_child("GunComponent", true, false)
	if gun_component == null:
		return false
	if not gun_component.has_method("add_reserve_ammo"):
		return false

	var transferred: int = (gun_component.add_reserve_ammo(ammo_amount))
	if transferred <= 0:
		return false
	ammo_amount -= transferred
	if ammo_amount <= 0:
		GC.destroy(get_parent())
		return true
	if gun_component.has_method("reload"):
		gun_component.reload()

	rep.info("Transferred %d ammo | Remaining: %d" % [transferred, ammo_amount])
	return true
