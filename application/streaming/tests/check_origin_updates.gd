extends SceneTree # Check event-driven origin updates without generating scenery.

class FlatTerrain extends InfiniteTerrain: # Supply a loaded terrain facade for streamer updates.
    func get_loaded_chunk_count() -> int: return 1 # Let stationary streamers execute their ordinary paths.

class StaticSettlements extends SettlementStreamer: # Isolate static-position ownership from procedural generation.
    func _ready() -> void: _terrain.origin_shifted.connect(_update_origin_positions) # Retain production rebase handling.

class StaticPaths extends PathStreamer: # Isolate loaded path roots from route generation.
    func _ready() -> void: _terrain.origin_shifted.connect(_update_origin_positions) # Retain production rebase handling.

class StaticCamps extends CampStreamer: # Isolate loaded camps from procedural placement.
    func _ready() -> void: _terrain.origin_shifted.connect(_update_origin_positions) # Retain production rebase handling.

class DormantVillager extends Villager: # Check rebasing of a suspended actor independently of rig assets.
    func _ready() -> void: # Subscribe to origin events while keeping actor updates disabled.
        _terrain.origin_shifted.connect(_synchronize_world_position) # Retain production actor transform ownership.
        set_process(false) # Suspend per-frame actor work.
        set_physics_process(false) # Suspend movement work.

func _initialize() -> void: run.call_deferred() # Wait until fixture nodes can enter the tree.

func run() -> void: # Verify stationary positions and real origin-shift handling.
    var game: Node3D = Node3D.new() # Own the isolated game hierarchy.
    var world: Node3D = Node3D.new() # Own terrain and static streamers.
    world.name = "World" # Match production relative paths.
    game.add_child(world) # Attach the world hierarchy.
    var terrain: FlatTerrain = FlatTerrain.new() # Supply real coordinate conversions and rebasing.
    terrain.name = "Terrain" # Match streamer terrain paths.
    world.add_child(terrain) # Attach the terrain facade.
    var entities: Node3D = Node3D.new() # Own floating-origin participants.
    entities.name = "DynamicEntities" # Match production player paths.
    game.add_child(entities) # Attach the dynamic hierarchy.
    var player: FirstPersonPlayer = load("res://actors/player/first_person_player.tscn").instantiate() # Supply production player contracts.
    player.name = "Player" # Match streamer player paths.
    entities.add_child(player) # Attach the rebase subject.
    var settlements: StaticSettlements = StaticSettlements.new() # Supply static settlement ownership.
    settlements.name = "Settlements" # Match the production hierarchy.
    world.add_child(settlements) # Attach the settlement streamer.
    var paths: StaticPaths = StaticPaths.new() # Supply static path ownership.
    world.add_child(paths) # Attach the path streamer.
    var camps: StaticCamps = StaticCamps.new() # Supply static camp ownership.
    camps._terrain = terrain # Provide terrain without procedural initialization.
    camps._player = player # Provide the player proximity source.
    game.add_child(camps) # Attach the camp streamer.
    root.add_child(game) # Initialize the complete fixture hierarchy.
    terrain.set_process(false) # Disable ordinary terrain generation.
    terrain.set_physics_process(false) # Keep rebasing under test control.
    terrain._player = player # Supply the real rebase subject.
    terrain._rebase_root = entities # Supply dynamic origin participants.
    player.set_fly_mode_enabled(true) # Avoid requiring generated collision.
    settlements.set_process(false) # Keep streamer calls under test control.
    paths.set_process(false) # Keep streamer calls under test control.
    camps.set_process(false) # Keep streamer calls under test control.
    settlements._elapsed = -100.0 # Suppress procedural refresh during position checks.
    paths._centre = Vector2i.ZERO # Retain the stationary route neighbourhood.
    var home: Node3D = Node3D.new() # Supply a retained house root.
    home.set_meta("world_position", Vector3(100.0, 0.0, 100.0)) # Assign authoritative static coordinates.
    settlements.add_child(home) # Attach the retained house.
    settlements._homes[Vector2i.ZERO] = home # Register the root with production origin handling.
    var path: MeshInstance3D = MeshInstance3D.new() # Supply a retained path root.
    paths.add_child(path) # Attach the retained path.
    paths._chunks[Vector2i.ZERO] = path # Register the root with production origin handling.
    var camp: Node3D = Node3D.new() # Supply a retained camp root.
    camp.set_meta("world_position", Vector3(200.0, 0.0, 200.0)) # Assign authoritative camp coordinates.
    camps.add_child(camp) # Attach the retained camp.
    camps._cells[Vector2i.ZERO] = camp # Register the root with production origin handling.
    var npc: DormantVillager = DormantVillager.new() # Supply an inactive overworld actor.
    npc._terrain = terrain # Bind the actor's coordinate service.
    npc.world_position = Vector3(150.0, 0.04, 150.0) # Assign authoritative actor coordinates.
    world.add_child(npc) # Subscribe the actor to origin shifts.
    terrain.origin_shifted.emit() # Initialize retained roots from their authoritative coordinates.
    home.position += Vector3.ONE # Mark the root to detect a repeated position assignment.
    path.position += Vector3.ONE # Mark the path to detect a repeated position assignment.
    camp.position += Vector3.ONE # Mark the camp to detect a repeated position assignment.
    for step: int in range(20): # Exercise stationary streamer frames.
        settlements._profile__process(0.0) # Run the production settlement update.
        paths._profile__process(0.0) # Run the production path update.
        camps._profile__process(0.0) # Run the production camp update.
    assert(home.position == Vector3(101.0, 1.0, 101.0) and path.position == Vector3.ONE and camp.position == Vector3(201.0, 1.0, 201.0), "Stationary streamer rewrote static transforms") # Detect recurring transform work.
    player.global_position = Vector3(40000.0, 5.0, -40000.0) # Trigger an actual floating-origin shift.
    var player_world: Vector3 = terrain.local_to_world_position(player.global_position) # Preserve player identity across the shift.
    terrain._rebase_world_if_needed() # Exercise production signal ordering and coordinate conversion.
    assert(terrain.local_to_world_position(player.global_position).is_equal_approx(player_world), "Rebase changed player world position") # Preserve absolute player coordinates.
    assert(home.position.is_equal_approx(terrain.world_to_local_position(home.get_meta("world_position"))) and camp.position.is_equal_approx(terrain.world_to_local_position(camp.get_meta("world_position"))), "Static roots missed origin shift") # Reposition scenery only on the event.
    assert(path.position.is_equal_approx(terrain.world_to_local_position(Vector3.ZERO)), "Path missed origin shift") # Preserve retained route placement.
    assert(npc.global_position.is_equal_approx(terrain.world_to_local_position(npc.world_position)) and not npc.is_physics_processing(), "Inactive actor missed origin shift") # Rebase dormant actors without enabling their simulation.
    game.queue_free() # Release the fixture hierarchy.
    await process_frame # Complete teardown.
    print("PASS stationary static roots, real floating origin, player coordinates and inactive NPC rebasing") # Report regression coverage.
    quit() # Finish the regression process.
