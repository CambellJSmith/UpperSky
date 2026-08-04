extends RefCounted # Groups immutable terrain streaming and mesh dimensions without scene ownership.
class_name TerrainConfiguration # Makes shared terrain dimensions available to generation and streaming code.

const CHUNK_SIZE: float = 64.0 # Defines the horizontal size of every independently streamed terrain chunk.
const CHUNK_RESOLUTION: int = 33 # Creates a regular two-metre vertex grid across each chunk including both borders.
const VISUAL_RADIUS: int = 7 # Keeps a broad square of terrain visible around the player's current chunk.
const COLLISION_RADIUS: int = 2 # Keeps exact terrain collision only in nearby chunks where gameplay can reach it.
const CHUNKS_BUILT_PER_FRAME: int = 2 # Limits main-thread mesh creation to prevent large streaming spikes.
const TERRAIN_UV_SCALE: float = 0.03125 # Produces consistent world-space texture coordinates for future terrain materials.
const ORIGIN_REBASE_DISTANCE: float = 2048.0 # Keeps active transforms close to the origin during effectively unbounded travel.
