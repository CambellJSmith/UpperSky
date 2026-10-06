extends SceneTree

class Actor extends CharacterBody3D:
    var affection := AffectionState.new(100)
    var health: DamageableHealth
    var combat: NpcCombat
    var record: Dictionary
    func _ready():
        record = {"npc_id":str(get_instance_id())}
        health = DamageableHealth.new()
        add_child(health)
        combat = NpcCombat.new()
        add_child(combat)
        combat.configure(self,affection,health.state)
        var collision := CollisionShape3D.new()
        var shape := CapsuleShape3D.new()
        shape.radius = .4
        shape.height = 2
        collision.shape = shape
        collision.position.y = 1
        add_child(collision)
        collision_layer = 4
        add_to_group("npc")
    func get_health_component(): return health
    func get_social_record(): return record
    func get_social_space(): return get_world_3d()
    func get_relationship_species(): return "human"
    func get_default_affection(): return 100.0
    func change_affection(amount): affection.change_score(amount)
    func receive_equipment_hit(hit):
        NpcRelationships.damage_received(self,hit.source,health.apply_damage(hit.damage))

func _initialize(): run.call_deferred()
func run():
    var scene := Node3D.new()
    root.add_child(scene)
    var caster := Actor.new()
    var victim := Actor.new()
    var player = load("res://actors/player/first_person_player.tscn").instantiate()
    scene.add_child(caster)
    scene.add_child(victim)
    scene.add_child(player)
    player.set_physics_process(false)
    caster.position = Vector3(0,0,0)
    victim.position = Vector3(0,0,3)
    player.position = Vector3(0,0,6)
    NpcRelationships.meet(caster,victim)
    assert(NpcRelationships.get_score(victim,caster) == 150)
    await physics_frame
    # Fireballs aimed at the player must hit an intervening NPC instead.
    for shot in range(3):
        var projectile = load("res://actors/combat/npc_fireball.gd").new()
        scene.add_child(projectile)
        projectile.launch(caster,player.global_position+Vector3.UP,20)
        for step in range(20): await physics_frame
    assert(victim.health.get_health() == 40,"Projectile did not hit the intervening NPC")
    assert(player.get_health_state().get_health() == 100,"Projectile passed through the NPC")
    assert(NpcRelationships.get_score(victim,caster) == 90)
    assert(victim.affection.score == 100,"NPC damage blamed the player")
    assert(NpcRelationships.get_score(caster,victim) == 150,"Damage changed the reverse relationship")
    var encoded = SaveCodec.encode(victim.record)
    assert(SaveCodec.valid(encoded))
    victim.record = SaveCodec.decode(encoded)
    assert(victim.record.npc_aggressors.has(caster.record.npc_id),"Saved grudge was lost")
    assert(victim.combat.tick(.01) and victim.combat.target == caster,"Victim did not retaliate against its less liked attacker")
    victim.affection.set_score(0)
    # Move the player out of the obstructed line of sight.
    player.position = Vector3(2,0,3)
    await physics_frame
    victim.combat.tick(.3)
    assert(victim.combat.target == player,"NPC did not prioritize its lowest affection")
    victim.combat.deal_hit(caster,8)
    assert(caster.health.get_health() == 92)
    assert(NpcRelationships.get_score(caster,victim) == 142,"Melee damage did not lower affection")
    caster.health.set_infinite_health_enabled(true)
    victim.combat.deal_hit(caster,8)
    assert(NpcRelationships.get_score(caster,victim) == 142,"Prevented damage changed affection")
    var hit := EquipmentHit.new()
    hit.source = player
    hit.damage = 5
    victim.receive_equipment_hit(hit)
    assert(victim.affection.score == 0)
    assert(NpcRelationships.get_score(victim,caster) == 90)
    caster.health.set_infinite_health_enabled(false)
    caster.health.set_health(0)
    victim.affection.set_score(100)
    assert(not victim.combat.tick(.3),"NPC targeted a corpse")
    scene.queue_free()
    await process_frame
    print("PASS intercepted fireballs, correct attacker blame, directed damage scores, retaliation above 10, lowest-affection target switching, melee, invulnerability and dead targets")
    quit()
