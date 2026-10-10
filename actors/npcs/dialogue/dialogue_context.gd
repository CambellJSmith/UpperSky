extends RefCounted # Isolate world facts from authored phrases and interface state.
class_name DialogueContext # Build a factual snapshot only when a conversation starts.

static func build(npc: Villager, terrain: InfiniteTerrain, cycle: DayNightCycle) -> Dictionary: # Resolve shared context for humans and orcs in every populated space.
    var context: Dictionary = {"species": npc.get_relationship_species(), "role": npc.role, "occupation": npc.role.replace("_", " "), "affection": npc.get_affection(), "time_of_day": "day"} # Use the actor's actual social and occupational state.
    if cycle != null: # Use the actual world clock when present.
        var hour: float = cycle.get_time_of_day_hours() # Resolve the current world hour.
        context["clock_time"] = cycle.get_formatted_time() # Preserve the game's time display format.
        context["time_of_day"] = "night" if DayNightCycle.is_night_hour(hour) else "morning" if hour < 12.0 else "afternoon" if hour < 17.0 else "evening" # Choose a natural greeting from the world clock.
    var ancestor: Node = npc.get_parent() # Inspect composition for an active city interior.
    while ancestor != null: # Support actors nested in city containers.
        if ancestor is CitySpace: # Prefer the actual city containing the speaker.
            var city: CitySpace = ancestor as CitySpace # Access the authoritative city definition.
            context["city_name"] = CityGeometry.city_name(city.definition.seed) # Match existing generated city naming.
            context["in_city"] = true # Describe the city as the current location.
            return context # Avoid applying exterior coordinates to city-local actors.
        ancestor = ancestor.get_parent() # Continue through composed actor parents.
    if npc.get_dialogue_terrain() != terrain or terrain == null: # Avoid exterior geography for caves and unrelated spaces.
        return context # Retain valid social facts without fabricated geography.
    var point: Vector2 = Vector2(npc.world_position.x, npc.world_position.z) # Use absolute coordinates so origin shifts cannot change facts.
    var city: Dictionary = SettlementSampler.for_terrain(terrain).known_nearby_city(point) # Read generated definitions without starting an expensive regional search.
    if not city.is_empty(): # Substitute geography only when a real city is known.
        var offset: Vector2 = (city.position as Vector2) - point # Resolve the city's relative position.
        context["city_name"] = CityGeometry.city_name(city.seed) # Reuse the exact city naming contract.
        context["city_direction"] = direction(offset) # Describe cardinal direction from the speaker.
        context["city_distance"] = "%.1f km" % (offset.length() / 1000.0) if offset.length() >= 1000.0 else "%d metres" % roundi(offset.length()) # Format truthful approximate travel distance.
    return context # Keep the snapshot bounded to one conversation.

static func direction(offset: Vector2) -> String: # Match world compass north to decreasing world Z.
    var directions: Array[String] = ["east", "southeast", "south", "southwest", "west", "northwest", "north", "northeast"] # Order direction labels around the horizontal plane.
    return directions[posmod(roundi(offset.angle() / (PI / 4.0)), directions.size())] # Select the nearest compass heading.
