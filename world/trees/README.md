# Low-poly trees

Eight families have two deterministic authored forms each: oak, birch, beech, Scots pine, spruce, willow, wind-bent oak and dead snag. Tapered polygon trunks fork into supported crowns; visible roots, birch bark markings, conifer branch whorls, willow hanging foliage and broken dead limbs distinguish the silhouettes. Bark and leaf colours use flat vertex shading without textures.

`TreeGeometry` builds 48 shared meshes (16 forms × three distance levels). Full-detail trees use 241–934 triangles; distant trees use 94–232. Chunk MultiMeshes group instances by form, preserving the family at every distance. Bounds come from the complete transformed geometry. Two shared capsule segments per form follow the trunk skeleton, with each instance's yaw and scale; foliage and small branches remain non-solid.

Species selection forms broad groves, favours conifers at altitude and places willows on moist ground near water. Dead snags are occasional (3.5% of candidates). Existing density, biome, path and camp exclusions remain; settlement clearings have additional canopy room. Trunk bases use the rendered terrain triangle height.

Checks: `godot --headless --path . --script world/trees/tests/check_trees.gd` and `world/trees/tests/check_distribution.gd`. These verify geometry, deterministic forms, detail reduction, winding, bounds, bent/scaled trunk collisions, clearing reservations and grounded placement.
