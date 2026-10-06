# Wayshrines

Low-poly stone arches, bronze carvings, faceted floating crystals and animated rune lights appear on dry, gently sloped ground. Three colour/crest variants use deterministic sampling: an 85% candidate chance per 1536-metre cell, up to 32 attempts, and at most one shrine per cell. Their entire six-metre footprint rejects water, lava, camps, towns, cottages and wilderness roads; sampled height variation must stay within 1.8 metres. Vegetation protects a nine-metre clearing, with extra padding for trees and grass patches.

Look at a shrine within 3.5 metres and press E / controller X to awaken it. Awakening brightens its crystal and runes. The travel menu lists only other activated shrines, with distances; the first discovery explains that another shrine is needed. Choose a destination and press Travel or activate the list entry. Escape / E closes the menu. Interaction respects solid cover and other foreground interactables.

Discoveries use absolute cell identities and persist through streaming and saved games. The save system restores the registry before shrine streaming begins. The streamer retains at most nine cell entries and builds one per frame. Location caches are bounded to 128 cells.

Travel is available at a visible nearby shrine in the active overworld, for living players. Current and locked destinations are rejected. Player movement pauses, the floating origin rebases, destination terrain collision is built, and a capsule sweep resolves safe arrival beside the shrine before movement resumes. If the destination collision cannot be resolved, the player returns to the source. Equipped inventory, health, affection and activated shrine records are retained.

Checks: `godot --headless --path . --script world/wayshrines/tests/check_wayshrines.gd`.
