# First-person arms

`rigged_arm.glb` is the user-supplied `Meshy_AI_textured_low_poly_arm_1005180455_texture.glb`, copied without modifying its geometry, 21-bone skin or embedded textures. Godot extracts the three embedded JPG textures beside it during import. The source has a rig but no animation clips.

`FirstPersonArms` instances the model twice under the player's camera, mirroring one instance for the left arm. Shoulder origins sit below the camera. An analytic two-bone solver poses the shoulder and elbow; the finger bones curl and the thumb opposes the fingers around the handle. The arms follow the equipped item's existing slash, chop or thrust motion. A small shoulder adjustment maintains reach during cross-body attacks. No arm collision bodies are created.

The right hand holds swords and knives. Chop-profile axes, tools and the greatsword use both hands and a more central equipment-mount position. Unequipping releases the grip and restores relaxed hands. The existing melee ray, contact timing and cooldown remain authoritative.

Grip offsets are in the equipped item's local space: right hand Y = -0.045, supporting hand Y = 0.22 on long shafts or -0.17 on the greatsword hilt. These match the current low-poly equipment collection. New equipment with a different handle origin may need an additional grip profile.

Meshes retain the supplied textured material, use expanded animated bounds and do not cast first-person arm shadows into the world. They use the main camera's ordinary depth rendering, as existing held equipment does.

Run `godot --headless --path . --script actors/player/arms/tests/check_arms.gd` to check both rigs, every equipment definition, animated reach, finite poses, swapping and unequip cancellation.
