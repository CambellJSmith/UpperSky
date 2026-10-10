extends RefCounted # Share bounded cache eviction between deterministic samplers.
class_name CacheEviction # Retain useful samples when cache capacity is reached.

static func make_room(cache: Dictionary, limit: int) -> void: # Evict a small oldest batch instead of flushing all entries.
    if cache.size() < limit: # Keep a cache below its capacity unchanged.
        return # Avoid allocating a key snapshot for ordinary inserts.
    var keys: Array = cache.keys() # Snapshot insertion order only at an eviction boundary.
    var count: int = maxi(1, limit / 8) # Amortize eviction while retaining most existing samples.
    for index: int in range(mini(count, keys.size())): # Visit the oldest retained entries.
        cache.erase(keys[index]) # Release only the eviction batch.
