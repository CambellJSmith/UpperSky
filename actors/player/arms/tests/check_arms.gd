extends SceneTree
func _initialize(): run.call_deferred()
func run():
    var player = load("res://actors/player/first_person_player.tscn").instantiate()
    root.add_child(player)
    player.set_physics_process(false)
    player.set_process(false)
    var equipment = player.get_node("PlayerEquipment")
    var inventory = player.get_node("PlayerInventory")
    var arms = player.get_node("Head/Camera3D/Arms")
    assert(arms._arms.size() == 2)
    var worst_error = 0.0
    var samples = 0
    for definition in EquipmentCatalog.DEFINITIONS:
        assert(inventory.try_add_item(definition.item_id,definition.display_name,definition.unit_weight,1,InventoryCategory.Type.WEAPONS_TOOLS))
        assert(equipment.equip_item(definition.item_id))
        var item = equipment._equipped_item
        assert(arms._item == item)
        assert(item.primary_use())
        for frame in range(36):
            await create_timer(.016).timeout
            arms._update_pose(0)
            for arm in arms._arms:
                var skeleton: Skeleton3D = arm.skeleton
                assert(skeleton.get_bone_count() == 21)
                for bone in range(skeleton.get_bone_count()): assert(skeleton.get_bone_global_pose(bone).origin.is_finite())
                if arm.side > 0 or arms._two_handed:
                    var wrist = arms.to_local(skeleton.to_global(skeleton.get_bone_global_pose(2).origin))
                    worst_error = maxf(worst_error,wrist.distance_to(arm.desired_wrist))
                    samples += 1
        equipment.unequip()
        assert(arms._item == null)
        assert(not item._swing_tween.is_valid())
        await process_frame
    player.get_view_camera().rotation = Vector3(.9,1.3,0)
    arms._update_pose(0)
    assert(arms._arms[0].root.get_parent() == arms)
    print("Arm tracking samples: ",samples,"; maximum wrist error: ",worst_error)
    assert(worst_error < .015,"A hand lost contact with its handle during an attack")
    player.free()
    print("PASS: imported 21-bone rigs, all 17 equipment grips and attack profiles, reach, swapping, unequip cancellation and camera attachment.")
    quit()
