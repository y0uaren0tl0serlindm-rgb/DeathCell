# DeathCell — 类死亡细胞 2D 动作

Godot 4.7 / GDScript。目前是一个**可玩的垂直切片**：手感 → 战斗 → 程序化关卡 → 死亡循环这条主链路已经打通，
美术全部是占位色块（ColorRect + `_draw()`），换成真实素材不需要改逻辑。

## 仓库

这个项目有**两个远端，内容必须保持一致**：

```
origin  git@10.194.101.198:sisyphus/DeathCell.git       # 内网
github  git@github.com:y0uaren0tl0serlindm-rgb/DeathCell.git
```

`main` 的上游是 `github/main`，所以裸跑 `git push` **只会推到 GitHub**，内网那份会悄悄落后。
推送时请显式推两边：

```bash
git push origin main && git push github main
```

两边分叉时用 merge 不要用 rebase —— 提交已经发布出去了，改写历史会让另一边和协作者对不上。

## 运行

```bash
godot --path .                                            # 直接开玩
godot --headless --path . res://tests/smoke_test.tscn     # 冒烟测试：核心链路 15 项
godot --headless --path . res://tests/generation_test.tscn # 关卡校验：1800 个房间可通行
godot --headless --path . res://tests/regression_test.tscn # 回归测试：已修 issue 不复发
bash tests/cold_start_check.sh                            # 冷启动：无缓存也能起
```

### 引用别的脚本要显式 preload

跨文件用到别人的 `class_name` 时，**必须在文件顶部写一行 `const X = preload("res://...")`**，
哪怕全局类名看起来已经能用了。

原因：`class_name` 的解析依赖 `.godot/global_script_class_cache.cfg`，而这个目录不入库。
干净检出、或者别人 pull 到含新 `class_name` 的代码而没重开编辑器，都会解析失败、
游戏直接起不来（issue #8）。显式 preload 让依赖在解析期就确定，跟缓存无关。

同理，**不要用字符串查类**（`find_children(..., "Room")`、`ClassDB` 之类）——
那也走全局注册表。用预加载的常量做 `is` 判断。

改完跑 `bash tests/cold_start_check.sh` 验证。

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
  level/      level_grid.gd（地形生成 + 可达性校验，不进场景树，可批量测试）
              room.gd（把网格变成碰撞体/画面/角色）, door.gd
  pickups/    cell_pickup.gd
  ui/         hud.gd
  fx/         game_camera.gd, damage_number.gd
  main.gd     房间 ↔ 玩家 ↔ 死亡重开的编排
tests/        smoke_test（核心链路）, generation_test（关卡可通行性）
              regression_test（每项对应一个已修 issue）
```

## 调手感看这里

- **移动/跳跃/翻滚**：`src/player/player.gd` 顶部常量区。
  ⚠️ 改跳跃参数必须同步 `src/level/level_grid.gd` 的"玩家能力"常量段
  （`BODY_TILES` / `JUMP_UP` / `_max_dx()`）—— 地形生成是按这些值反推约束的，
  不同步就会生成玩家跳不上去的地形。改完跑一遍 generation_test 验证。
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

## 美术素材规格（给美术同学）

美术由独立的同学负责，代码这边不改美术资源。下面是接入所需的硬约束——
现在的占位色块就是按这些尺寸摆的，照着做可以直接替换、不用改逻辑。

**基础**：视口 640×360（窗口 2 倍放大到 1280×720）；像素画，纹理过滤已设为 nearest；
所有角色**原点在脚底中心**（脚踩的那个点是 `position`，身体往上长）。

| 对象 | 碰撞体尺寸 | 建议画布 | 说明 |
|---|---|---|---|
| 玩家 | 10 × 22 | 32 × 32 | 武器挥舞可以超出画布，判定框跟贴图无关 |
| 小兵 Grunt | 12 × 20 | 32 × 32 | |
| 精英 Brute | 18 × 28 | 48 × 48 | |
| 地形图块 | 16 × 16 | 16 × 16 | 需要 上表面 / 内部 / 左右边缘 几种变体 |
| 细胞掉落 | 直径 ~8 | 16 × 16 | 会自己发光缩放，画静态即可 |
| 门 | 22 × 38 | 32 × 48 | |

**玩家动画**（状态机里已有的状态，一一对应）：
`idle` / `run` / `jump` / `fall` / `roll` / `hurt` / `death`，外加每把武器 2~3 段攻击。

攻击动画要卡住三个阶段的时长，动作读起来才对（数值见 `src/weapons/weapons.gd`）：

| 武器 | 段 | 前摇 | 判定 | 后摇 |
|---|---|---|---|---|
| 锈剑 | 1 / 2 / 3 | 0.06 / 0.06 / 0.12 | 0.08 / 0.08 / 0.10 | 0.16 / 0.18 / 0.30 |
| 双匕 | 1 / 2 / 3 | 0.04 / 0.04 / 0.05 | 0.06 / 0.06 / 0.07 | 0.10 / 0.10 / 0.20 |
| 重锤 | 1 / 2 | 0.20 / 0.26 | 0.10 / 0.12 | 0.34 / 0.42 |

**敌人动画**：`idle` / `walk` / `windup` / `attack` / `hurt` / `death`。
其中 `windup`（前摇）是玩家的读招信号，**必须一眼能认出来**——现在用的是闪黄光，
换成动画后建议保留高对比的提亮或特效。

**接入位置**：每个角色场景里都有一个 `Visual` 节点，下面挂的 ColorRect 就是占位。
把 ColorRect 换成 `AnimatedSprite2D`、按上面的名字建动画即可，
`player.gd` / `enemy.gd` 里改几行播放调用，不动任何逻辑。
地形那边 `level_grid.gd` 已经生成好 `solid` 网格，接 TileMapLayer 只是把网格喂过去。

**配色**：背景和地形色现在是按层数做色相偏移（`room.gd` 的 `generate()`），
如果美术要出固定的生物群系配色，告诉我改成查表即可。

## 已知缺口 / 下一步

按优先级：

1. **音效**：命中、翻滚、脚步、死亡。没有音效的打击感只有一半，而且这块不依赖美术，可以马上做。
2. **美术接入**：素材由外部同学产出（规格见上一节），代码这边只负责接线：
   ColorRect → AnimatedSprite2D、`solid` 网格 → TileMapLayer。
3. **敌人多样性**：目前只有近战冲撞。至少还需要远程射手和会跳的敌人（现在敌人不会跳，会被地形卡住）。
4. **词条/装备系统**：死亡细胞的核心留存来自"这把武器有什么词条"。
   `WeaponData` 已经是 Resource，加一层 Affix 数组即可。
5. **房间结构**：现在每层是一条线性走廊。下一步做多房间图（分支、宝箱房、精英房）。
6. **meta 进度**：`Game.meta_blueprints` 是空壳，需要接存档（`ConfigFile` 或 `ResourceSaver`）。
7. **一次性内容**：Boss、卷轴（永久属性提升）、传送门。
