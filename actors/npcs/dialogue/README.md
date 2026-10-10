# NPC Dialogue

Living peaceful human and orc NPCs support the existing Interact action. The authored menu offers greeting, nearby city, occupation, time of day and travel advice. Mouse and keyboard focus work through native Buttons; StickLeft North/South navigates, Button A selects, and Button B exits. Interact, Inventory and UI Cancel also close the conversation.

`dialogue_phrases.gd` owns prewritten alternatives and named substitutions. `dialogue_context.gd` resolves factual context once at conversation opening. The UI scene contains the controls; `dialogue_interaction.gd` owns targeting and conversation lifetime. Villager exposes exclusive weak conversation ownership and keeps combat updating while holding route movement.

Supported context keys: species, role, occupation, affection, time_of_day, optional clock_time, optional city_name, city_direction, city_distance, and in_city. Templates requiring optional facts must use a matching fallback branch. Names use CityGeometry.city_name, the same function as the existing city system. Exterior city knowledge selects the nearest already generated city within the surrounding region. It does not synchronously generate a regional search when opening a menu. Missing city knowledge has an explicit honest fallback; city-local speakers use their actual CitySpace definition.

To add alternatives, extend the corresponding LINES collection. To add a player topic, add its title to TOPICS, its content and eligibility branch to response, and an authored Button under the menu's Topics container. Keep topic order and scene button order aligned.

Headless regression: `godot --headless --path . --script actors/npcs/dialogue/tests/check_dialogue.gd`. Its display-only subclass bypasses mouse capture readiness because the dummy display server cannot capture a mouse; actor eligibility, targeting, state, content and authored menu controls remain production code. Visual appearance and physical controller operation require an interactive game run.
