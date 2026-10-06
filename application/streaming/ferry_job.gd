extends RefCounted
class_name FerryJob
var cell: Vector2i
var seamless: bool
var mutex := Mutex.new()
var stopped := false
func _init(coordinate: Vector2i, use_seamless: bool): cell = coordinate; seamless = use_seamless
func cancel():
    mutex.lock()
    stopped = true
    mutex.unlock()
func is_cancelled() -> bool:
    mutex.lock()
    var value := stopped
    mutex.unlock()
    return value
func generate() -> Array[Dictionary]:
    var task := TerrainRoadJob.new({"key":"ferry","start":Vector2.ZERO,"end":Vector2.ZERO,"kind":"connection","a":{"position":Vector2.ZERO},"b":{"position":Vector2.ZERO}},seamless)
    var terrain := task.create_sampler()
    var sampler := FerrySampler.new(terrain)
    sampler.cancelled = is_cancelled
    var result := sampler.sample(cell)
    terrain.free()
    return result
