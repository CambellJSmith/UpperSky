extends CharacterBody3D
class_name Villager

const MODEL_PATHS = ["res://actors/npcs/villagers/models/humble_pilgrim.glb","res://actors/npcs/villagers/models/village_weaver.glb","res://actors/npcs/villagers/models/orc.glb","res://actors/npcs/villagers/models/demon.glb","res://actors/npcs/villagers/models/ghost.glb","res://actors/npcs/villagers/models/zombie.glb","res://actors/npcs/villagers/models/fish_man.glb","res://actors/npcs/villagers/models/wizard.glb","res://actors/npcs/villagers/models/werewolf.glb","res://actors/npcs/villagers/models/knight.glb","res://actors/npcs/villagers/models/vampire.glb","res://actors/npcs/villagers/models/king.glb","res://actors/npcs/villagers/models/shadow_person.glb"]
const LIBRARY_PATHS = ["res://actors/npcs/villagers/animations/humble_pilgrim.res","res://actors/npcs/villagers/animations/village_weaver.res","res://actors/npcs/villagers/animations/orc.res","res://actors/npcs/villagers/animations/demon.res","res://actors/npcs/villagers/animations/ghost.res","res://actors/npcs/villagers/animations/zombie.res","res://actors/npcs/villagers/animations/fish_man.res","res://actors/npcs/villagers/animations/wizard.res","res://actors/npcs/villagers/animations/werewolf.res","res://actors/npcs/villagers/animations/knight.res","res://actors/npcs/villagers/animations/vampire.res","res://actors/npcs/villagers/animations/king.res","res://actors/npcs/villagers/animations/shadow_person.res"]
const CLIPS = {"idle":"Idle_Loop","walk":"Walk_Loop","run":"Jog_Fwd_Loop","punch":"Punch_Jab","kick":"Kick","weapon_slash":"WeaponSlash","weapon_chop":"WeaponChop","weapon_stab":"WeaponStab"}
var _loot_record: Dictionary = {}
const SPECIES = ["human","human","orc","demon","ghost","zombie","fish_man","wizard","werewolf","knight","vampire","human","shadow_person"]
var affection: AffectionState = AffectionState.new()
var _damage_source: Node3D
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
var _peasant_model: int = 0
var _werewolf_carrier := false
var _vampire_carrier := false
var _night_model: int = 8
const WEREWOLF_MODEL := 8
const VAMPIRE_MODEL := 10
var _dungeon: ProceduralDungeonWorld
var _space: Node3D
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
var follow_leader: WeakRef
var ferry_route: FerryCrossing
var ferry_riding: FerryCrossing
var follow_gap := 4.5
var encounter_kind := ""
var _travel_trail: Array[Vector2] = []
var _route_sampler: VillagerPopulationSampler
var journey: Dictionary = {}
var _visit_remaining := 0.0
var _update_cadence: NpcUpdateCadence = NpcUpdateCadence.new() # Own animation and patrol timing without changing streaming ownership.
var _update_player: Node3D # Cache the active player for distance sampling.

