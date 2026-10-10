extends RefCounted # Keep authored radiant event content separate from scheduling and interface state.
class_name RadiantEventPhrases # Describe consent-based spontaneous conversations.

const BATTLE_CHALLENGE: String = "battle_challenge" # Identify the first supported radiant encounter.
const CHALLENGES: Array[String] = [ # Supply varied prewritten invitations without implying consent.
    "Good {time_of_day}, traveller. You look capable. Will you face me in a battle?", # Invite an explicit player decision.
    "I have been looking for someone to test my strength against. Will you fight me?", # Offer a different challenge opening.
    "A moment, traveller! I challenge you to battle. Do you accept?", # Explain why the approaching NPC stopped the player.
    "Let us see who is stronger. Will you agree to a battle?", # Keep hostility conditional on acceptance.
] # Finish the authored challenge alternatives.

static func definition(kind: String, variation: int) -> Dictionary: # Resolve supported event content before reserving an NPC.
    if kind != BATTLE_CHALLENGE: # Reject unknown event identifiers without opening incomplete menus.
        return {} # Leave gameplay ownership unchanged.
    return {"opening": CHALLENGES[posmod(variation, CHALLENGES.size())], "accept": "I Accept Your Challenge", "decline": "No, Thank You", "hostile_on_accept": true} # Declare authored responses and the accepted event effect.
