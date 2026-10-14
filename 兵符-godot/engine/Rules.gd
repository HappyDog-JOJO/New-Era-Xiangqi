extends RefCounted
## 棋盘几何与规则常量。
##
## 【架构约定】这个文件只做纯计算：不碰 Node、不发信号、不读文件。
## 引擎层的每个文件都必须满足这条，否则单测和 AI 就都做不成了。

const COLS := 9
const ROWS := 10

## 三座桥所在的列
const BRIDGE_COLS := [3, 5, 7]

## 九宫：红方 列4–6 × 行1–3；黑方 列4–6 × 行8–10
const PALACE := {
	"r": {"c0": 4, "c1": 6, "r0": 1, "r1": 3},
	"b": {"c0": 4, "c1": 6, "r0": 8, "r1": 10},
}

## 主将起始位置
const KING_START := {"r": Vector2i(5, 2), "b": Vector2i(5, 9)}

## 士起始位置（每方 2 个，开局自带，不是卡牌）
const ADVISOR_START := {
	"r": [Vector2i(4, 1), Vector2i(6, 1)],
	"b": [Vector2i(4, 10), Vector2i(6, 10)],
}

## 人口：主将与士为 0，小兵 1，其余 2
const POP_COST := {"king": 0, "advisor": 0, "pawn": 1}
const POP_COST_DEFAULT := 2

## 象的每方上限（士没有上限：固定 2 个、无法补充）
const ELEPHANT_CAP := 2

## 主将的「指挥范围」半径，用**曼哈顿距离**。
## 部署（§2.3）与装备都在这个范围内进行：
##   · 开局布阵例外 —— 可放己方半场任意空点（§6.1）
##   · 装备：小兵必须在主将曼哈顿 ≤ 2 之内，否则装不了
## 【作者裁定，规则书 v0.5 尚未收录，建议并入 v0.6 的 §3.2 / §7.2】
## 口径确认：**只判曼哈顿 ≤ 2，不附加「不过河」**；**含主将自身那一格**（距离 0）。
const COMMAND_RANGE := 2


## 两点是否在指挥范围内（曼哈顿距离 ≤ COMMAND_RANGE，含距离 0）
static func within_command_range(c1: int, r1: int, c2: int, r2: int) -> bool:
	return abs(c1 - c2) + abs(r1 - r2) <= COMMAND_RANGE


static func in_board(c: int, r: int) -> bool:
	return c >= 1 and c <= COLS and r >= 1 and r <= ROWS


static func in_palace(owner: String, c: int, r: int) -> bool:
	var z: Dictionary = PALACE[owner]
	return c >= z.c0 and c <= z.c1 and r >= z.r0 and r <= z.r1


## 己方半场：红行 1–5，黑行 6–10
static func own_half(owner: String, r: int) -> bool:
	return r <= 5 if owner == "r" else r >= 6


## 该单位是否已经过河
static func has_crossed(owner: String, r: int) -> bool:
	return r >= 6 if owner == "r" else r <= 5


## 从 r1 走到 r2 是否跨越河界
static func crosses_river(r1: int, r2: int) -> bool:
	return (r1 <= 5 and r2 >= 6) or (r1 >= 6 and r2 <= 5)


static func is_bridge_col(c: int) -> bool:
	return BRIDGE_COLS.has(c)


static func other_side(owner: String) -> String:
	return "b" if owner == "r" else "r"


static func side_name(owner: String) -> String:
	return "红方" if owner == "r" else "黑方"


static func cell_name(c: int, r: int) -> String:
	return "(%d,%d)" % [c, r]
