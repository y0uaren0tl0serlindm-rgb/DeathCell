extends Node
## 全局信号总线：任何模块都可以广播/监听，避免节点之间互相持有引用。

## 战斗
signal hit_landed(world_pos: Vector2, amount: int, is_crit: bool)
signal enemy_died(world_pos: Vector2, cell_reward: int)

## 玩家
signal player_health_changed(current: int, maximum: int)
signal player_died()
signal player_weapon_changed(weapon_name: String)

## 进程
signal cells_changed(amount: int)
signal depth_changed(depth: int)
signal room_cleared()
signal request_next_room()
signal request_restart_run()
