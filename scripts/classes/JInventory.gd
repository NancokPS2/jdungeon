extends Node

class_name JInventory

signal loaded
signal item_added(item_uuid: String, item_class: String)
signal item_removed(item_uuid: String)

signal gold_added(total: int, amount: int)
signal gold_removed(total: int, amount: int)

@export var size: int = 36
@export var player: JPlayerBody2D

var items: Array[JItem] = []
var gold: int = 1000


func _ready():
	if J.is_server():
		J.rpcs.item.inventory_item_used.connect(_on_inventory_item_used)
		J.rpcs.item.inventory_item_dropped.connect(_on_inventory_item_dropped)


func add_item(item: JItem) -> bool:
	if not J.is_server():
		return false

	if item.item_type == JItem.ITEM_TYPE.CURRENCY:
		add_gold(item.amount)
		return true

	item.collision_layer = 0

	if items.size() >= size:
		return false

	items.append(item)

	sync_add_item.rpc_id(player.peer_id, item.name, item.item_class, item.amount)

	return true


func remove_item(item_uuid: String):
	if not J.is_server():
		return false

	var item: JItem = get_item(item_uuid)
	if item != null:
		items.erase(item)
		sync_remove_item.rpc_id(player.peer_id, item_uuid)
		return item


func get_item(item_uuid: String) -> JItem:
	for item in items:
		if item.uuid == item_uuid:
			return item

	return null


func use_item(item_uuid: String):
	if not J.is_server():
		return false

	var item: JItem = get_item(item_uuid)
	if item and item.use(player):
		remove_item(item_uuid)
		return true

	return false


func add_gold(amount: int):
	if not J.is_server():
		return

	gold += amount
	sync_add_gold.rpc_id(player.peer_id, gold, amount)


func remove_gold(amount: int) -> bool:
	if not J.is_server():
		return false

	if amount <= gold:
		gold -= amount
		sync_remove_gold.rpc_id(player.peer_id, gold, amount)
		return true

	return false


func to_json() -> Dictionary:
	var output: Dictionary = {"gold": gold, "items": []}

	for item in items:
		output["items"].append(item.to_json())

	return output


func from_json(data: Dictionary) -> bool:
	if "gold" in data:
		player.inventory.gold = data["gold"]

		gold_added.emit(data["gold"], 0)
	else:
		J.logger.warn('Failed to load inventory from data, missing "gold" key')
		return false

	if "items" in data:
		items = []
	else:
		J.logger.warn('Failed to load inventory from data, missing "gold" key')
		return false

	for item_data in data["items"]:
		if not "uuid" in item_data:
			J.logger.warn('Failed to load inventory from data, missing "uuid" key')
			return false

		if not "item_class" in item_data:
			J.logger.warn('Failed to load inventory from data, missing "item_class" key')
			return false

		if not "amount" in item_data:
			J.logger.warn('Failed to load inventory from data, missing "amount" key')
			return false

		var item: JItem = J.item_scenes[item_data["item_class"]].instantiate()
		item.from_json(item_data)
		item.collision_layer = 0

		items.append(item)

	loaded.emit()

	return true


func _on_inventory_item_used(id: int, item_uuid: String):
	if player.peer_id != id:
		return

	use_item(item_uuid)


func _on_inventory_item_dropped(id: int, item_uuid: String):
	if player.peer_id != id:
		return

	var item = get_item(item_uuid)
	if not item:
		return

	remove_item(item_uuid)

	var random_x = randi_range(-J.DROP_RANGE, J.DROP_RANGE)
	var random_y = randi_range(-J.DROP_RANGE, J.DROP_RANGE)
	item.position = player.position + Vector2(random_x, random_y)
	item.collision_layer = J.PHYSICS_LAYER_ITEMS

	J.world.items.add_child(item)
	item.start_expire_timer()


@rpc("call_remote", "any_peer", "reliable") func sync_inventory():
	if not J.is_server():
		return

	var id = multiplayer.get_remote_sender_id()

	# Only allow logged in players
	if not J.server.is_user_logged_in(id):
		return

	if id == player.peer_id:
		sync_response.rpc_id(id, to_json())


@rpc("call_remote", "authority", "reliable") func sync_response(inventory: Dictionary):
	from_json(inventory)


@rpc("call_remote", "authority", "reliable")
func sync_add_item(item_uuid: String, item_class: String, amount: int):
	var item = J.item_scenes[item_class].instantiate()
	item.uuid = item_uuid
	item.item_class = item_class
	item.amount = amount
	item.collision_layer = 0

	items.append(item)

	item_added.emit(item_uuid, item_class)


@rpc("call_remote", "authority", "reliable") func sync_remove_item(item_uuid: String):
	var item: JItem = get_item(item_uuid)
	if item != null:
		items.erase(item)

		item_removed.emit(item_uuid)


@rpc("call_remote", "authority", "reliable") func sync_add_gold(total: int, amount: int):
	gold = total
	gold_added.emit(total, amount)


@rpc("call_remote", "authority", "reliable") func sync_remove_gold(total: int, amount: int):
	gold = total
	gold_removed.emit(total, amount)
