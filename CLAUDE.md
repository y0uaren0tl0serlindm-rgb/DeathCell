# DeathCell — 类死亡细胞 2D 动作

Godot 4.7 / GDScript。目前是一个**可玩的垂直切片**：手感 → 战斗 → 程序化关卡 → 死亡循环这条主链路已经打通，
主角已接入像素美术，其余仍是占位色块（ColorRect + `_draw()`），换成真实素材不需要改逻辑。

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
godot --headless --path . --import                        # 首次克隆后跑一次（导入美术素材）
godot --path .                                            # 直接开玩
godot --headless --path . res://tests/smoke_test.tscn     # 冒烟测试：核心链路 15 项
godot --headless --path . res://tests/run_flow_test.tscn  # 流程测试：8 层、结算、解锁、选人
godot --headless --path . res://tests/generation_test.tscn # 关卡校验：三个生成器各 300 个房间
godot --headless --path . res://tests/chunk_test.tscn      # 手绘模板块：画完 .room 跑这个
godot --headless --path . res://tests/regression_test.tscn # 回归测试：已修 issue 不复发
godot --headless --path . res://tests/jump_model_test.tscn # 跳跃模型与真实玩家是否一致
bash tests/cold_start_check.sh                            # 冷启动：无缓存也能起
```

首次克隆或新增了图片/音频等二进制素材后，要跑一次 `--import` 把它们转成引擎格式
（性质等同 `npm install`，是可脚本化的命令，不需要打开编辑器）。
纯改代码不需要重跑。

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
| J / 鼠标左键 | 攻击（两段连招） |
| Shift / L | 翻滚（有无敌帧，可取消攻击后摇） |
| E | 清怪后进入下一层；L8 进入终点传送门 |
| 鼠标 / Enter | 局外解锁、选人并开始下一局 |

## 目录

```
src/
  autoload/   Events(信号总线) Game(run + 局外持久化状态) FX(顿帧/震屏/飘字)
  core/       Health, Hitbox, Hurtbox, DamageInfo —— 玩家和敌人共用同一套伤害管线
  player/     player.gd（枚举状态机：IDLE/RUN/JUMP/FALL/ROLL/ATTACK/HURT/DEAD）
  weapons/    WeaponData + AttackStep + weapons.gd（武器库，代码定义）
  enemies/    enemy.gd 基类 + grunt.tscn / brute.tscn（靠 @export 数值区分）
  level/      jump_model.gd（用 player.gd 的物理常数模拟出跳跃包络）
              room_chunk.gd（手绘 .room 模板块的解析与结构校验）
              chunk_library.gd（读盘 + 缓存 + 按深度筛选模板块）
              agent_carver.gd（智能体挖掘：模板块拼不出来时的兜底）
              level_grid.gd（生成调度 + 可达性校验，不进场景树，可批量测试）
              room.gd（把网格变成碰撞体/画面/角色）, door.gd
  pickups/    cell_pickup.gd
  ui/         hud.gd（局内）, meta_screen.gd（结算/解锁/选人）
  fx/         game_camera.gd, damage_number.gd
  main.gd     局外整备 ↔ 8 层 run ↔ 死亡/通关结算的编排