func configure(terrain: InfiniteTerrain, definition: Dictionary) -> void:
    _loot_record = LootSession.get_record("npc:%s:%d:%d"%[definition.role,definition.model,definition.seed],definition.seed,true)
    _terrain = terrain
    _sampler = SettlementSampler.for_terrain(terrain)
    _route_sampler = VillagerPopulationSampler.new(terrain)
    model_index = definition.model
    _peasant_model = model_index
    _werewolf_carrier = definition.role == "traveller" and model_index in [0,1] and werewolf_seed(definition.seed)
    _vampire_carrier = definition.role == "traveller" and model_index in [0,1] and vampire_seed(definition.seed)
    _night_model = VAMPIRE_MODEL if _vampire_carrier else WEREWOLF_MODEL
    affection = LootSession.get_affection(_loot_record,SPECIES[model_index])
    role = definition.role
    route.assign(definition.route)
    journey = definition.get("journey",{})
    _travel_direction = int(definition.get("travel_direction",1))
    _rng.seed = definition.seed
    _waypoint = int(definition.get("start",0))%route.size()
    var point: Vector2 = route[_waypoint].lerp(route[(_waypoint+1)%route.size()],float(definition.get("start_fraction",0)))
    follow_gap = float(definition.get("follow_gap",4.5))
    encounter_kind = definition.get("encounter","")
    _travel_trail = [point]
    world_position = Vector3(point.x,_ground_height(point)+.04,point.y)
    if _loot_record.health.is_dead(): world_position = _loot_record.get("position",world_position)
    position = terrain.world_to_local_position(world_position)
    _wait = _rng.randf_range(.2,1.5)
    if not journey.is_empty() and not _loot_record.health.is_dead():
        var saved: Dictionary = _loot_record.get("journey",{})
        if saved.get("key","") == journey.key and saved.get("position") is Vector3:
            world_position = saved.position
            position = terrain.world_to_local_position(world_position)
            _waypoint = clampi(int(saved.get("waypoint",0)),0,route.size()-1)
            _travel_direction = int(saved.get("direction",1))
            _visit_remaining = float(saved.get("visit",0))
        _advance_after_wait = false

func persist_journey() -> void:
    if journey.is_empty() or _loot_record.is_empty(): return
    var saved_position := world_position
    var saved_waypoint := _waypoint
    if is_instance_valid(ferry_riding):
        saved_position = ferry_riding.save_position(self)
        var departure := ferry_riding.side
        saved_waypoint = int(journey.get("land_indexes",[0,0])[departure])
    _loot_record["journey"] = {"key":journey.key,"position":saved_position,"waypoint":saved_waypoint,"direction":_travel_direction,"visit":_visit_remaining}

func _advance_route() -> void:
    if journey.is_empty():
        _waypoint = posmod(_waypoint+_travel_direction,route.size())
    else:
        _waypoint = clampi(_waypoint+_travel_direction,0,route.size()-1)

func ferry_arrived(end: int) -> void:
    if journey.is_empty():
        _waypoint = 2 if end==1 else 0
    else:
        _waypoint = int(journey.land_indexes[end])
        # Continue towards the settlement on the bank where we disembarked.
        _travel_direction = 1 if end==1 else -1
        _travel_trail.clear()
        persist_journey()
    _wait = 1.0
    _advance_after_wait = false

func configure_space(space: Node3D, definition: Dictionary) -> void:
    _space = space
    model_index = definition.model
    _peasant_model = model_index
    role = definition.role
    _loot_record = LootSession.get_record("npc:%s:%d:%d"%[role,model_index,definition.seed],definition.seed,true)
    affection = LootSession.get_affection(_loot_record,SPECIES[model_index])
    route.assign(definition.route)
    _rng.seed = definition.seed
    _waypoint = int(definition.get("start",0))%route.size()
    var start_point := route[_waypoint].lerp(route[(_waypoint+1)%route.size()],_rng.randf_range(.05,.25))
    world_position = Vector3(start_point.x,.04,start_point.y)
    if _loot_record.health.is_dead(): world_position = _loot_record.get("position",world_position)
    position = world_position
    _wait = _rng.randf_range(.2,1.5)

    if not _loot_record.health.is_dead() and _loot_record.get("city_position") is Vector3:
        var saved: Vector3 = _loot_record.city_position
        if saved.is_finite() and space.is_walkable(Vector2(saved.x,saved.z)):
            world_position = saved
            position = saved
            _waypoint = posmod(int(_loot_record.get("city_waypoint",_waypoint)),route.size())

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
    if _space != null: return _space.to_global(point)
    return _terrain.world_to_local_position(point) if _dungeon == null else _dungeon.to_global(point)
func _to_world(point: Vector3) -> Vector3:
    if _space != null: return _space.to_local(point)
    return _terrain.local_to_world_position(point) if _dungeon == null else _dungeon.to_local(point)
