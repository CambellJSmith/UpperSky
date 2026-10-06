extends SceneTree
func _initialize(): run.call_deferred()
func run():
    var game = load("res://application/game/game.tscn").instantiate()
    root.add_child(game)
    game.get_node("SaveSystem").startup={}
    game.get_node("SaveSystem").set_process(false)
    var settlements: SettlementStreamer = game.get_node("World/Settlements")
    var deadline = Time.get_ticks_msec()+120000
    while Time.get_ticks_msec()<deadline:
        if settlements._towns.size()>0 and settlements._homes.size()>0: break
        await process_frame
    var towns = settlements._towns.size()
    var homes = settlements._homes.size()
    print("STARTUP loaded settlements ",towns," homes ",homes," after ",(Time.get_ticks_msec()-(deadline-120000))/1000.0," seconds")
    game.queue_free()
    await process_frame
    assert(towns>0 and homes>0,"Natural settlement streaming must reach both settlements and homesteads at fresh spawn")
    print("PASS natural startup settlement visibility without teleporting")
    quit()
