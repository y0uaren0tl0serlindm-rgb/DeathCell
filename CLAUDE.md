# DeathCell — 类死亡细胞 2D 动作 Roguelite

Godot 4.7 / GDScript。目前是一个**可玩的垂直切片**：手感 → 战斗 → 程序化关卡 → 死亡循环这条主链路已经打通，
美术全部是占位色块（ColorRect + `_draw()`），换成真实素材不需要改逻辑。

## 运行

```bash
godot --path .                                    # 直接开玩
godot --headless --path . res://tests/smoke_test.tscn   # 无头冒烟测试（13 项）
```

改了带 `class_name` 的脚本后如果命令行报 "Could not find type X"，
跑一次 `godot --headless --path . --editor --quit` 重建全局类缓存即可。

## 操作

| 键 | 行为 |
|---|---|
| A / D、←/→ | 移动 |
| 空格 | 跳（可变高度：松手即截断上升） |
| J / 鼠标左键 | 攻击（三段连招） |
| Shift / L | 翻滚（有无敌帧，可取消攻击后摇） |
| K | 换武器（锈剑 / 双匕 / 重锤） |
| E | 在门口进入下一层 |
| R | 死亡后重开 |

## 目录

```
src/
  autoload/   Events(信号总线) Game(单次 run 状态) FX(顿帧/震屏/飘字)
  core/       Health, Hitbox, Hurtbox, DamageInfo —— 玩家和敌人共用同一套伤害管线
  player/     player.gd（枚举状态机：IDLE/RUN/JUMP/FALL/ROLL/ATTACK/HURT/DEAD）
  weapons/    WeaponData + AttackStep + weapons.gd（武器库，代码定义）
  enemies/    enemy.gd 基类 + grunt.tscn / brute.tscn（靠 @export 数值区分）
  level/      room.gd（程序化房间生成）, door.gd
  pickups/    cell_pickup.gd
  ui/         hud.gd
  fx/         game_camera.gd, damage_number.gd
  main.gd     房间 ↔ 玩家 ↔ 死亡重开的编排
tests/        无头冒烟测试
```

## 调手感看这里

- **移动/跳跃/翻滚**：`src/player/player.gd` 顶部常量区。跳跃高度约 3.4 格、跳跃距离约 6 格 ——
  `src/level/room.gd` 的地形生成就是按这个能力上限约束的（`MAX_STEP = 2`），改跳跃参数时要一起看。
- **武器连招**：`src/weapons/weapons.gd`。每段招式是 前摇 / 判定 / 后摇 三个时间片，
  `cancel_after` 决定后摇进行到多少比例可以被下一段或翻滚取消 —— 这个值决定了整套战斗的节奏。
- **打击感**：`src/autoload/fx.gd`（顿帧时长、震屏强度）。
  顿帧用 `Engine.time_scale`，所以任何需要在顿帧期间照常运行的东西（震屏、飘字）
  都必须用不受时间缩放影响的 delta 或 `set_ignore_time_scale(true)`。

## 物理层约定

| bit | 值 | 用途 |
|---|---|---|
| 1 | 1 | world（地形） |
| 2 | 2 | player_body |
| 3 | 4 | enemy_body |
| 4 | 8 | player_hurtbox |
| 5 | 16 | enemy_hurtbox |
| 6 | 32 | pickup |

Hitbox 只 `monitoring`，Hurtbox 只 `monitorable` —— 攻击方主动检测，受击方被动挨打，
一次挥击对同一目标只结算一次（`Hitbox.activate()` 会清空命中表）。

## 已知缺口 / 下一步

按优先级：

1. **美术接入**：把 ColorRect 换成 AnimatedSprite2D，攻击的三个阶段对应动画帧；
   地形换成 TileMapLayer（`room.gd` 已经生成好 `solid` 网格，直接喂给 TileMapLayer 即可）。
2. **音效**：命中、翻滚、脚步、死亡。没有音效的打击感只有一半。
3. **敌人多样性**：目前只有近战冲撞。至少还需要远程射手和会跳的敌人（现在敌人不会跳，会被地形卡住）。
4. **词条/装备系统**：死亡细胞的核心留存来自"这把武器有什么词条"。
   `WeaponData` 已经是 Resource，加一层 Affix 数组即可。
5. **房间结构**：现在每层是一条线性走廊。下一步做多房间图（分支、宝箱房、精英房）。
6. **meta 进度**：`Game.meta_blueprints` 是空壳，需要接存档（`ConfigFile` 或 `ResourceSaver`）。
7. **一次性内容**：Boss、卷轴（永久属性提升）、传送门。
