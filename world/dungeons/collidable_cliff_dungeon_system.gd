extends PreciseCliffDungeonSystem # Retains exact A/B transition routing while adding deeply embedded collidable exterior portals and a stable height-mapped interior pocket.
class_name CollidableCliffDungeonSystem # Exposes the complete cliff-only paired-dungeon runtime with precise spawns, exterior collision, and stable height-field interior movement.

const DUNGEON_POCKET_ORIGIN: Vector3 = Vector3(0.0, -1024.0, 0.0) # Isolates interiors safely below the terrain's bounded low elevations while keeping physics coordinates far closer to origin than the previous twenty-kilometre pocket.
const INTERIOR_SAFE_SPAWN_DISTANCE: float = 1.85 # Places the player close to the centre of the endpoint cell so the capsule starts well clear of the boundary wall and portal plane.
const INTERIOR_SAFE_FLOOR_CLEARANCE: float = 0.12 # Gives the capsule a conservative initial gap above the sampled floor height before gravity settles it naturally.

func _enter_dungeon(pair_id: int, endpoint: DungeonPairDefinition.Endpoint) -> bool: # Generates the selected height-mapped dungeon in the stable below-world pocket and lands the player at the exact matching interior endpoint.
    if _active_dungeon != null: # Rejects nested entry while another deterministic interior is already active.
        return false # Leaves current world-space state untouched when a transition is already in progress.
    var pair: DungeonPairDefinition = _find_pair(pair_id) # Resolves the exact streamed pair represented by the exterior door the player interacted with.
    if pair == null: # Detects stale exterior interaction metadata that no longer maps to an active deterministic pair.
        return false # Refuses to guess a destination when authoritative pair metadata is unavailable.
    _active_pair = pair # Retains the exact pair so either interior endpoint can route back to its correct exterior counterpart later.
    var stable_dungeon: StableWallProceduralDungeonWorld = StableWallProceduralDungeonWorld.new() # Creates the deterministic paired-height-map interior with primitive wall collision instead of concave vertical triangles.
    _active_dungeon = stable_dungeon # Stores the stable wall subclass through the existing base dungeon ownership contract.
    _active_dungeon.name = "ActiveDungeon_%d_%d" % [pair.region_coordinate.x, pair.region_coordinate.y] # Gives the generated interior its stable region-coordinate diagnostic identity.
    _active_dungeon.position = DUNGEON_POCKET_ORIGIN # Places collision near enough to origin for reliable millimetre-scale CharacterBody recovery while remaining far below overworld terrain.
    _active_dungeon.build(pair.pair_id, pair.dungeon_seed, pair.region_coordinate) # Reconstructs topology, paired height maps, visible meshes, primitive walls, ceiling collision, doors, fixtures, and lighting from the immutable pair seed.
    add_child(_active_dungeon) # Installs the generated world so its exact physical interior-door transforms are authoritative before player placement.
    var arrival_door: DungeonDoor = _find_matching_interior_door(pair_id, endpoint) # Resolves only the interior door whose pair identity and A/B endpoint match the exterior interaction source.
    if arrival_door == null: # Detects any generated endpoint mismatch before altering overworld/player state.
        _active_dungeon.queue_free() # Releases the invalid generated world instead of placing the player at an assumed coordinate.
        _active_dungeon = null # Clears active interior ownership after rejecting the malformed transition.
        _active_pair = null # Clears pair state because entry did not complete.
        return false # Fails closed so endpoint correspondence can never silently drift.
    var arrival_position: Vector3 = stable_dungeon.get_height_mapped_spawn_position(endpoint, INTERIOR_SAFE_SPAWN_DISTANCE, INTERIOR_SAFE_FLOOR_CLEARANCE) # Moves inward from the exact corresponding door, then grounds the player to the authoritative floor height map at that actual landing coordinate.
    var arrival_yaw: float = DungeonSpawnResolver.get_yaw_facing_front(arrival_door) # Faces the player directly into traversable dungeon space using the same physical door transform.
    _set_overworld_active(false) # Suspends terrain streaming, decoration, exterior portals, and other overworld-only presentation before relocation.
    _player.initialize_environment(null) # Detaches terrain water queries while the player occupies the isolated interior pocket.
    _player.set_fly_mode_enabled(false) # Ensures ordinary CharacterBody collision and grounded motion are active for the dungeon landing.
    _player.velocity = Vector3.ZERO # Removes overworld momentum before placing the body onto generated interior collision.
    _camera.environment = _active_dungeon.get_environment() # Activates the brighter dungeon-specific environment directly on the first-person camera.
    _player.global_position = arrival_position # Moves the player to the exact corresponding interior A or B door at the correct sampled floor elevation.
    _player.rotation.y = arrival_yaw # Aligns movement orientation with the same door-relative direction used for spawn placement.
    return true # Reports successful deterministic entry into the stable height-mapped dungeon pocket.

func _create_exterior_door(pair_root: Node3D, pair: DungeonPairDefinition, endpoint: DungeonPairDefinition.Endpoint) -> void: # Creates one deeply embedded exterior doorway while preserving the existing deterministic pair routing contract.
    if pair_root == null or pair == null: # Rejects malformed stream requests before allocating procedural entrance geometry.
        return # Leaves invalid pair state untouched instead of constructing an unowned doorway.
    var door: EmbeddedExteriorDungeonDoor = EmbeddedExteriorDungeonDoor.new() # Allocates the exterior-only door specialization with deep masonry and coarse primitive collision.
    door.name = "DoorB" if endpoint == DungeonPairDefinition.Endpoint.B else "DoorA" # Preserves the existing compact endpoint identity under each streamed pair root.
    pair_root.add_child(door) # Parents the entrance before assigning its world-space transform so floating-origin ownership remains correct.
    door.configure(pair.pair_id, endpoint, true, pair.get_yaw(endpoint), pair.get_display_name(endpoint)) # Builds the procedural exterior using the exact deterministic pair metadata already consumed by transition routing.
    door.global_position = _terrain.world_to_local_position(pair.get_world_position(endpoint)) # Places the generated entrance at the exact terrain-backed endpoint after any accumulated floating-origin rebase.
