extends ProceduralDungeonWorld # Retains the deterministic dungeon layout and geometry while making interior visibility substantially more readable.
class_name ReadableProceduralDungeonWorld # Provides brighter ambient fill and stronger existing procedural lanterns without changing topology or endpoint routing.

const LANTERN_ENERGY_MULTIPLIER: float = 1.65 # Raises each existing procedural lantern enough to illuminate nearby walls and floor clearly.
const LANTERN_RANGE_MULTIPLIER: float = 1.35 # Broadens each existing light pool so dark gaps between the bounded compatibility-renderer light count are less severe.
const READABLE_AMBIENT_COLOUR: Color = Color(0.25, 0.275, 0.32, 1.0) # Provides a cool neutral fill that preserves the warmer identity of local lanterns.
const READABLE_AMBIENT_ENERGY: float = 0.92 # Keeps unlit corridors navigable while leaving local fixtures visibly brighter than ambient stone.
const READABLE_BACKGROUND_ENERGY: float = 0.32 # Makes accidental clear-background exposure less black without competing with dungeon architecture.
const READABLE_FOG_COLOUR: Color = Color(0.13, 0.14, 0.155, 1.0) # Lightens atmospheric fill so distant corridors remain legible instead of disappearing into black.
const READABLE_FOG_ENERGY: float = 0.72 # Raises fog illumination enough to preserve depth cues under the stronger ambient baseline.
const READABLE_FOG_DENSITY: float = 0.006 # Reduces the original fog density so long corridors retain more visible geometry.

func _build_procedural_lighting() -> void: # Builds the original deterministic fixtures, then strengthens only their light resources without increasing light count.
    super._build_procedural_lighting() # Reuses the established seeded fixture placement and compatibility-safe seven-light budget.
    for child: Node in get_children(): # Examines generated direct children after the base lighting pass has installed all fixtures and lights.
        if not (child is OmniLight3D): # Skips architecture, collision, doors, fixture meshes, and every other non-light child.
            continue # Advances directly to the next generated dungeon child.
        var light: OmniLight3D = child as OmniLight3D # Converts the validated generated light to its strongly typed resource owner.
        light.light_energy *= LANTERN_ENERGY_MULTIPLIER # Raises brightness while preserving each fixture's deterministic seeded variation.
        light.omni_range *= LANTERN_RANGE_MULTIPLIER # Broadens the existing pool without adding another per-mesh light to the compatibility renderer.

func _create_environment() -> Environment: # Starts from the existing dungeon environment and raises only the values responsible for baseline readability.
    var environment: Environment = super._create_environment() # Preserves the existing textureless background, fog mode, and overworld-independent camera environment contract.
    environment.background_energy_multiplier = READABLE_BACKGROUND_ENERGY # Prevents any procedural geometry gap from presenting as absolute black.
    environment.ambient_light_color = READABLE_AMBIENT_COLOUR # Replaces the very dark blue ambient fill with a brighter neutral-cool stone-readable tone.
    environment.ambient_light_energy = READABLE_AMBIENT_ENERGY # Raises baseline illumination across the complete dungeon so navigation never depends on standing beside a lantern.
    environment.fog_light_color = READABLE_FOG_COLOUR # Keeps the reduced fog compatible with the brighter ambient stone palette.
    environment.fog_light_energy = READABLE_FOG_ENERGY # Lets fog carry enough light to retain distant corridor silhouettes.
    environment.fog_density = READABLE_FOG_DENSITY # Reduces atmospheric extinction so the procedural layout remains visible over longer sight lines.
    return environment # Returns the readability-adjusted environment used directly by the player's dungeon camera override.
