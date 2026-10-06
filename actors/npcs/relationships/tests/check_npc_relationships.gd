extends SceneTree

class Actor extends Node3D:
    var record: Dictionary
    var species := "human"
    var default_kind := ""
    var space: Object
    var health: DamageableHealth
    func configure(id: String, kind: String, world: Object):
        record = LootSession.get_record(id,hash(id),true)
        species = kind
        space = world
    func _ready():
        health = DamageableHealth.new()
        health.bind_state(record.health)
        add_child(health)
    func get_social_record() -> Dictionary: return record
    func get_relationship_species() -> String: return species
    func get_default_affection() -> float: return AffectionState.starting_score(species if default_kind.is_empty() else default_kind)
    func get_social_space() -> Object: return space
    func get_health_component() -> DamageableHealth: return health

func _initialize(): run.call_deferred()
func actor(id: String, species: String, space: Object, position: Vector3) -> Actor:
    var npc := Actor.new()
    npc.configure(id,species,space)
    npc.position = position
    root.add_child(npc)
    return npc

func run():
    LootSession.records.clear()
    var manager := NpcRelationships.new()
    root.add_child(manager)
    manager.set_process(false)
    var world := Node.new()
    var cave := Node.new()
    root.add_child(world); root.add_child(cave)
    var a := actor("social:a","human",world,Vector3.ZERO)
    var b := actor("social:b","human",world,Vector3(50.01,0,0))
    assert(NpcRelationships.get_score(a,b) == null)
    assert(not NpcRelationships.set_score(a,b,12))
    manager.scan([a,b])
    assert(not a.record.has("npc_affection") and not b.record.has("npc_affection"))
    b.position.x = 50
    manager.scan([a,b])
    assert(NpcRelationships.get_score(a,b) == 150)
    assert(NpcRelationships.get_score(b,a) == 150)
    assert(NpcRelationships.get_score(a,a) == null)
    assert(NpcRelationships.set_score(a,b,73.5))
    var reverse = NpcRelationships.get_score(b,a)
    assert(NpcRelationships.change_score(a,b,-3.5))
    assert(NpcRelationships.get_score(a,b) == 70 and NpcRelationships.get_score(b,a) == reverse)
    b.position.x = 400
    manager.scan([a,b])
    b.species = "werewolf"
    b.position.x = 20
    manager.scan([b,a])
    assert(NpcRelationships.get_score(a,b)==70)
    # Separate spaces must not meet even if their coordinates coincide.
    var c := actor("social:c","orc",cave,Vector3.ZERO)
    manager.scan([a,b,c])
    assert(NpcRelationships.get_score(a,c)==null)
    c.space = world
    manager.scan([a,b,c])
    assert(NpcRelationships.get_score(a,c)==100)
    assert(NpcRelationships.get_score(c,a)==50)
    # Human knights use the knight default but share the human species bonus.
    var knight := actor("social:knight","human",world,Vector3.ZERO)
    knight.default_kind = "knight"
    manager.scan([a,knight])
    assert(NpcRelationships.get_score(a,knight)==150)
    assert(NpcRelationships.get_score(knight,a)==61)
    for kind in ["ghost","zombie","demon","fish_man","werewolf","vampire"]:
        var stranger := actor("social:"+kind,kind,world,Vector3.ZERO)
        manager.scan([a,stranger])
        assert(NpcRelationships.get_score(stranger,a)==(25 if kind=="ghost" else 0))
        var peer := actor("social:peer:"+kind,kind,world,Vector3.ZERO)
        manager.scan([stranger,peer])
        assert(NpcRelationships.get_score(stranger,peer)==(75 if kind=="ghost" else 50))
        stranger.queue_free(); peer.queue_free()
    # A vertical separation also counts towards the fifty-metre radius.
    var high := actor("social:high","human",world,Vector3(0,51,0))
    manager.scan([a,high])
    assert(NpcRelationships.get_score(a,high)==null)
    high.process_mode = Node.PROCESS_MODE_DISABLED
    high.position = Vector3.ZERO
    manager.scan([a,high])
    assert(NpcRelationships.get_score(a,high)==null)
    high.process_mode = Node.PROCESS_MODE_INHERIT
    manager.scan([a,high])
    assert(NpcRelationships.get_score(a,high)!=null)
    # Codec round-trip retains directed states and fractional affection.
    NpcRelationships.set_score(a,b,123.25)
    var encoded = SaveCodec.encode(LootSession.records)
    assert(SaveCodec.valid(encoded))
    LootSession.records = SaveCodec.decode(encoded)
    a.record = LootSession.get_record("social:a",0,true)
    b.record = LootSession.get_record("social:b",0,true)
    manager.scan([a,b])
    assert(NpcRelationships.get_score(a,b)==123.25 and NpcRelationships.get_score(b,a)==reverse)
    var king := Villager.new()
    for model in [0,1,7,9,11]:
        king.model_index = model
        assert(king.get_relationship_species()=="human")
    king.model_index = 8
    assert(king.get_relationship_species()=="werewolf")
    for model in range(12):
        king.model_index = model
        assert(king.get_default_affection()==[100,100,50,0,25,0,0,100,0,11,0,100][model])
    king.free()
    for node in [a,b,c,high,knight,world,cave,manager]: node.queue_free()
    await process_frame
    print("PASS lazy 50m meetings, player defaults for all twelve models, +50 species bonus, directed scores, no rerolls and saved fractional scores")
    quit()
