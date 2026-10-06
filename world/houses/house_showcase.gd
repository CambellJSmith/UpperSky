extends Node3D
class_name HouseShowcase

## An optional six-house inspection courtyard, separate from world settlement placement.
var _terrain: InfiniteTerrain
var _world_anchor: Vector3
var _contents: Node3D

func show_for(player: FirstPersonPlayer, terrain: InfiniteTerrain, seed_value: int) -> void:
    _terrain = terrain
    var world: Vector3 = terrain.local_to_world_position(player.global_position)
    var ground: float = maxf(terrain.get_height_at(Vector2(world.x,world.z)),terrain.get_water_level_at(Vector2(world.x,world.z)))
    for x in [-36.0,0.0,36.0]:
        for z in [-26.0,0.0,26.0]:
            ground = maxf(ground,terrain.get_height_at(Vector2(world.x+x,world.z+z)))
    _world_anchor = Vector3(world.x,ground+35.0,world.z)
    position = terrain.world_to_local_position(_world_anchor)
    populate(seed_value)
    player.set_fly_mode_enabled(true)
    player.global_position = global_position+Vector3(0,13,-38)
    player.velocity = Vector3.ZERO
    player.rotation.y = PI
    player.get_node("Head").rotation.x = -.24

func _process(_delta: float) -> void:
    if _terrain != null:
        position = _terrain.world_to_local_position(_world_anchor)

func populate(seed_value: int) -> void:
    if is_instance_valid(_contents):
        remove_child(_contents)
        _contents.queue_free()
    _contents = Node3D.new()
    _contents.name = "HouseCollection"
    add_child(_contents)
    var floor_material = StandardMaterial3D.new()
    floor_material.albedo_color = Color("68736b")
    floor_material.roughness = 1.0
    var platform = MeshInstance3D.new()
    var mesh = BoxMesh.new()
    mesh.size = Vector3(74,.6,54)
    platform.mesh = mesh
    platform.material_override = floor_material
    platform.position.y = -.3
    _contents.add_child(platform)
    var body = StaticBody3D.new()
    _contents.add_child(body)
    var shape = CollisionShape3D.new()
    var box = BoxShape3D.new()
    box.size = mesh.size
    shape.shape = box
    shape.position.y = -.3
    body.add_child(shape)
    var walls = [HouseRecipe.WallStyle.STONE,HouseRecipe.WallStyle.WOOD,HouseRecipe.WallStyle.BRICK,HouseRecipe.WallStyle.TIMBER_FRAME,HouseRecipe.WallStyle.TIMBER_FRAME,HouseRecipe.WallStyle.STONE]
    for i in range(6):
        var house = ProceduralHouse.new()
        var recipe = HouseRecipe.new()
        recipe.seed_value = seed_value+i*137
        recipe.layout = i+1
        recipe.wall_style = walls[i]
        recipe.roof_style = HouseRecipe.RoofStyle.THATCH if i < 2 else HouseRecipe.RoofStyle.SLATE
        house.recipe = recipe
        house.name = "House%d"%i
        house.position = Vector3((i%3-1)*24,0,(-12 if i<3 else 12))
        _contents.add_child(house)
