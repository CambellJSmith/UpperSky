extends RefCounted # Own one-time encounter stock preparation and atomic inventory settlement.
class_name RadiantOfferService # Apply concrete radiant rewards without putting economy logic in the menu.

static func find_item(storage: Object, id: StringName) -> InventoryStack: # Resolve a real stack through the shared read-only inventory API.
    for index: int in range(storage.get_stack_count()): # Inspect existing source or destination stock once per decision.
        var stack: InventoryStack = storage.get_stack_at(index) # Retain strongly typed immutable item metadata.
        if stack.get_item_id() == id: # Match the quoted stable identifier.
            return stack # Return the actual held stock rather than a fabricated quantity.
    return null # Report goods that the holder does not possess.

static func prepare(npc: Villager, kind: String) -> Dictionary: # Create one stable quote and back offered goods with real NPC stock.
    var record: Dictionary = npc.get_social_record() # Reuse the actor's existing persistent social and inventory state.
    if record.get("radiant_completed", false): # Prevent a completed event actor from issuing duplicate gifts or payments.
        return {} # Keep one encounter completion per spawned actor.
    if record.has("radiant_offer"): # Preserve exact terms when a conversation is retried.
        var existing: Dictionary = record.radiant_offer # Resolve the already prepared quote.
        return existing.duplicate(true) if existing.kind == kind else {} # Reject switching this actor to a different reward after stock preparation.
    var quote: Dictionary = RadiantEventPhrases.definition(kind, hash(str(record.get("npc_id", npc.name)))) # Resolve authored content once for this event identity.
    if quote.is_empty(): # Reject unsupported event content before creating stock.
        return {} # Leave the actor's inventory untouched.
    var give_id: StringName = StringName(quote.get("give_id", "")) # Resolve the quoted outgoing NPC item.
    var quantity: int = int(quote.get("give_quantity", 0)) # Resolve the complete promised quantity.
    if quantity > 0: # Back a concrete reward or sale with the NPC's own loot storage.
        var item: InventoryStack = RadiantItemCatalogue.item(give_id) # Reuse real item metadata and usable equipment definitions.
        if item == null: # Reject unsupported reward items.
            return {} # Avoid offering goods that cannot enter player inventory.
        var storage: LootStorage = record.inventory # Resolve the actual actor-owned stock.
        var held: InventoryStack = find_item(storage, give_id) # Check whether ordinary NPC loot already supplies the offer.
        var needed: int = maxi(0, quantity - (held.get_quantity() if held != null else 0)) # Add only missing promised stock.
        if needed > 0 and not storage.try_add_item(give_id, item.get_display_name(), item.get_unit_weight(), needed, item.get_category()): # Respect existing inventory metadata while preparing stock.
            return {} # Reject a conflicting stock definition without opening a misleading offer.
    record["radiant_offer"] = quote.duplicate(true) # Store stable terms independently of rendered menu text.
    return quote # Return an independently renderable copy of the prepared quote.

static func render(quote: Dictionary, context: Dictionary) -> Dictionary: # Expand item and world terms without altering the actor's stored transaction.
    var result: Dictionary = quote.duplicate(true) # Isolate display text from settlement state.
    var terms: Dictionary = context.duplicate() # Preserve ordinary city and time substitutions.
    for prefix: String in ["give", "take"]: # Resolve outgoing and required item quantities consistently.
        var quantity: int = int(quote.get(prefix + "_quantity", 0)) # Read the exact quoted amount.
        if quantity > 0: # Substitute concrete item terms only when an exchange requires them.
            var item: InventoryStack = RadiantItemCatalogue.item(StringName(quote[prefix + "_id"])) # Resolve the game's authoritative item description.
            terms["reward" if prefix == "give" else "payment"] = RadiantItemCatalogue.quantity_label(item, quantity) # Show the exact goods or price in every authored control.
    result["opening"] = str(quote.opening).format(terms) # Resolve real world and exchange information in the invitation.
    result["accept"] = str(quote.accept).format(terms) # Make the player's consent label display exact terms.
    if quote.kind == "local_news": # Use known geography only when the speaker has a real city context.
        result["success"] = DialoguePhrases.response("city", context, 0) + " Discover wayshrines as you travel; awakened shrines can help you return." # Share factual local information with an honest missing-city fallback.
    if result.has("title"): # Present a natural speaker role rather than an implementation identifier.
        result["title"] = (str(context.get("species", "")) + " " + str(result.title)).capitalize() # Include the actual human or orc species in the encounter heading.
    return result # Return only the per-conversation display snapshot.

