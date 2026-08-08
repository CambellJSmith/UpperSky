extends RefCounted # Stores one validated overworld dungeon entrance placement without creating scene-tree state.
class_name DungeonEntrancePlacement # Exposes strongly typed terrain position and outward-facing direction to dungeon placement code.

var world_position: Vector2 # Stores the absolute procedural-world horizontal coordinate at the foot of the selected terrain face.
var outward_direction: Vector2 # Stores the normalized downhill direction pointing away from the hill, cliff, or mountain containing the entrance.

func _init(position: Vector2, outward: Vector2) -> void: # Creates immutable-by-convention placement data from one validated terrain site.
    world_position = position # Retains the selected absolute terrain coordinate used to ground the generated exterior doorway.
    outward_direction = outward.normalized() # Normalizes the terrain-facing vector so yaw and exit offsets remain stable regardless of sampled gradient magnitude.