func _ground_height(point: Vector2) -> float:
    if is_instance_valid(ferry_route):
        var height = ferry_route.deck_height(point)
        if height!=null: return height
    if _space != null: return 0.0
    if _dungeon is ReadableProceduralDungeonWorld:
        return _dungeon._height_field.sample_floor(point.x,point.y,DungeonGeometryBuilder.CELL_SIZE)
    return 0.0 if _dungeon != null else _route_sampler._paths.walking_height(point)

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
    NearbyActorIndex.invalidate() # Include newly spawned actors in subsequent perception queries.
    _update_cadence.configure(get_instance_id()) # Spread distant update phases across the population.
    _update_player = get_tree().get_first_node_in_group("player") as Node3D # Resolve the player once when available.
    if _terrain != null: # Reposition overworld actors even while their own processing is disabled.
        _terrain.origin_shifted.connect(_synchronize_world_position) # Update actor coordinates after an actual origin shift.
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
    if _loot_record.health.is_dead():
        if (_werewolf_carrier or _vampire_carrier) and _loot_record.get(_night_form_key(),false): _replace_form(_night_model)
        _show_corpse()
    else: _update_werewolf_form()

func _process(delta: float) -> void:
    # Timing scopes are inactive until a console recording begins.
    if not RuntimeProfiler.recording:
        _profile__process(delta)
        return
    var _profile_token = RuntimeProfiler.begin("npcs.animation")
    _profile__process(delta)
    RuntimeProfiler.end(_profile_token)

func _profile__process(delta: float) -> void:
    _update_werewolf_form() # Keep explicit time changes immediately visible independently of pose cadence.
    equipment.sync_inventory() # Apply inventory revisions immediately, including looted corpse weapons.
    delta = _update_cadence.animation_step(delta, combat.active or _action_remaining > 0.0) # Reduce distant skeleton work while retaining elapsed playback time.
    if delta <= 0.0: # Keep the preceding pose between scheduled evaluations.
        return # Avoid bone and equipment updates on skipped frames.
    if _loot_record.health.is_dead():
        equipment.update_pose()
        return
    _animation.advance(delta)
    _ground_feet()
    equipment.update_pose()

static func werewolf_seed(seed_value: int) -> bool:
    var rng := RandomNumberGenerator.new()
    rng.seed = hash("werewolf:%d" % seed_value)
    return rng.randi_range(0,49) == 0

static func vampire_seed(seed_value: int) -> bool:
    # A separate outcome in the same lottery makes both forms exactly 1/50,
    # without assigning two transformations to one peasant.
    var rng := RandomNumberGenerator.new()
    rng.seed = hash("werewolf:%d" % seed_value)
    return rng.randi_range(0,49) == 1

func _night_form_key() -> String:
    return "vampire_form" if _vampire_carrier else "werewolf_form"

func _update_werewolf_form() -> void:
    if not (_werewolf_carrier or _vampire_carrier) or health.is_dead(): return
    var clock := get_tree().get_first_node_in_group(DayNightCycle.GROUP_NAME) as DayNightCycle
    if clock == null: return
    var hour := clock.get_time_of_day_hours()
    var night := DayNightCycle.is_night_hour(hour)
    var form_key := _night_form_key()
    if night:
        if not _loot_record.get(form_key,false):
            _loot_record["day_affection"] = affection.get_score()
            _loot_record[form_key] = true
        affection.set_score(0.0)
        if model_index != _night_model: _replace_form(_night_model)
    else:
        if _loot_record.get(form_key,false):
            affection.set_score(float(_loot_record.get("day_affection",100.0)))
            _loot_record[form_key] = false
        if model_index == _night_model: _replace_form(_peasant_model)

