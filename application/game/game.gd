extends Node3D # Owns and initializes the active world and player composition.

const PLAYER_SPAWN_CHUNK_COORDINATE: Vector2i = Vector2i.ZERO # Identifies the terrain chunk used for the initial player start.
const PLAYER_SPAWN_CLEARANCE: float = 2.2 # Places the player safely above generated terrain before physics settles them.

@onready var _terrain: InfiniteTerrain = $World/Terrain # Stores the active infinite terrain controller.
@onready var _dynamic_entities: Node3D = $DynamicEntities # Owns active entities that participate in floating-origin rebasing.
@onready var _player: FirstPersonPlayer = $DynamicEntities/Player # Stores the active first-person player instance.

func _ready() -> void: # Prepares collision-backed terrain before allowing the player to enter physics simulation.
    _player.set_physics_process(false) # Prevents gravity and movement from advancing while the spawn terrain is constructed.
    var spawn_horizontal: Vector2 = _get_player_spawn_horizontal() # Calculates a spawn point safely inside the selected terrain chunk.
    var spawn_height: float = _terrain.get_height_at(spawn_horizontal) # Samples the authoritative terrain height at the chosen start.
    _player.global_position = Vector3(spawn_horizontal.x, spawn_height + PLAYER_SPAWN_CLEARANCE, spawn_horizontal.y) # Places the player above the generated surface.
    _player.velocity = Vector3.ZERO # Clears inherited movement before the player begins interacting with terrain.
    _terrain.initialize(_player, _dynamic_entities) # Builds spawn terrain and registers active entities for floating-origin rebasing.
    _player.set_physics_process(true) # Enables player movement only after collision exists beneath the spawn point.

func _get_player_spawn_horizontal() -> Vector2: # Converts the selected spawn chunk into a point centred away from exposed chunk edges.
    var chunk_origin: Vector2 = Vector2(PLAYER_SPAWN_CHUNK_COORDINATE) * TerrainConfiguration.CHUNK_SIZE # Calculates the selected chunk's horizontal world origin.
    var chunk_centre_offset: Vector2 = Vector2.ONE * TerrainConfiguration.CHUNK_SIZE * 0.5 # Calculates the offset from the chunk origin to its centre.
    return chunk_origin + chunk_centre_offset # Returns a stable spawn point fully surrounded by the chunk surface.
