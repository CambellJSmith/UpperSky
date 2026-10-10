extends RefCounted # Keep authored conversation content independent of UI and world lookup.
class_name DialoguePhrases # Provide reusable topic definitions and template expansion.

const TOPICS: Dictionary = { # Define the player-authored conversation choices.
    "greeting": "Hello.", # Start a friendly exchange.
    "city": "Is There A City Nearby?", # Ask for a real known city.
    "work": "What Do You Do Here?", # Ask about the speaker's occupation.
    "time": "How Is Your Day Going?", # Ask about the current world time.
    "advice": "Any Advice For A Traveller?", # Ask for practical world guidance.
} # Finish the topic catalogue.
const LINES: Dictionary = { # Store authored phrases with named world-context substitutions.
    "greeting": ["Good {time_of_day}, traveller.", "This {species} can always spare a moment for conversation.", "Hello there. What brings you this way?", "Well met. It is good to have someone to talk to."], # Vary ordinary greetings.
    "reserved": ["Good {time_of_day}. Keep this brief, please.", "I will hear you out, traveller.", "You may speak, but mind your manners."], # Reflect a poor existing relationship without changing it.
    "friendly": ["Good {time_of_day}! Always a pleasure to see you.", "Come, friend. What is on your mind?", "There you are! I have time for a chat."], # Reflect an established friendly relationship.
    "city": ["{city_name} lies {city_direction}, about {city_distance} from here.", "Looking for a city? Try {city_name}. It is {city_direction}, roughly {city_distance} away.", "I know of {city_name}, {city_distance} to the {city_direction}."], # Reference authoritative generated city coordinates and names.
    "current_city": ["You are already in {city_name}, traveller.", "This is {city_name}. Take your time looking around.", "Welcome to {city_name}. You have found your city."], # Recognize a speaker inside the actual city space.
    "unknown_city": ["I cannot point you towards a city with confidence.", "I do not know a city near here. Ask again further along the road.", "I would rather admit I do not know than send you the wrong way."], # Avoid fabricated place names when context is unavailable.
    "camper": ["I am staying at this camp. A tent and a little company suit me well.", "Mostly I walk around the camp and keep close to my tent.", "This camp is home for now. I am in no hurry to leave."], # Describe an actual camp resident's activity.
    "traveller": ["I travel the roads between settlements.", "I am on the road. There is always another place to visit.", "Walking, resting, then walking again. That is a traveller's life."], # Describe road traveller behavior.
    "guard": ["I keep watch and patrol the streets.", "I am on patrol. Speak quickly, and keep out of trouble.", "Someone has to keep an eye on these streets."], # Describe city and village patrols.
    "resident": ["I live around here. Most days I take a walk and mind my business.", "These streets are familiar to me. I like to stretch my legs.", "I spend my time close to home."], # Describe ordinary residents without inventing services.
    "work": ["I am a {occupation}. That keeps me occupied.", "You will usually find me tending to my own affairs.", "A little walking and a little conversation make a decent day."], # Cover other human occupations safely.
    "time": ["It is {clock_time} already. The {time_of_day} is passing quickly.", "A quiet {time_of_day} so far. I hope yours is going well.", "There is still time for a chat this {time_of_day}."], # Use the live day and night clock.
    "unknown_time": ["I have lost track of the time, but I can spare a moment.", "A conversation makes the day pass more pleasantly."], # Support spaces without a world clock.
    "advice": ["Watch your footing near water. A shoreline can hide deep ground.", "A bedroll at a camp can give you a proper rest.", "Discover wayshrines as you travel. Once awakened, they can help you return.", "Keep an eye on what you carry. Too much weight makes travel harder.", "Keep away from lava. No destination is worth walking through it."], # Offer mechanics that actually exist in the game.
} # Finish the authored phrase library.

static func response(topic: String, context: Dictionary, variation: int) -> String: # Select a valid context-aware phrase without evaluating arbitrary code.
    var key: String = topic # Begin with the requested topic.
    if topic == "greeting": # Tailor the greeting to existing affection.
        var affection: float = float(context.get("affection", AffectionState.NEUTRAL)) # Read the speaker's relationship context.
        key = "reserved" if affection < AffectionState.NEUTRAL - 40.0 else "friendly" if affection >= AffectionState.NEUTRAL + 40.0 else "greeting" # Select a relationship-appropriate greeting.
    elif topic == "city": # Require real city information before substituting place details.
        key = "current_city" if context.get("in_city", false) else "city" if context.has("city_name") else "unknown_city" # Avoid inventing missing world facts.
    elif topic == "work": # Prefer occupation-specific statements where available.
        var role: String = str(context.get("role", "")) # Resolve the actual NPC role.
        key = "camper" if role == "camper" else "traveller" if role == "traveller" else "guard" if "knight" in role else "resident" if "resident" in role or role == "homesteader" else "work" # Match authored lines to actual behavior.
    elif topic == "time" and not context.has("clock_time"): # Handle scenes with no clock.
        key = "unknown_time" # Select an honest fallback.
    if not LINES.has(key): # Reject unsupported topics safely.
        return "What Would You Like To Talk About?" # Keep the conversation usable after content changes.
    var lines: Array = LINES[key] # Read the valid authored alternatives.
    var template: String = str(lines[posmod(variation, lines.size())]) # Rotate alternatives deterministically.
    return template.format(context) # Substitute only the supplied named context values.
