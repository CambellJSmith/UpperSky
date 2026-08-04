extends RefCounted # Groups immutable terrain streaming and mesh dimensions without scene ownership.
class_name TerrainConfiguration # Makes shared terrain dimensions available to generation and streaming code.

const CHUNK_SIZE: float = 256.0 # Covers large geographic sections so mountain provinces and valleys read at monumental scale.
const CHUNK_RESOLUTION: int = 33 # Creates an eight-metre vertex grid that preserves the deliberately coarse terrain silhouette.
const WATER_RESOLUTION: int = 17 # Creates a sixteen-metre water grid before exact triangle clipping to limit extra procedural sampling cost.
const WATER_LEVEL_OFFSET: float = -120.0 # Places each water surface below its surrounding regional shelf so only valleys and basins flood.
const WATER_LEVEL_CLEARANCE: float = 96.0 # Requires the general regional surface to sit safely above the next higher water band before switching levels.
const WATER_REGIONAL_PLATEAU_INFLUENCE: float = 0.24 # Lets broad local uplands influence water-band selection without making individual lakes slope.
const WATER_REGIONAL_BASIN_INFLUENCE: float = 0.22 # Lets enormous basins select an appropriate lower water band without following every terrain depression.
const VISUAL_RADIUS: int = 9 # Keeps almost five kilometres of terrain loaded across the player's surrounding view.
const COLLISION_RADIUS: int = 2 # Keeps exact terrain collision only in nearby chunks where gameplay can reach it.
const INITIAL_COLLISION_RADIUS: int = 1 # Builds a complete three-by-three collision neighbourhood before resolving the player spawn.
const CHUNKS_BUILT_PER_FRAME: int = 2 # Limits main-thread mesh creation to prevent large streaming spikes.
const TERRAIN_UV_SCALE: float = 0.03125 # Produces consistent world-space texture coordinates for future terrain materials.
const ORIGIN_REBASE_DISTANCE: float = 32768.0 # Allows long journeys through kilometre-scale landforms before floating-origin correction is required.
