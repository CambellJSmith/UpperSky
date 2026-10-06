extends RefCounted
class_name LootStorage
var stacks: Array[InventoryStack] = []
var revision: int = 0
func get_stack_count() -> int: return stacks.size()
func get_stack_at(index: int) -> InventoryStack:
    return stacks[index] if index >= 0 and index < stacks.size() else null
func get_revision() -> int: return revision
func try_add_item(id: StringName, title: String, weight: float, amount: int = 1, category: int = InventoryCategory.Type.MISC) -> bool:
    if id == &"" or not is_finite(weight) or weight < 0 or amount <= 0 or not InventoryCategory.is_valid(category): return false
    for stack in stacks:
        if stack.get_item_id() != id: continue
        if not is_equal_approx(stack.get_unit_weight(),weight) or stack.get_category() != category: return false
        stack.increase_quantity(amount)
        revision += 1
        return true
    stacks.append(InventoryStack.new(id,title,weight,amount,category))
    revision += 1
    return true
func remove_item(id: StringName, amount: int = 1) -> int:
    for i in range(stacks.size()):
        if stacks[i].get_item_id() != id: continue
        var removed = stacks[i].remove_quantity(amount)
        if removed > 0: revision += 1
        if stacks[i].get_quantity() == 0: stacks.remove_at(i)
        return removed
    return 0
static func transfer(source: Object, destination: Object, id: StringName, amount: int) -> bool:
    if source == destination or amount <= 0: return false
    for i in range(source.get_stack_count()):
        var stack: InventoryStack = source.get_stack_at(i)
        if stack.get_item_id() != id: continue
        if stack.get_quantity() < amount: return false
        if not destination.try_add_item(id,stack.get_display_name(),stack.get_unit_weight(),amount,stack.get_category()): return false
        source.remove_item(id,amount)
        return true
    return false
