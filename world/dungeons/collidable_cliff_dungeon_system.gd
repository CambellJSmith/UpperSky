extends PreciseCliffDungeonSystem # Retains exact A/B transition placement while swapping only overworld entrance construction to the deeply embedded collidable door implementation.
class_name CollidableCliffDungeonSystem # Exposes cliff-only paired dungeons with deep visual masonry and low-poly exterior collision.

func _create_exterior_door(pair_root: Node3D, pair: DungeonPairDefinition, endpoint: DungeonPairDefinition.Endpoint) -> void: # Creates one deeply embedded exterior doorway while preserving the existing deterministic pair routing contract.
    if pair_root == null or pair == null: # Rejects malformed stream requests before allocating procedural entrance geometry.
        return # Leaves invalid pair state untouched instead of constructing an unowned doorway.
    var door: EmbeddedExteriorDungeonDoor = EmbeddedExteriorDungeonDoor.new() # Allocates the exterior-only door specialization with deep masonry and coarse primitive collision.
    door.name = "DoorB" if endpoint == DungeonPairDefinition.Endpoint.B else "DoorA" # Preserves the existing compact endpoint identity under each streamed pair root.
    pair_root.add_child(door) # Parents the entrance before assigning its world-space transform so floating-origin ownership remains correct.
    door.configure(pair.pair_id, endpoint, true, pair.get_yaw(endpoint), pair.get_display_name(endpoint)) # Builds the procedural exterior using the exact deterministic pair metadata already consumed by transition routing.
    door.global_position = _terrain.world_to_local_position(pair.get_world_position(endpoint)) # Places the generated entrance at the exact terrain-backed endpoint after any accumulated floating-origin rebase.
