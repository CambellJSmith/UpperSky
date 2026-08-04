extends Node3D # Owns and initializes the active world and player composition.

const PLAYER_SPAWN_HORIZONTAL: Vector2 = Vector2(0.0, 0.0) # Defines the stable initial horizontal world position.
const PLAYER_SPAWN_CLEARANCE: float = 2.2 # Places the player safely above generated terrain before physics settles them.

@onready var _terrain: InfiniteTerrain = $World/Terrain # Stores the active infinite terrain controller.
@onready var _dynamic_entities: Node3D = $DynamicEntities # Owns active entities that participate in floating-origin rebasing.
@onready var _player: FirstPersonPlayer = $DynamicEntities/Player # Stores the active first-person player instance.

func _ready() -> void: # Places the player from terrain data and begins terrain streaming.
    var spawn_height: float = _terrain.get_height_at(PLAYER_SPAWN_HORIZONTAL) # Samples the authoritative terrain height at the chosen start.
    _player.global_position = Vector3(PLAYER_SPAWN_HORIZONTAL.x, spawn_height + PLAYER_SPAWN_CLEARANCE, PLAYER_SPAWN_HORIZONTAL.y) # Places the player above the generated surface.
    _terrain.initialize(_player, _dynamic_entities) # Builds spawn terrain and registers active entities for floating-origin rebasing.
