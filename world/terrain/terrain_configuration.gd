extends RefCounted # Groups immutable terrain streaming and mesh dimensions without scene ownership.
class_name TerrainConfiguration # Makes shared terrain dimensions available to generation and streaming code.

const CHUNK_SIZE: float = 96.0 # Enlarges each streamed terrain section so the visible world covers broader geographic distances.
const CHUNK_RESOLUTION: int = 25 # Creates a coarser four-metre vertex grid across each chunk including both borders.
const VISUAL_RADIUS: int = 7 # Keeps a broad square of terrain visible around the player's current chunk.
const COLLISION_RADIUS: int = 2 # Keeps exact terrain collision only in nearby chunks where gameplay can reach it.
const INITIAL_COLLISION_RADIUS: int = 1 # Builds a complete three-by-three collision neighbourhood before resolving the player spawn.
const CHUNKS_BUILT_PER_FRAME: int = 2 # Limits main-thread mesh creation to prevent large streaming spikes.
const TERRAIN_UV_SCALE: float = 0.03125 # Produces consistent world-space texture coordinates for future terrain materials.
const ORIGIN_REBASE_DISTANCE: float = 4096.0 # Allows longer travel across the enlarged landscape before floating-origin correction is required.
