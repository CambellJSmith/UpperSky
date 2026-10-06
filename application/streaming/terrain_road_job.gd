extends RefCounted
class_name TerrainRoadJob
signal completed
var link: Dictionary
var result: Dictionary
var _mutex := Mutex.new()
var _cancelled := false
var seamless := false

func cancel():
    _mutex.lock()
    _cancelled = true
    _mutex.unlock()

func is_cancelled() -> bool:
    _mutex.lock()
    var value := _cancelled
    _mutex.unlock()
    return value

func _init(definition: Dictionary, use_seamless: bool = false):
    # Only immutable scalar/array data crosses the worker boundary. Procedural
    # samplers and their mutable caches belong exclusively to this worker.
    link = {"key":definition.key,"start":definition.start,"end":definition.end,"kind":definition.kind,"a":{"position":definition.a.position},"b":{"position":definition.b.position}}
    seamless = use_seamless

func generate() -> Dictionary:
    if is_cancelled(): return {}
    var terrain := create_sampler()
    var network := WorldPathNetwork.new(terrain,false)
    network.cancel_check = is_cancelled
    var road: Dictionary = network._road.call(link,null,false)
    terrain.free()
    return road

func create_sampler() -> InfiniteTerrain:
    var terrain: InfiniteTerrain = SeamlessInfiniteTerrain.new() if seamless else InfiniteTerrain.new()
    terrain._height_sampler = SeamlessTerrainHeightSampler.new() if seamless else TerrainHeightSampler.new()
    terrain._water_level_sampler = SeamlessTerrainWaterLevelSampler.new() if seamless else TerrainWaterLevelSampler.new()
    return terrain

func accept(road: Dictionary):
    result = road
    completed.emit()
