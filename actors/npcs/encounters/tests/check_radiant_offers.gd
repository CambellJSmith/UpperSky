extends SceneTree # Verify real offer settlement, failure atomicity and encounter variety.

const GAME: PackedScene = preload("res://application/game/game.tscn") # Resolve equipment dependencies before isolated inventory classes.

func _initialize() -> void: # Wait for normal autoload initialization.
    run.call_deferred() # Exercise the production economy in a live tree.

func count(storage: Object, id: StringName) -> int: # Read actual held quantities through the shared storage API.
    var stack: InventoryStack = RadiantOfferService.find_item(storage, id) # Find the authoritative stack.
    return stack.get_quantity() if stack != null else 0 # Treat missing goods as zero.

func actor() -> Villager: # Create an isolated actor with genuine social and loot state.
    var npc: Villager = Villager.new() # Avoid unnecessary model and animation setup for economy assertions.
    npc._loot_record = {"inventory": LootStorage.new(), "npc_id": "offer_test"} # Supply the same storage contract as generated NPCs.
    return npc # Let each test own an independent one-time encounter.

func add(inventory: PlayerInventory, id: StringName, quantity: int) -> void: # Fund a player with real catalogue metadata.
    var item: InventoryStack = RadiantItemCatalogue.item(id) # Resolve actual item weight and category.
    assert(inventory.try_add_item(id, item.get_display_name(), item.get_unit_weight(), quantity, item.get_category())) # Require all test funding to respect production inventory rules.

