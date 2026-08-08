extends Node3D # Implements a stationary reusable combat target that accepts structured equipment hits.
class_name StrawDummyEnemy # Exposes the training target type to game composition and future combat tests.

const MAXIMUM_HEALTH: float = 100.0 # Defines the dummy's complete health pool before it enters its temporary defeated state.
const RESPAWN_DELAY_SECONDS: float = 2.5 # Keeps the training target reusable shortly after the player reduces it to zero health.
const HEALTH_BAR_FILL_HALF_WIDTH: float = 0.84 # Matches half the authored fill-mesh width so shrinking remains anchored to the left edge.
const HIT_REACTION_ANGLE: float = 0.08 # Defines the small visible lean applied whenever the straw body receives real damage.
const HIT_REACTION_OUT_DURATION: float = 0.06 # Defines how quickly the dummy leans away from a successful impact.
const HIT_REACTION_RETURN_DURATION: float = 0.16 # Defines how quickly the dummy settles back into its authored upright pose.

@onready var _health: DamageableHealth = $Health # Stores the reusable health component that owns authoritative current and maximum health.
@onready var _visual_root: Node3D = $Visuals # Stores the visual-only root used for hit reactions without moving collision or health UI.
@onready var _health_bar_fill: MeshInstance3D = $HealthBar/Fill # Stores the billboarded foreground bar whose horizontal scale represents remaining health.
@onready var _health_text: Label3D = $HealthBar/HealthText # Stores the floating numeric health readout above the target.

var _displayed_health_revision: int = -1 # Tracks the last health state rendered into the floating health presentation.
var _respawn_remaining_seconds: float = 0.0 # Counts down while a defeated training dummy waits to restore itself.
var _reaction_tween: Tween # Owns the active visual hit reaction so consecutive impacts cannot fight over rotation.

func _ready() -> void: # Initializes full health and synchronizes the authored floating health presentation.
    _health.initialize(MAXIMUM_HEALTH) # Starts the target at its complete reusable training health pool.
    _refresh_health_presentation() # Draws the initial full health bar and numeric value immediately.

func _process(delta: float) -> void: # Polls health revisions and advances the local respawn timer without signal dependencies.
    if _health.get_revision() != _displayed_health_revision: # Detects damage or restoration that has not yet reached the health presentation.
        _refresh_health_presentation() # Synchronizes the floating bar and text with authoritative health state.
    if _respawn_remaining_seconds <= 0.0: # Detects an active target that does not currently need respawn timing.
        return # Avoids unnecessary timer work while the dummy is alive.
    _respawn_remaining_seconds = maxf(_respawn_remaining_seconds - delta, 0.0) # Advances the defeat timer while preventing negative time.
    if _respawn_remaining_seconds > 0.0: # Detects a defeated target that still has time remaining before restoration.
        return # Leaves zero health visible until the configured reset delay completes.
    _health.restore_full_health() # Restores the reusable target to full health when the timer finishes.
    _visual_root.rotation = Vector3.ZERO # Ensures the straw body returns to its upright authored pose after restoration.

func receive_equipment_hit(hit: EquipmentHit) -> void: # Accepts the generic equipment-hit contract resolved by the player's camera raycast.
    if hit == null or _health.is_dead(): # Rejects malformed hits and additional impacts while the target is already defeated.
        return # Leaves health and presentation unchanged for rejected contacts.
    var applied_damage: float = _health.apply_damage(hit.damage) # Applies the equipped definition's exact damage value through reusable health state.
    if applied_damage <= 0.0: # Detects tools or future equipment definitions that intentionally deal no health damage.
        return # Avoids playing a false impact reaction when health did not change.
    _play_hit_reaction(hit) # Gives successful raycast contact immediate visible feedback on the straw body.
    if _health.is_dead(): # Detects the hit that reduced the target to zero health.
        _respawn_remaining_seconds = RESPAWN_DELAY_SECONDS # Starts the local reusable-target reset timer without removing the scene instance.

func _play_hit_reaction(hit: EquipmentHit) -> void: # Leans the straw visuals briefly in response to a successful damage event.
    if _reaction_tween != null and _reaction_tween.is_valid(): # Detects an earlier reaction that has not yet completed.
        _reaction_tween.kill() # Prevents overlapping tweens from competing for the visual-root rotation.
    _visual_root.rotation = Vector3.ZERO # Starts each hit reaction from the stable authored upright pose.
    var reaction_direction: float = -1.0 if hit.normal.x >= 0.0 else 1.0 # Chooses a deterministic lean direction from the contacted surface normal.
    var reaction_rotation: Vector3 = Vector3(0.0, 0.0, HIT_REACTION_ANGLE * reaction_direction) # Builds the small lateral lean used as visible hit feedback.
    _reaction_tween = create_tween() # Creates a node-bound tween that is automatically discarded with the dummy.
    _reaction_tween.set_trans(Tween.TRANS_QUAD) # Uses smooth acceleration so the straw body feels flexible rather than mechanical.
    _reaction_tween.set_ease(Tween.EASE_OUT) # Makes the initial impact response quick and readable.
    _reaction_tween.tween_property(_visual_root, "rotation", reaction_rotation, HIT_REACTION_OUT_DURATION) # Pushes the visible dummy away from the hit.
    _reaction_tween.tween_property(_visual_root, "rotation", Vector3.ZERO, HIT_REACTION_RETURN_DURATION).set_ease(Tween.EASE_IN_OUT) # Settles the dummy back upright after impact.

func _refresh_health_presentation() -> void: # Synchronizes the floating billboard health bar and numeric readout with authoritative health state.
    var health_ratio: float = _health.get_health_ratio() # Reads normalized current health for horizontal bar scaling.
    _health_bar_fill.scale = Vector3(health_ratio, 1.0, 1.0) # Shrinks only the foreground bar width while preserving authored height and depth.
    _health_bar_fill.position.x = -HEALTH_BAR_FILL_HALF_WIDTH * (1.0 - health_ratio) # Shifts the shrinking fill left so health depletes from right to left.
    _health_bar_fill.visible = health_ratio > 0.0 # Hides the foreground completely when no health remains.
    var current_health: int = roundi(_health.get_current_health()) # Converts the display value to a clean whole-number combat readout.
    var maximum_health: int = roundi(_health.get_maximum_health()) # Converts the maximum value to the same clean whole-number format.
    _health_text.text = "%d / %d" % [current_health, maximum_health] # Displays current and maximum health directly above the billboard bar.
    if _health.is_dead(): # Detects the temporary defeated state used by the reusable training target.
        _health_text.text += "  RESETTING" # Makes the automatic restoration behavior explicit to the player.
    _displayed_health_revision = _health.get_revision() # Records the rendered revision so unchanged health does not rebuild presentation each frame.