func _replace_form(next_model: int) -> void:
    combat.cancel()
    _was_in_combat = false
    _action_remaining = 0.0
    _animation.stop()
    remove_child(_visual)
    _visual.queue_free()
    model_index = next_model
    var model_path: String = "res://actors/npcs/villagers/models/vampire.glb" if next_model == VAMPIRE_MODEL else MODEL_PATHS[next_model]
    var animation_path: String = "res://actors/npcs/villagers/animations/vampire.res" if next_model == VAMPIRE_MODEL else LIBRARY_PATHS[next_model]
    _visual = load(model_path).instantiate()
    _visual.name = "Visual"
    add_child(_visual)
    _animation = _visual.find_child("AnimationPlayer",true,false)
    if _animation == null:
        _animation = AnimationPlayer.new()
        _animation.name = "AnimationPlayer"
        _visual.add_child(_animation)
    _rig = _visual.find_children("*","Skeleton3D",true,false)[0]
    _animation.add_animation_library("Quaternius",load(animation_path))
    _animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
    _animation.playback_default_blend_time = .18
    _feet.clear()
    var mapper = preload("res://actors/npcs/villagers/authoring/rig_map.gd")
    for semantic in ["LeftFoot","RightFoot","LeftToeBase","RightToeBase"]:
        var bone = mapper.find_target_bone(_rig,semantic)
        if bone >= 0: _feet.append(bone)
    _prepare_mesh(_visual)
    _play("idle")
    _animation.advance(0)
    _ground_feet()
    equipment.configure(self,_rig,_loot_record.inventory)

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
    if is_instance_valid(ferry_riding):
        velocity = Vector3.ZERO
        _play("idle")
        return
    if (_terrain == null and _dungeon == null and _space == null) or route.size() < 2: return
    _synchronize_world_position() # Restore explicit world-position changes without repeating identical transform writes.
    if _update_cadence.distance_check_due(delta): # Reassess proximity at a bounded rate.
        if not is_instance_valid(_update_player): # Support actors spawned before the player exists.
            _update_player = get_tree().get_first_node_in_group("player") as Node3D # Refresh the cached player reference.
        _update_cadence.distance_squared = global_position.distance_squared_to(_update_player.global_position) if is_instance_valid(_update_player) else 0.0 # Retain full updates when no player can be resolved.
    delta = _update_cadence.physics_step(delta, combat.needs_immediate_update() or _action_remaining > 0.0 or is_instance_valid(ferry_route)) # Keep fights, actions and ferry boarding on the ordinary physics cadence.
    if delta <= 0.0: # Defer distant patrol and terrain work between updates.
        return # Preserve the current route state until the next scheduled update.
    var fighting = combat.tick(delta)
    if _was_in_combat and not fighting:
        _action_remaining = 0
        _wait = 1
        _play("idle")
        _combat_path.clear()
    _was_in_combat = fighting
    if _visit_remaining > 0 and not fighting:
        _visit_remaining = maxf(0,_visit_remaining-delta)
        velocity = Vector3.ZERO
        _play("idle")
        return
    var boarding_side := -1
    if is_instance_valid(ferry_route):
        if journey.is_empty() and _waypoint in [1,3]: boarding_side = 0 if _waypoint==1 else 1
        elif not journey.is_empty(): boarding_side = int(journey.get("ferry_stops",{}).get(_waypoint,-1))
    if not fighting and boarding_side >= 0:
        var dock: Dictionary = ferry_route.definition.docks[boarding_side]
        if Vector2(world_position.x,world_position.z).distance_to(dock.tip)<1:
            ferry_route.request(self,boarding_side)
            velocity = Vector3.ZERO
            _play("idle")
            return
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
            if _advance_after_wait: _advance_route()
            _advance_after_wait = true
            _state = "run" if role in ["traveller","knight_patrol","city_knight"] and _rng.randf() < (.1 if encounter_kind == "explorers" else .45) else "walk"
    else:
        var point = Vector2(world_position.x,world_position.z)
        var target = route[_waypoint]
        var leader: Villager = follow_leader.get_ref() if follow_leader != null else null
        var following := is_instance_valid(leader) and not leader.health.is_dead() and not leader.is_in_combat() and leader.is_physics_processing() and leader._travel_direction == _travel_direction
        if following:
            target = leader.trail_target(follow_gap,point)
            _waypoint = leader._waypoint
            _state = "run" if leader._state == "run" and leader._wait <= 0 else "walk"
        var direction = (target-point).normalized()
        var speed: float = 3.6 if _state == "run" else 1.65
        if following and point.distance_to(target)>4: speed *= 1.2
        var next = point+direction*speed*delta
        if point.distance_to(target) < .65:
            velocity.x = 0
            velocity.z = 0
            if following:
                _wait = .12
                _advance_after_wait = false
            else: _wait = _rng.randf_range(.4,1.8) if role not in ["traveller","knight_patrol","city_knight"] else _rng.randf_range(.15,.7)
            if not following and encounter_kind == "explorers": _wait = _rng.randf_range(.8,2.2)
            if not journey.is_empty() and ((_waypoint==route.size()-1 and _travel_direction==1) or (_waypoint==0 and _travel_direction==-1)):
                # Visit the settlement before departing on the checked return road.
                _visit_remaining = _rng.randf_range(25,60)
                _travel_direction *= -1
                _advance_after_wait = true
                persist_journey()
        elif not _walkable(next):
            _wait = 1.5
            _advance_after_wait = false
            velocity.x = 0
            velocity.z = 0
            if journey.is_empty():
                _travel_direction *= -1
                _advance_route()
        else:
            velocity.x = direction.x*speed
            velocity.z = direction.y*speed
            rotation.y = lerp_angle(rotation.y,atan2(direction.x,direction.y),minf(1,delta*6))
            _play(_state)

    velocity.y = 0.0 if is_on_floor() else maxf(velocity.y-24*delta,-20)
    var before = global_position
    if _update_cadence.uses_distant_movement() and not fighting and not is_instance_valid(ferry_route): # Use checked route travel for remote actors.
        global_position += Vector3(velocity.x, 0.0, velocity.z) * delta # Preserve patrol speed without invoking movement collision for distant steps.
    else: # Retain collision-backed movement during nearby interactions and combat.
        move_and_slide() # Resolve close movement against active world collision.
    var actual = _to_world(global_position)
    var point = Vector2(actual.x,actual.z)
    var ground = _ground_height(point)
    # Sampled ground also supports routes at the edge of the collision stream.
    if (_update_cadence.uses_distant_movement() and not fighting) or actual.y < ground-.10 or actual.y > ground+1.0:
        actual.y = ground+.04
        velocity.y = 0
    world_position = actual
    if role == "traveller":
        var trail_point := Vector2(actual.x,actual.z)
        if _travel_trail.is_empty() or trail_point.distance_to(_travel_trail.back()) >= .5:
            _travel_trail.append(trail_point)
            if _travel_trail.size()>128: _travel_trail.pop_front()
    _synchronize_world_position() # Write the final transform only when sampled grounding corrected it.
    if Vector2(velocity.x,velocity.z).length() > .1 and global_position.distance_to(before) < delta*.12:
        _blocked += delta
        if _blocked > 1.3:
            _wait = 2
            _advance_after_wait = false
            if journey.is_empty():
                _travel_direction *= -1
                _advance_route()
            _blocked = 0
    else: _blocked = 0

