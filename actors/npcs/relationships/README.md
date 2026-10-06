# Player affection

Every NPC owns an AffectionState towards the player: 0 is pure hate, 100 neutral, and 200 perfect adoration. Humans start at 100, orcs at 50, and demons, zombies and fish-men at 0. Ghosts start at 25. Unlisted species default to 100.

NPCs expose get_affection(), set_affection(value) and change_affection(amount). The affection state also exposes score and changed(previous, current). Values clamp to 0–200; non-finite inputs are ignored. Signals fire only when the score changes.

Villagers, wilderness patrols and cave NPCs retain the score in their session record when unloaded and respawned, including after death. Starting values apply only once. The save system stores and restores these records alongside health and loot across game sessions.

Affection at or below 10 now triggers nearby NPC combat; raising it above 10 cancels combat. Scores do not change automatically from actions yet; dialogue, gifts or other gameplay can call change_affection().