static func accept(npc: Villager, player_inventory: PlayerInventory) -> Dictionary: # Settle the actor's stored offer once after explicit consent.
    var record: Dictionary = npc.get_social_record() # Resolve authoritative quote ownership and completion state.
    if record.get("radiant_completed", false) or not record.has("radiant_offer"): # Reject stale or unprepared decisions.
        return {"success": false, "message": "This Offer Is No Longer Available."} # Never pay out the same event actor twice.
    var quote: Dictionary = record.radiant_offer # Use stored terms rather than trusting rendered UI content.
    if quote.get("hostile_on_accept", false): # Preserve the original battle challenge's immediate effect.
        npc.set_affection(AffectionState.HATE) # Trigger ordinary hostility synchronously upon consent.
        record["radiant_completed"] = true # Prevent stale or reopened challenge decisions.
        return {"success": true, "hostile": true, "message": "Challenge Accepted."} # Let the controller close immediately and resume combat.
    var storage: LootStorage = record.inventory # Resolve the source that actually owns offered rewards.
    var give_id: StringName = StringName(quote.get("give_id", "")) # Resolve the reward's stable item identifier.
    var give_quantity: int = int(quote.get("give_quantity", 0)) # Resolve the promised outgoing quantity.
    var take_id: StringName = StringName(quote.get("take_id", "")) # Resolve the required payment or donated goods.
    var take_quantity: int = int(quote.get("take_quantity", 0)) # Resolve the required outgoing player amount.
    var reward: InventoryStack = find_item(storage, give_id) if give_quantity > 0 else null # Read real stocked goods rather than minting a menu reward.
    if give_quantity > 0 and (reward == null or reward.get_quantity() < give_quantity): # Revalidate stock after any other actor inventory changes.
        return {"success": false, "message": "I No Longer Have The Promised Goods."} # Keep player payment intact if stock is missing.
    var payment: InventoryStack = find_item(player_inventory, take_id) if take_quantity > 0 else null # Resolve actual player currency or requested goods.
    if take_quantity > 0 and (payment == null or payment.get_quantity() < take_quantity): # Require the full advertised payment.
        var item: InventoryStack = RadiantItemCatalogue.item(take_id) # Describe the required goods consistently with the quote.
        return {"success": false, "message": "You Need %s To Accept This Offer." % RadiantItemCatalogue.quantity_label(item, take_quantity)} # Explain why the exchange remains pending without charging anything.
    var existing_payment: InventoryStack = find_item(storage, take_id) if take_quantity > 0 else null # Validate the NPC's prospective payment destination before charging the player.
    if existing_payment != null and (not is_equal_approx(existing_payment.get_unit_weight(), payment.get_unit_weight()) or existing_payment.get_category() != payment.get_category()): # Require compatible destination stack metadata.
        return {"success": false, "message": "These Goods Cannot Be Exchanged Right Now."} # Reject conflicting stock definitions before any mutation.
    if not player_inventory.try_exchange_items(take_id, take_quantity, reward, give_quantity): # Validate final carried weight and all player stack metadata atomically.
        return {"success": false, "message": "The Exchange Cannot Fit Your Inventory. Check Your Carrying Space."} # Retain currency, goods and the pending choice after a failed receipt.
    if take_quantity > 0: # Deliver the prevalidated payment to the NPC's real stock.
        storage.try_add_item(take_id, payment.get_display_name(), payment.get_unit_weight(), take_quantity, payment.get_category()) # Transfer payment ownership using the original held metadata.
    if give_quantity > 0: # Complete the prevalidated NPC stock transfer.
        storage.remove_item(give_id, give_quantity) # Remove exactly the quantity already delivered to the player.
    record["radiant_completed"] = true # Make completion irreversible for this actor's encounter identity.
    npc.change_affection(float(quote.get("affection_gain", 0.0))) # Reflect a completed friendly exchange or help in existing social state.
    return {"success": true, "hostile": false, "message": str(quote.get("success", "Thank You. Safe Travels!"))} # Confirm the concrete outcome without closing before the player can read it.