func _walkable(point: Vector2) -> bool:
    if is_instance_valid(ferry_route) and ferry_route.deck_height(point)!=null:
        return absf(float(ferry_route.deck_height(point))-world_position.y)<.55
    if _space != null: return _space.is_walkable(point)
    if _dungeon != null:
        var cell = Vector2i(floori(point.x/DungeonGeometryBuilder.CELL_SIZE+_dungeon._layout.width*.5),floori(point.y/DungeonGeometryBuilder.CELL_SIZE+_dungeon._layout.height*.5))
        return _dungeon._layout.is_walkable(cell) and absf(_ground_height(point)-world_position.y) < .55
    if (_terrain.has_water_at(point) and _route_sampler._paths.bridge_height(point) == null) or BiomeProfile.is_lava(point) or _route_sampler.is_obstructed(point, role == "camper"): return false # Allow camp residents to walk within their clearing.
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

func _synchronize_world_position() -> void: # Keep absolute actor state aligned after explicit moves and origin shifts.
    var expected: Vector3 = _to_local(world_position) # Resolve the current local position from authoritative world state.
    if not global_position.is_equal_approx(expected): # Avoid sending an unchanged transform through the scene and physics servers.
        global_position = expected # Apply only an actual position correction.

func set_active(active: bool) -> void:
    if is_processing() == active and is_physics_processing() == active: # Avoid repeating processing and collision changes every streamer frame.
        return # Retain the current activation state.
    _update_cadence.reset() # Drop deferred time whenever streaming changes activation.
    if not active and combat != null: combat.cancel()
    set_physics_process(active)
    set_process(active)
    collision_layer = 4 if active else 0
    collision_mask = 1|4 if active and not is_instance_valid(ferry_riding) else 0