assets/levels/chunks/*.room   手绘的房间模板块（纯文本，一字符一格）
              画法见 assets/levels/README.md
tests/        smoke_test（核心链路）, generation_test（关卡可通行性）
              run_flow_test（8 层 + 结算 + 解锁 + 选人）
              chunk_test（手绘模板块：语法 + 可达性 + 接缝）
              regression_test（每项对应一个已修 issue）
              jump_model_test（跳跃模型 vs 真实玩家）
```

## 调手感看这里

- **移动/跳跃/翻滚**：`src/player/player.gd` 顶部常量区。
  改完跳跃参数不需要再去关卡那边手工同步 —— `src/level/jump_model.gd`
  会直接读这些常量、模拟出跳跃包络，地形生成用的是模拟结果。
  但要跑一遍 `jump_model_test`（模型 vs 真实玩家）和 `generation_test`
  确认没脱节。仍然有一条常量硬约束：`PLATFORM_CLEARANCE + 1 <= 稳妥跳跃高度`，
  generation_test 开头会断言。
- **玩家的瞬时状态**：新增任何 `_pending_*` / `_active_*` / 输入缓冲字段，
  都要加进 `player.gd` 的 `clear_transient_state()`。
  漏了它就会跨房间泄漏，在下一次攻击结束时莫名其妙地生效（issue #6）。
- **攻击中的输入**：走 `_pending_intent` 意图槽，不走定时缓冲。
  槽里永远只留最后按下的那一个，到攻击的取消点再兑现。
  两条理由：定时缓冲会在取消点之前过期（重锤取消点 0.54 秒 > 缓冲 0.15 秒），
  以及玩家必须能改主意 —— 新意图要能覆盖尚未开始的续击（issue #9）。
  加新动作时在 `Intent` 里加一项，并在 `_consume_intent_at_cancel_point()`
  / `_resolve_intent_after_attack()` 里决定它是"截断后摇"还是"等这一击打完"。
- **武器绑定角色**：游戏中不能换武器，主角固定用锈剑（`Weapons.rusty_sword()`）。
  要改装备走 `Player.equip()` —— 后续的掉落/词条系统从那里进来。
  攻击进行中调 `equip()` 不影响这一击：伤害和时间轴走 `_active_weapon` / `_active_step`，
  它们在 `_enter_attack()` 时就锁定了（issue #2，回归测试仍在守这条）。
- **连招段数 = 攻击贴图套数**。每段招式用 `AttackStep.anim` 显式指定动画名，
  **不要**退回按段号取模。以前表现层用 `_combo_index % 2` 轮换两套贴图，
  锈剑三段就播成 A-B-A —— 打三下看起来只有两下，玩家读不出连招进行到哪了。
  段数和贴图数是各自变化的两个量，取模只在两者相等时碰巧成立。
  现在锈剑是两段（对应 `attack_a` / `attack_b`）；美术出了第三套斩击之后，
  在 `weapons.gd` 里加一段 `ANIM_C` 即可。smoke_test 会断言这条对应关系。
- **连招循环**：`WeaponData.loops` 默认 false，末段之后退出攻击状态。
  要循环必须显式打开 —— 以前用 `index % size` 隐式循环，导致连点就能无限续招。
- **武器连招**：`src/weapons/weapons.gd`。每段招式是 前摇 / 判定 / 后摇 三个时间片，
  `cancel_after` 决定后摇进行到多少比例可以被下一段或翻滚取消 —— 这个值决定了整套战斗的节奏。
- **打击感**：`src/autoload/fx.gd`（顿帧时长、震屏强度）。
  顿帧用 `Engine.time_scale`，所以任何需要在顿帧期间照常运行的东西（震屏、飘字）
  都必须用不受时间缩放影响的 delta 或 `set_ignore_time_scale(true)`。

## 关卡生成

有三个生成器，`LevelGrid.generator` 切换，默认**模板块拼接**。

**模板块拼接**（`room_chunk.gd` + `chunk_library.gd` + `level_grid.gd` 的
`_build_with_chunks`）：把 `assets/levels/chunks/*.room` 里**手绘**的块横向接起来。
块是纯文本、一个字符一格。**怎么画见 [`assets/levels/README.md`](assets/levels/README.md)**，
画完跑 `chunk_test`，它会指出哪个平台跳不上去。
接缝的判据和房间内部完全一样：从上一块的 `>` 往右走一格到下一块的 `<`，
这一步必须是 `JumpModel` 里真实存在的移动。
拼不出通路（块太少、接口高度凑不上）时**自动退回智能体挖掘** ——
静默降级最难发现，所以两个测试都把"有房间退回了"当失败报。

**智能体挖掘**（`agent_carver.gd`）：从一整块石头开始，智能体从入口出发，
每一步只做 `JumpModel` 里真实存在的移动，走到出口为止；走过的地方挖空、
落脚点下面填实。**可达性是路径本身的性质**，不靠事后推导约束。
出来的是带竖井、露台、回环的洞穴。也是模板块拼不出来时的兜底。

**高度图**（`level_grid.gd` 里的 `_build_with_heightmap`）：地面随机游走 +
悬空平台，出来的是"一条走廊 + 挂件"。保留它是为了 A/B 对比。

两条约束是共通的、也是最容易踩的：

- 平台/台阶的高度必须来自 `JumpModel`，不要手推。手推的两次代价见 issue #7。
- **正下方是跳不上去的** —— 玩家会顶到台子底面，真实路线是在边上起跳再落上去。
  所以基准落脚点要取紧挨台子边缘的那一列，不是台子自己那一列。

房间宽度是**实例变量** `LevelGrid.width`，不是常量 —— 拼接出来的房间每次都不一样宽。
高度仍然是常量 `H`，所有模板块都是 H 行高，拼接只有横向一个自由度。

改了生成逻辑跑 `generation_test`，它会对比三个生成器的指标并断言硬条件
（出口可达、连通率、平台密度不退化、没有静默退回）。
改了 `.room` 或模板块相关代码跑 `chunk_test`。

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

⚠️ 在 `area_entered` / `body_entered` 回调里**不能直接**改 `monitoring` / `monitorable`
或增删带碰撞体的节点 —— 那是物理查询期，引擎会拒绝并报错。
命中 → 扣血 → 死亡这条链全在回调里，所以相关操作一律用
`set_deferred()` / `call_deferred()`。

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
`idle` / `run` / `jump` / `fall` / `roll` / `hurt` / `death`，外加攻击 `attack_a` / `attack_b`。

目前**只有 idle / run / attack_a / attack_b 有真素材**，其余状态在
`hero_sprite.gd` 里回落到 idle 帧（人在空中站着、翻滚是站姿转圈），
起步/停步/转身的过渡帧也是拿 idle 凑的。这几项是接下来最影响手感的缺口。
连招段数被锁死在攻击贴图套数上（smoke_test 断言），所以**多出一套斩击 = 多一段连招**。

攻击动画要卡住三个阶段的时长，动作读起来才对（数值见 `src/weapons/weapons.gd`）：

| 武器 | 段 | 前摇 | 判定 | 后摇 |
|---|---|---|---|---|
| 锈剑（主角固定武器） | 1 / 2 | 0.06 / 0.10 | 0.08 / 0.10 | 0.16 / 0.28 |
| 双匕（未启用） | 1 / 2 | 0.04 / 0.05 | 0.06 / 0.07 | 0.10 / 0.20 |
| 重锤（未启用） | 1 / 2 | 0.20 / 0.26 | 0.10 / 0.12 | 0.34 / 0.42 |

六帧的攻击贴图按这三个时间片分：**前 4 帧摊在前摇里，第 5 帧（斩击弧）
正好占满判定窗口，第 6 帧（余韵）占满后摇**。第 5 帧和判定框同生共死是硬要求 ——
`art/tests/attack_visual_test.tscn` 会断言这一点。

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

1. **主角缺失的动画**：`jump` / `fall` / `hurt` / `death` 目前一张贴图都没有，
   `hero_sprite.gd` 全部回落到 idle 帧 —— 人在空中站着、挨打没反应。
   翻滚也只是 idle 帧整体旋转 360°。`run_start` / `run_stop` / `run_turn`
   同样是拿 idle 帧凑的，每次起步/停步/转身角色会闪一下站姿，
   高速左右点按时最明显。**这是目前最影响手感的一项**，等美术补齐后接线即可。
2. **音效**：命中、翻滚、脚步、死亡。没有音效的打击感只有一半，而且这块不依赖美术，可以马上做。
3. **地形美术**：`solid` 网格 → TileMapLayer；敌人 ColorRect → AnimatedSprite2D。
4. **手绘模板块的量**：现在只有 5 块，一层来回就那几段。
   多画几块就能明显拉开变化 —— 画法见 `assets/levels/README.md`。
5. **敌人多样性**：目前只有近战冲撞。至少还需要远程射手和会跳的敌人（现在敌人不会跳，会被地形卡住）。
6. **词条/装备系统**：死亡细胞的核心留存来自"这把武器有什么词条"。
   `WeaponData` 已经是 Resource，加一层 Affix 数组即可；装备入口是 `Player.equip()`。
7. **房间结构**：现在每层是一条横向通道。下一步做多房间图（分支、宝箱房、精英房）——
   模板块的 `tags` 字段就是为这个留的。
8. **meta 图纸**：局外细胞、角色解锁与选人已经用 `ConfigFile` 持久化；
   `Game.meta_blueprints` 仍是空壳。
9. **一次性内容**：Boss、卷轴（永久属性提升）。L8 传送门先作为无 Boss 的终点占位。
10. **导出配置**：`.room` 是纯文本，不走导入流水线。以后做正式导出时，
    记得把 `*.room` 加进导出过滤器，否则打包后 `ChunkLibrary` 会读不到块、
    静默退回智能体挖掘。
