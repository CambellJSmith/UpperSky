extends CharacterBody3D
class_name Villager

const MODEL_PATHS = ["res://actors/npcs/villagers/models/humble_pilgrim.glb","res://actors/npcs/villagers/models/village_weaver.glb","res://actors/npcs/villagers/models/orc.glb","res://actors/npcs/villagers/models/demon.glb","res://actors/npcs/villagers/models/ghost.glb","res://actors/npcs/villagers/models/zombie.glb","res://actors/npcs/villagers/models/fish_man.glb"]
const LIBRARY_PATHS = ["res://actors/npcs/villagers/animations/humble_pilgrim.res","res://actors/npcs/villagers/animations/village_weaver.res","res://actors/npcs/villagers/animations/orc.res","res://actors/npcs/villagers/animations/demon.res","res://actors/npcs/villagers/animations/ghost.res","res://actors/npcs/villagers/animations/zombie.res","res://actors/npcs/villagers/animations/fish_man.res"]
const CLIPS = {"idle":"Idle_Loop","walk":"Walk_Loop","run":"Jog_Fwd_Loop","punch":"Punch_Jab","kick":"Kick","weapon_slash":"WeaponSlash","weapon_chop":"WeaponChop","weapon_stab":"WeaponStab"}
var _loot_record: Dictionary = {}
const SPECIES = ["human","human","orc","demon","ghost","zombie","fish_man"]
var affection: AffectionState = AffectionState.new()
var equipment: NpcEquipment
var combat: NpcCombat
var _was_in_combat: bool = false
var _combat_path: Array[Vector2] = []
var _combat_path_timer: float = 0.0
var health: DamageableHealth
var _corpse_collider: CollisionShape3D
var world_position: Vector3
var route: Array[Vector2] = []
var role: String = "traveller"
var model_index: int = 0
var _dungeon: ProceduralDungeonWorld
var _terrain: InfiniteTerrain
var _sampler: SettlementSampler
var _rng = RandomNumberGenerator.new()
var _visual: Node3D
var _ragdoll: RigidBody3D
var _animation: AnimationPlayer
var _rig: Skeleton3D
var _feet: Array[int] = []
var _state: String = "idle"
var _wait: float = 2.0
var _waypoint: int = 0
var _blocked: float = 0.0
var _action_remaining: float = 0.0
var _advance_after_wait: bool = true
var _travel_direction: int = 1
var _route_sampler: VillagerPopulationSampler

func configure(terrain: InfiniteTerrain, definition: Dictionary) -> void:
    _loot_record = LootSession.get_record("npc:%s:%d:%d"%[definition.role,definition.model,definition.seed],definition.seed,true)
    _terrain = terrain
    _sampler = SettlementSampler.for_terrain(terrain)
    _route_sampler = VillagerPopulationSampler.new(terrain)
    model_index = definition.model
    affection = LootSession.get_affection(_loot_record,SPECIES[model_index])
    role = definition.role
    route.assign(definition.route)
    _rng.seed = definition.seed
    _waypoint = int(definition.get("start",0))%route.size()
    var point = route[_waypoint]
    world_position = Vector3(point.x,_ground_height(point)+.04,point.y)
    if _loot_record.health.is_dead(): world_position = _loot_record.get("position",world_position)
    position = terrain.world_to_local_position(world_position)
    _wait = _rng.randf_range(1,6)

func configure_cave(dungeon: ProceduralDungeonWorld, definition: Dictionary):
    _dungeon = dungeon
    model_index = definition.model
    role = "cave"
    route.assign(definition.route)
    _rng.seed = definition.seed
    _loot_record = LootSession.get_record("cave:%s:%s:%d:%d"%[dungeon._region_coordinate,dungeon._pair_id,model_index,definition.seed],definition.seed,true)
    affection = LootSession.get_affection(_loot_record,SPECIES[model_index])
    world_position = Vector3(route[0].x,_ground_height(route[0])+.04,route[0].y)
    if _loot_record.health.is_dead(): world_position = _loot_record.get("position",world_position)
    position = world_position

func _to_local(point: Vector3) -> Vector3:
    return _terrain.world_to_local_position(point) if _dungeon == null else _dungeon.to_global(point)
func _to_world(point: Vector3) -> Vector3:
    return _terrain.local_to_world_position(point) if _dungeon == null else _dungeon.to_local(point)
func _ground_height(point: Vector2) -> float:
    if _dungeon is ReadableProceduralDungeonWorld:
        return _dungeon._height_field.sample_floor(point.x,point.y,DungeonGeometryBuilder.CELL_SIZE)
    return 0.0 if _dungeon != null else _sampler.ground_height(point)