func _prepare_mesh(node: Node) -> void:
    if node is MeshInstance3D: node.custom_aabb = AABB(Vector3(-2,-1,-2),Vector3(4,4,4))
    for child in node.get_children(): _prepare_mesh(child)

func get_health_component() -> DamageableHealth: return health
func receive_equipment_hit(hit: EquipmentHit):
    if hit == null or health == null: return
    _damage_source = hit.source
    var applied: float = health.apply_damage(hit.damage)
    _damage_source = null
    if applied > 0.0:
        NpcRelationships.damage_received(self,hit.source,applied)
func _on_death():
    if is_instance_valid(ferry_riding): ferry_riding.release(self,ferry_riding.side)
    _loot_record.position = world_position
    var player = get_tree().get_first_node_in_group("player")
    if player != null and _damage_source == player:
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
    if model_index == 12: return "Shadow person's belongings"
    if model_index == 11: return "King\'s belongings"
    if model_index == VAMPIRE_MODEL: return "Vampire's belongings"
    if model_index == 9: return "Knight's belongings"
    if model_index == WEREWOLF_MODEL: return "Werewolf's belongings"
    return ["Pilgrim","Weaver","Orc","Demon","Ghost","Zombie","Fish-man","Wizard"][model_index]+"'s belongings"

func get_affection() -> float: return affection.get_score()
func set_affection(value: float): affection.set_score(value)
func change_affection(amount: float): affection.change_score(amount)

func get_social_record() -> Dictionary: return _loot_record
func get_default_affection() -> float: return AffectionState.starting_score(SPECIES[model_index])
func get_relationship_species() -> String:
    if model_index in [0,1,7,9,11]: return "human"
    return SPECIES[model_index]
func get_social_space() -> Object:
    if _space != null: return _space
    if _dungeon != null: return _dungeon
    return _terrain.get_world_3d() if _terrain != null and _terrain.is_inside_tree() else _terrain
func get_npc_affection(other: Node): return NpcRelationships.get_score(self,other)
func set_npc_affection(other: Node, value: float) -> bool: return NpcRelationships.set_score(self,other,value)
func change_npc_affection(other: Node, amount: float) -> bool: return NpcRelationships.change_score(self,other,amount)

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

func trail_target(gap: float, follower: Vector2 = Vector2(INF,INF)) -> Vector2:
    var previous := Vector2(world_position.x,world_position.z)
    var remaining := gap
    var goal := previous
    var goal_index := 0
    for index in range(_travel_trail.size()-1,-1,-1):
        var point := _travel_trail[index]
        var distance := previous.distance_to(point)
        goal = point
        goal_index = index
        if distance >= remaining:
            goal = previous.lerp(point,remaining/maxf(distance,.001))
            break
        remaining -= distance
        previous = point
    # A lagging companion takes intermediate footsteps around bends.
    if follower.is_finite() and goal_index>2:
        var nearest := 0
        var closest := INF
        for index in range(goal_index+1):
            var distance := follower.distance_squared_to(_travel_trail[index])
            if distance < closest:
                closest = distance
                nearest = index
        if nearest+2 < goal_index: return _travel_trail[nearest+2]
    return goal

func _exit_tree() -> void:
    NearbyActorIndex.invalidate() # Force subsequent perception queries to release this actor.
    if _space == null: persist_journey()