func run() -> void: # Check every authored exchange and important failure path.
    var composition: PackedScene = load("res://application/game/game.tscn") # Resolve normal equipment resource dependencies.
    assert(composition != null) # Require integrated game scripts to compile.
    var vitals: PlayerVitals = PlayerVitals.new() # Supply the authoritative carrying capacity.
    var inventory: PlayerInventory = PlayerInventory.new() # Use production player inventory mutation.
    inventory.initialize(vitals) # Bind live stamina-derived weight limits.
    for kind: String in RadiantOfferCatalogue.kinds(): # Exercise every authored noncombat offer.
        var npc: Villager = actor() # Isolate stock and completion state.
        var quote: Dictionary = RadiantOfferService.prepare(npc, kind) # Prepare actual promised stock.
        assert(not quote.is_empty()) # Require every selectable encounter to be valid.
        var payment_id: StringName = StringName(quote.take_id) # Resolve required player goods.
        var reward_id: StringName = StringName(quote.give_id) # Resolve promised NPC goods.
        if int(quote.take_quantity) > 0: # Fund the exact requested payment.
            add(inventory, payment_id, int(quote.take_quantity)) # Use real currency or goods.
        var before_payment: int = count(inventory, payment_id) # Snapshot the payer's stock.
        var before_reward: int = count(inventory, reward_id) # Snapshot the recipient's stock.
        var npc_payment: int = count(npc.get_social_record().inventory, payment_id) # Snapshot the NPC payment destination.
        var rendered: Dictionary = RadiantOfferService.render(quote, {"species": "human", "time_of_day": "morning"}) # Check missing-city fallback and exact item substitution.
        assert(not "{" in str(rendered.opening) and not "{" in str(rendered.accept)) # Reject unresolved authored variables.
        var result: Dictionary = RadiantOfferService.accept(npc, inventory) # Settle one explicitly accepted offer.
        assert(result.success and not result.hostile) # Keep every added event peaceful.
        assert(count(inventory, payment_id) == before_payment - int(quote.take_quantity)) # Transfer the complete real payment.
        assert(count(inventory, reward_id) == before_reward + int(quote.give_quantity)) # Deliver the complete promised goods.
        assert(count(npc.get_social_record().inventory, payment_id) == npc_payment + int(quote.take_quantity)) # Give donated or sold goods to the actual NPC.
        var revision: int = inventory.get_revision() # Snapshot a completed player's inventory.
        assert(not RadiantOfferService.accept(npc, inventory).success) # Reject duplicate acceptance.
        assert(inventory.get_revision() == revision) # Prevent repeated rewards or charges.
        assert(RadiantOfferService.prepare(npc, kind).is_empty()) # Prevent reopening a completed gift.
        npc.free() # Release the isolated event actor.
    var poor: PlayerInventory = PlayerInventory.new() # Exercise an unfunded sale independently.
    poor.initialize(vitals) # Bind genuine carrying rules.
    var seller: Villager = actor() # Supply a real merchant's stock.
    RadiantOfferService.prepare(seller, "boot_money") # Prepare bread for five coins.
    assert(not RadiantOfferService.accept(seller, poor).success) # Reject missing currency.
    assert(poor.get_revision() == 0 and not seller.get_social_record().get("radiant_completed", false)) # Keep a failed offer pending without mutation.
    add(poor, &"coins", 5) # Supply the complete price.
    vitals.set_maximum_stamina(0.5) # Make the offered bread too heavy after payment.
    assert(not RadiantOfferService.accept(seller, poor).success) # Reject excess final carried weight.
    assert(count(poor, &"coins") == 5 and count(poor, &"bread") == 0) # Preserve payment after failed receipt.
    var barter: Villager = actor() # Test capacity after outgoing goods leave.
    RadiantOfferService.prepare(barter, "traveller_barter") # Offer lighter linen for heavier bread.
    var full: PlayerInventory = PlayerInventory.new() # Use an exactly full inventory.
    full.initialize(vitals) # Share the live half-kilogram limit.
    add(full, &"bread", 2) # Fill capacity before the exchange.
    assert(RadiantOfferService.accept(barter, full).success) # Allow an exchange whose final weight fits.
    assert(count(full, &"bread") == 0 and count(full, &"linen") == 3) # Transfer both sides of the barter.
    vitals.set_maximum_stamina(100.0) # Restore ordinary capacity for metadata conflict checks.
    var conflict: Villager = actor() # Exercise incompatible NPC payment metadata.
    RadiantOfferService.prepare(conflict, "boot_money") # Prepare an otherwise valid sale.
    assert(conflict.get_social_record().inventory.try_add_item(&"coins", "Coins", 1.0, 1, InventoryCategory.Type.MISC)) # Introduce incompatible existing destination stock.
    var conflict_revision: int = poor.get_revision() # Snapshot a fully funded payer.
    assert(not RadiantOfferService.accept(conflict, poor).success) # Reject the incompatible destination before charging.
    assert(poor.get_revision() == conflict_revision and count(poor, &"coins") == 5) # Preserve both player payment and inventory revision.
    conflict.free() # Release conflicting NPC storage.
    var missing: Villager = actor() # Exercise promised stock disappearing before consent.
    RadiantOfferService.prepare(missing, "boot_money") # Create the original stock-backed quote.
    missing.get_social_record().inventory.remove_item(&"bread", 3) # Reproduce an external source stock change.
    assert(not RadiantOfferService.accept(missing, poor).success) # Revalidate available goods at acceptance.
    assert(poor.get_revision() == conflict_revision) # Retain all player goods after a missing-stock failure.
    missing.free() # Release the depleted merchant.
    var director: RadiantEventDirector = RadiantEventDirector.new() # Exercise the real shuffled selection bag.
    director._rng.seed = 789 # Make variety assertions reproducible.
    var previous: String = "" # Track immediate repetition across bag boundaries.
    for round_index: int in range(3): # Cover several complete content cycles.
        var seen: Array[String] = [] # Track coverage within each cycle.
        for index: int in range(RadiantEventPhrases.kinds().size()): # Consume one full pool.
            var kind: String = director._choose_kind() # Select through production scheduling logic.
            assert(kind != previous and not seen.has(kind)) # Prevent immediate repeats and duplicates within a cycle.
            seen.append(kind) # Record this cycle's unique event.
            previous = kind # Retain the boundary predecessor.
        assert(seen.size() == 17) # Require all sixteen additions and the existing battle challenge.
    director._actor = seller # Supply the accepted friendly actor for state transition checks.
    director._resolved(seller, true) # Simulate the dialogue completion signal.
    assert(director._state == RadiantEventDirector.State.LEAVING) # Keep a successful friendly exchange out of combat.
    director.free() # Release scheduler resources.
    seller.free() # Release merchant stock.
    barter.free() # Release barter stock.
    full.free() # Release barter inventory.
    poor.free() # Release failed-sale inventory.
    inventory.free() # Release successful-offer inventory.
    vitals.free() # Release shared capacity state.
    print("RADIANT_OFFERS_OK") # Report all concrete economy and selection assertions passing.
    quit() # Finish the bounded regression.
