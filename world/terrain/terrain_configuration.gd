extends RefCounted # Groups immutable terrain streaming and mesh dimensions without scene ownership.
class_name TerrainConfiguration # Makes shared terrain dimensions available to generation and streaming code.

const CHUNK_SIZE: float = 256.0 # Covers large geographic sections so mountain provinces and valleys read at monumental scale.
const CHUNK_RESOLUTION: int = 33 # Creates an eight-metre vertex grid that preserves the deliberately coarse terrain silhouette.
const VISUAL_RADIUS: int = 9 # Keeps almost five kilometres of terrain loaded across the player's surrounding view.
const COLLISION_RADIUS: int = 2 # Keeps exact terrain collision only in nearby chunks where gameplay can reach it.
const INITIAL_COLLISION_RADIUS: int = 1 # Builds a complete three-by-three collision neighbourhood before resolving the player spawn.
const CHUNKS_BUILT_PER_FRAME: int = 2 # Limits main-thread mesh creation to prevent large streaming spikes.
const TERRAIN_UV_SCALE: float = 0.03125 # Produces consistent world-space texture coordinates for future terrain materials.
const ORIGIN_REBASE_DISTANCE: float = 32768.0 # Allows long journeys through kilometre-scale landforms before floating-origin correction is required.
