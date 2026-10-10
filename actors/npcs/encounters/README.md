# Radiant NPC Events

The first event is a battle challenge from a male human, female human or orc. A single director schedules one actor at a time during grounded outdoor gameplay. Initial encounters wait for eligible play time; subsequent events use a longer randomized cooldown. Menus, loading, interiors, swimming, flying, climbing and ferry travel postpone spawning.

Placement proposes one candidate behind the player's current camera. Every actor-bound corner must be behind the camera plane. The entire initial approach requires dry non-lava terrain, gentle height changes, registered ground collision and body clearance. Failed candidates retry over time rather than forcing a spawn or scanning a region in one frame.

The actor uses ordinary Villager collision, grounding, run animation and combat. The director updates its destination at a bounded cadence, requires arrival and line of sight, then opens the composed dialogue menu. An obstructed or unsuccessful pursuit times out. A new menu can wait without stealing another interface's input.

The challenge begins at neutral affection. Accept explicitly sets AffectionState.HATE synchronously and closes the menu before normal combat resumes. Decline, cancel and ordinary close preserve affection and send the actor back toward its original spawn. Actors retire only while wholly behind the current camera and sufficiently far away; nearby battle corpses remain available for ordinary loot. No additional combat implementation is introduced.

`radiant_event_phrases.gd` owns authored event content and acceptance effects. Opening text supports the existing DialogueContext variables. `radiant_spawn_sampler.gd` owns placement validation; `radiant_event_director.gd` owns scheduling and lifecycle. Event actors use session-local identities with existing loot and affection records, and are not reconstructed as an active radiant encounter after loading a save. Retired actors release their transient social records; expired saved radiant records are discarded after startup so repeated events do not grow unreachable record storage.

Regression: `godot --headless --path . --script actors/npcs/encounters/tests/check_radiant_events.gd`. The controlled world has real registered collision and runs real Villager movement; only mouse-capture readiness uses a headless display adapter. Interactive presentation and physical controller operation still require an in-game check.

## Offers, Gifts And Help

The shuffled encounter pool now includes the battle challenge plus sixteen peaceful encounters. Every type appears once per shuffled round, with no immediate repeats across rounds. Merchants sell bread for new boots, a pickaxe for wagon repairs, a sword for a journey home, a knife for an upgrade, and linen for tent supplies. Buyers purchase food or cloth; camp cooks and tailors barter those goods. Generous travellers offer bread, a knife, coins or cloth freely. Other travellers ask for coins or food, or share real nearby-city information.

The consent button names the exact goods and price. Accepted exchanges move real items between player and NPC inventories once, validate full payment and final carrying weight after outgoing goods leave, and leave failed offers pending with an explanation. Friendly outcomes increase affection and show a confirmation before the NPC departs peacefully. Only accepting a battle challenge makes the NPC hostile. Declining or closing an unfinished offer transfers nothing. Equipment rewards use the existing equipment catalogue.

Run `godot --headless --path . --script actors/npcs/encounters/tests/check_radiant_offers.gd` to check all peaceful transactions, insufficient funds, capacity rejection, net-weight barter, duplicate payout prevention and shuffled encounter coverage.