func _ready() -> void:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__ready()
        return
    var _profile_token = RuntimeProfiler.begin("npcs.instantiate")
    _profile__ready()
    RuntimeProfiler.end(_profile_token)

func _profile__ready() -> void:
    add_to_group("npc")
    health = DamageableHealth.new()
    health.name = "Health"
    health.bind_state(_loot_record.health)
    health.died.connect(_on_death)
    health.health_changed.connect(_on_health_changed)
    add_child(health)
    combat = NpcCombat.new()
    combat.name = "Combat"
    add_child(combat)
    combat.configure(self,affection,_loot_record.health)
    collision_layer = 4
    collision_mask = 1|4
    floor_snap_length = .4
    floor_max_angle = deg_to_rad(42)
    var collider = CollisionShape3D.new()
    _corpse_collider = collider
    var shape = CapsuleShape3D.new()
    shape.radius = .24
    shape.height = 1.65
    collider.shape = shape
    collider.position.y = .825
    add_child(collider)
    _visual = load(MODEL_PATHS[model_index]).instantiate()
    _visual.name = "Visual"
    add_child(_visual)
    _animation = _visual.find_child("AnimationPlayer",true,false)
    if _animation == null:
        _animation = AnimationPlayer.new()
        _animation.name = "AnimationPlayer"
        _visual.add_child(_animation)
    _rig = _visual.find_children("*","Skeleton3D",true,false)[0]
    _animation.add_animation_library("Quaternius",load(LIBRARY_PATHS[model_index]))
    _animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
    _animation.playback_default_blend_time = .18
    var mapper = preload("res://actors/npcs/villagers/authoring/rig_map.gd")
    for semantic in ["LeftFoot","RightFoot","LeftToeBase","RightToeBase"]:
        var bone = mapper.find_target_bone(_rig,semantic)
        if bone >= 0: _feet.append(bone)
    _prepare_mesh(_visual)
    _play("idle")
    _animation.advance(0)
    _ground_feet()
    equipment = NpcEquipment.new()
    equipment.name = "Equipment"
    add_child(equipment)
    equipment.configure(self,_rig,_loot_record.inventory)
    if _loot_record.health.is_dead(): _show_corpse()

func _process(delta: float) -> void:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__process(delta)
        return
    var _profile_token = RuntimeProfiler.begin("npcs.animation")
    _profile__process(delta)
    RuntimeProfiler.end(_profile_token)

func _profile__process(delta: float) -> void:
    equipment.sync_inventory()
    if _loot_record.health.is_dead():
        equipment.update_pose()
        return
    _animation.advance(delta)
    _ground_feet()
    equipment.update_pose()

func _ground_feet() -> void:
    var lowest: float = INF
    for bone in _feet:
        lowest = minf(lowest,(_rig.transform*_rig.get_bone_global_pose(bone)).origin.y)
    if is_finite(lowest): _visual.position.y = .04-lowest

func _physics_process(delta: float) -> void:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__physics_process(delta)
        return
    var _profile_token = RuntimeProfiler.begin("npcs.physics")
    _profile__physics_process(delta)
    RuntimeProfiler.end(_profile_token)

func _profile__physics_process(delta: float) -> void:
    if _loot_record.health.is_dead(): return
    if (_terrain == null and _dungeon == null) or route.size() < 2: return
    # Absolute coordinates stay authoritative through floating-origin shifts.
    global_position = _to_local(world_position)
    var fighting = combat.tick(delta)
    if _was_in_combat and not fighting:
        _action_remaining = 0
        _wait = 1
        _play("idle")
        _combat_path.clear()
    _was_in_combat = fighting
    if fighting:
        _fight_movement(delta)
    elif _action_remaining > 0:
        _action_remaining -= delta
        velocity.x = 0
        velocity.z = 0
        if _action_remaining <= 0:
            _play("idle")
            _wait = _rng.randf_range(1,3)
            _advance_after_wait = false
    elif _wait > 0:
        _wait -= delta
        velocity.x = 0
        velocity.z = 0
        _play("idle")
        if _wait <= 0:
            if _advance_after_wait: _waypoint = posmod(_waypoint+_travel_direction,route.size())
            _advance_after_wait = true
            _state = "run" if role == "traveller" and _rng.randf() < .30 else "walk"
    else:
        var point = Vector2(world_position.x,world_position.z)
        var target = route[_waypoint]
        var direction = (target-point).normalized()
        var speed: float = 3.0 if _state == "run" else 1.2
        var next = point+direction*speed*delta
        if point.distance_to(target) < .65:
            _wait = _rng.randf_range(2,8) if role != "traveller" else _rng.randf_range(.3,2)
        elif not _walkable(next):
            _wait = 1.5
            _advance_after_wait = false
            velocity.x = 0
            velocity.z = 0
            _travel_direction *= -1
            _waypoint = posmod(_waypoint+_travel_direction,route.size())
        else:
            velocity.x = direction.x*speed
            velocity.z = direction.y*speed
            rotation.y = lerp_angle(rotation.y,atan2(direction.x,direction.y),minf(1,delta*6))
            _play(_state)

    velocity.y = 0.0 if is_on_floor() else maxf(velocity.y-24*delta,-20)
    var before = global_position
    move_and_slide()
    var actual = _to_world(global_position)
    var point = Vector2(actual.x,actual.z)
    var ground = _ground_height(point)
    # Sampled ground also supports routes at the edge of the collision stream.
    if actual.y < ground-.10 or actual.y > ground+1.0:
        actual.y = ground+.04
        velocity.y = 0
    world_position = actual
    global_position = _to_local(world_position)
    if Vector2(velocity.x,velocity.z).length() > .1 and global_position.distance_to(before) < delta*.12:
        _blocked += delta
        if _blocked > 1.3:
            _wait = 2
            _advance_after_wait = false
            _travel_direction *= -1
            _waypoint = posmod(_waypoint+_travel_direction,route.size())
            _blocked = 0
    else: _blocked = 0

