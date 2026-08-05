extends RefCounted # Stores one deterministic smooth world-decoration instance without scene-tree ownership.
class_name WorldDecorationPlacement # Makes generated tree and boulder placements available to terrain chunks through strong typing.

enum Kind { TREE, BOULDER } # Distinguishes the collision and visual treatment required by each decoration family.

var kind: int = Kind.TREE # Stores whether this placement represents a tree or boulder.
var variant: int = 0 # Selects the shared mesh variation used by this placement.
var transform: Transform3D = Transform3D.IDENTITY # Stores the complete chunk-local visual transform, including scale and rotation.

func _init(decoration_kind: int, decoration_variant: int, decoration_transform: Transform3D) -> void: # Creates one immutable-style placement description.
    kind = decoration_kind # Stores the generated decoration family.
    variant = decoration_variant # Stores the generated shared-mesh variation.
    transform = decoration_transform # Stores the generated chunk-local transform.