func _walkable(point: Vector2) -> bool:
    if _dungeon != null:
        var cell = Vector2i(floori(point.x/DungeonGeometryBuilder.CELL_SIZE+_dungeon._layout.width*.5),floori(point.y/DungeonGeometryBuilder.CELL_SIZE+_dungeon._layout.height*.5))
        return _dungeon._layout.is_walkable(cell) and absf(_ground_height(point)-world_position.y) < .55
    if _terrain.has_water_at(point) or BiomeProfile.is_lava(point) or _route_sampler.is_obstructed(point): return false
    var height = _ground_height(point)
    return absf(height-world_position.y) < .55

func perform_action(action: String) -> bool:
    if _loot_record.health.is_dead(): return false
    if _action_remaining > 0: return false
    var weapon = get_equipped_weapon()
    if weapon != null:
        if action != equipment.get_attack_action(): return false
    elif action not in ["punch","kick"]: return false
    _play(action)
    _action_remaining = _animation.get_animation("Quaternius/"+CLIPS[action]).length
    return true

func _play(state: String) -> void:
    var name = "Quaternius/"+String(CLIPS[state])
    if _animation.current_animation != name: _animation.play(name,.18)

func set_active(active: bool) -> void:
    if not active and combat != null: combat.cancel()
    set_physics_process(active)
    set_process(active)
    collision_layer = 4 if active else 0
    collision_mask = 1|4 if active else 0

func _prepare_mesh(node: Node) -> void:
    if node is MeshInstance3D: node.custom_aabb = AABB(Vector3(-2,-1,-2),Vector3(4,4,4))
    for child in node.get_children(): _prepare_mesh(child)

func get_health_component() -> DamageableHealth: return health
func receive_equipment_hit(hit: EquipmentHit):
    if hit == null or health == null: return
    var applied: float = health.apply_damage(hit.damage)
    if applied > 0.0:
        affection.change_score(-applied)
func _on_death():
    _loot_record.position = world_position
    var player = get_tree().get_first_node_in_group("player")
    if player != null:
        var vitals = player.get_node_or_null("PlayerVitals")
        if vitals != null: vitals.add_experience(25.0)
    _show_corpse()
func _on_health_changed():
    if health.is_dead() or _visual == null or is_zero_approx(_visual.rotation.z): return
    _visual.rotation = Vector3.ZERO
    var shape = CapsuleShape3D.new()
    shape.radius = .24
    shape.height = 1.65
    _corpse_collider.set_deferred("shape",shape)
    _corpse_collider.set_deferred("position",Vector3(0,.825,0))
    _play("idle")
    _animation.advance(0)
    _ground_feet()

func _show_corpse():
    velocity = Vector3.ZERO
    _animation.stop()
    # Preserve the last position and let the complete imported skeleton tumble
    # as one physics body instead of snapping into a fixed death animation.
    _ragdoll = RigidBody3D.new()
    _ragdoll.set_script(load("res://actors/combat/ragdoll_corpse.gd"))
    _ragdoll.name = "RagdollCorpse"
    _ragdoll.collision_layer = 4
    _ragdoll.collision_mask = 1 | 4
    _ragdoll.set_meta("loot_target", self)
    _ragdoll.global_transform = global_transform
    get_parent().add_child(_ragdoll)
    remove_child(_visual)
    _ragdoll.add_child(_visual)
    _visual.position = Vector3.ZERO
    _visual.rotation = Vector3.ZERO
    var collider := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.radius = .30
    shape.height = 1.7
    collider.shape = shape
    collider.position.y = .82
    _ragdoll.add_child(collider)
    _corpse_collider.set_deferred("disabled", true)
    _ragdoll.apply_central_impulse(Vector3(_rng.randf_range(-.8,.8), .8, _rng.randf_range(-.8,.8)))
    _ragdoll.apply_torque_impulse(Vector3(_rng.randf_range(-1.2,1.2), _rng.randf_range(-.7,.7), _rng.randf_range(-1.2,1.2)))

func get_loot_inventory() -> LootStorage:
    return _loot_record.inventory if _loot_record.health.is_dead() else null
func get_loot_title() -> String:
    return ["Pilgrim","Weaver","Orc","Demon","Ghost","Zombie","Fish-man"][model_index]+"'s belongings"

func get_affection() -> float: return affection.get_score()
func set_affection(value: float): affection.set_score(value)
func change_affection(amount: float): affection.change_score(amount)

func is_in_combat() -> bool: return combat != null and combat.active

func _fight_movement(delta: float):
    _action_remaining = maxf(0,_action_remaining-delta)
    velocity.x = 0
    velocity.z = 0
    var player_point = _to_world(combat.target.global_position)
    var point = Vector2(world_position.x,world_position.z)
    var target_point = Vector2(player_point.x,player_point.z)
    var facing = (target_point-point).normalized()
    rotation.y = lerp_angle(rotation.y,atan2(facing.x,facing.y),minf(1,delta*8))
    if combat.attacking or _action_remaining > 0: return
    if global_position.distance_to(combat.target.global_position) <= combat.get_attack_reach()*.85:
        _play("idle")
        return
    var direction = _combat_chase_direction(target_point,delta)
    if direction.is_zero_approx():
        _play("idle")
        return
    velocity.x = direction.x*3.0
    velocity.z = direction.y*3.0
    _play("run")

func _combat_chase_direction(target: Vector2, delta: float) -> Vector2:
    var point = Vector2(world_position.x,world_position.z)
    if _dungeon != null:
        _combat_path_timer -= delta
        if _combat_path_timer <= 0:
            _combat_path_timer = .5
            _combat_path = _cave_chase_path(point,target)
        while not _combat_path.is_empty() and point.distance_to(_combat_path[0]) < .5:
            _combat_path.pop_front()
        if not _combat_path.is_empty(): target = _combat_path[0]
    var direct = (target-point).normalized()
    # Small dry-ground detours avoid shorelines, slopes and house footprints.
    for turn in [0.0,.65,-.65,1.3,-1.3]:
        var direction = direct.rotated(turn)
        if _walkable(point+direction*maxf(.6,3*delta)): return direction
    return Vector2.ZERO

func _cave_chase_path(start: Vector2, goal: Vector2) -> Array[Vector2]:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        return _profile__cave_chase_path(start, goal)
    var _profile_token = RuntimeProfiler.begin("npcs.cave_path")
    var _profile_result = _profile__cave_chase_path(start, goal)
    RuntimeProfiler.end(_profile_token)
    return _profile_result

func _profile__cave_chase_path(start: Vector2, goal: Vector2) -> Array[Vector2]:
    var result: Array[Vector2] = []
    var layout = _dungeon._layout
    var scale = DungeonGeometryBuilder.CELL_SIZE
    var offset = Vector2(layout.width,layout.height)*.5
    var first = Vector2i((start/scale+offset).floor())
    var last = Vector2i((goal/scale+offset).floor())
    if first == last or not layout.is_walkable(last): return result
    var queue: Array[Vector2i] = [first]
    var parents: Dictionary = {first:first}
    var cursor = 0
    while cursor < queue.size() and cursor < 512 and not parents.has(last):
        var cell = queue[cursor]
        cursor += 1
        for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
            var next = cell+step
            if layout.is_walkable(next) and not parents.has(next):
                parents[next] = cell
                queue.append(next)
    if not parents.has(last): return result
    var cell = last
    while cell != first:
        result.push_front((Vector2(cell)+Vector2(.5,.5)-offset)*scale)
        cell = parents[cell]
    result.append(goal)
    return result

func get_inventory() -> LootStorage: return _loot_record.inventory
func get_equipped_weapon() -> EquipmentDefinition:
    if equipment == null: return null
    equipment.sync_inventory()
    return equipment.weapon
func get_weapon_attack_action() -> String: return equipment.get_attack_action()
