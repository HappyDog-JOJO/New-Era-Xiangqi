extends RefCounted
## 走法生成。完全沿用象棋，加上本作的地形/次数规则与将军规则：
##   1) 小兵、战车、炮兵只能从列 3/5/7 过河
##   2) 敌方象站在它自己那一侧的桥头时，这座桥走不通（连它也不能被跨河吃掉）
##   3) 每回合全盘只能移动一次（由 Game.move_used 控制）
##   4) **将军**：不能走出让自己的主将挨吃的着法（"不能送将"）
##   5) **将帅照面**：两个主将同列且中间无子 = 双方都算被将军
##
## 【三层结构，别搞混】
##   pseudo_moves()  —— 只管走法形状，**不看**回合状态、**不看**会不会送将。
##                      将军检测靠它（"对面能不能吃到我主将"就是用它算的）。
##   legal_moves()   —— pseudo 再过一道"不能送将"。这是给玩家用的。
##   is_in_check()   —— 用 pseudo 扫对方所有子，看有没有能落到己方主将那格的。
##
## 【为什么将军检测必须用 pseudo】`_push()` 里有一条"空城计期间不能吃主将"。
## 将军和吃将共用同一套着法生成，所以**空城计一生效，is_in_check 自然就返回 false** ——
## 这正是我们要的（空城计期间不算被将军），不需要额外特判。
##
## 【架构约定】纯静态函数，不碰 Node。

const Rules := preload("res://engine/Rules.gd")

const HORSE_DELTAS := [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]
const ORTHO := [[1, 0], [-1, 0], [0, 1], [0, -1]]
const DIAG := [[1, 1], [1, -1], [-1, 1], [-1, -1]]


## 玩家可用的合法着法：形状合法 + 不送将。
## 返回 Array[Dictionary]：{"c": int, "r": int, "cap": String}
## cap 为空串表示走到空格；否则是被吃棋子的 id
##
## 【被将军时它自动就变成了"只能解将"】因为安全过滤要求走完之后己方不被将军，
## 所以身在将军中时，只有能解除将军的着法能活下来 —— 不需要额外判断。
static func legal_moves(game, p) -> Array:
	if game.phase != "play" or game.winner != "":
		return []
	if game.move_used:
		return []
	if game.is_rooted(p.id):
		return []
	if game.is_flooded(p.r):
		return []

	var safe: Array = []
	for m in pseudo_moves(game, p):
		if _would_be_safe(game, p, m.c, m.r):
			safe.append(m)
	return safe


## 只管走法形状。**不看** phase / move_used / 绊马索 / 水淹，**也不看**会不会送将。
## 将军检测与"试算解将"都用它。
static func pseudo_moves(game, p) -> Array:
	match p.kind_now():
		"pawn": return _pawn(game, p)
		"horse": return _horse(game, p)
		"chariot": return _chariot(game, p)
		"cannon": return _cannon(game, p)
		"king": return _king(game, p)
		"advisor": return _advisor(game, p)
		"elephant": return _elephant(game, p)
	return []


# ---------------------------------------------------------------- 将军

## owner 的主将现在是否被将军（含将帅照面）。
static func is_in_check(game, owner: String) -> bool:
	var king = game.king_of(owner)
	if king == null:
		return false
	if kings_face_each_other(game):
		return true
	var foe: String = Rules.other_side(owner)
	for q in game.pieces:
		if q.owner != foe or q.is_king():
			continue          # 主将的威胁由"照面"单独处理（两将永远够不着对方）
		for m in pseudo_moves(game, q):
			if m.c == king.c and m.r == king.r:
				return true
	return false


## 两个主将同列、中间无子。象棋里这是**非法局面**，所以双方都算被将军。
static func kings_face_each_other(game) -> bool:
	var rk = game.king_of("r")
	var bk = game.king_of("b")
	if rk == null or bk == null or rk.c != bk.c:
		return false
	var lo: int = mini(rk.r, bk.r) + 1
	var hi: int = maxi(rk.r, bk.r) - 1
	for r in range(lo, hi + 1):
		if game.piece_at(rk.c, r) != null:
			return false
	return true


## 把 p 试放到 (c,r) 之后，p 这一方还安全吗？
## 【做法】临时移子（被吃的先挪到盘外）→ 检测 → 原样还原。
## 必须**完全还原**，否则棋子会错位 —— 这条被 TestRunner 的"试算不留痕"断言盯着。
static func _would_be_safe(game, p, c: int, r: int) -> bool:
	var oc: int = p.c
	var orr: int = p.r
	var target = game.piece_at(c, r)
	var tc: int = 0
	var tr: int = 0
	if target != null:
		tc = target.c
		tr = target.r
		target.c = -99
		target.r = -99
	p.c = c
	p.r = r
	var bad: bool = is_in_check(game, p.owner)
	p.c = oc
	p.r = orr
	if target != null:
		target.c = tc
		target.r = tr
	return not bad


# ---------------------------------------------------------------- 各种棋子

static func _pawn(game, p) -> Array:
	var out: Array = []
	var dir: int = 1 if p.owner == "r" else -1
	_push(game, p, out, p.c, p.r + dir)
	# 首步 2 格：仅限己方底线两行内，且中间格空
	var in_start_zone: bool = (p.r <= 2) if p.owner == "r" else (p.r >= 9)
	if in_start_zone and game.piece_at(p.c, p.r + dir) == null:
		_push(game, p, out, p.c, p.r + 2 * dir)
	# 过河后可横走，永不后退
	if Rules.has_crossed(p.owner, p.r):
		_push(game, p, out, p.c - 1, p.r)
		_push(game, p, out, p.c + 1, p.r)
	return out


static func _horse(game, p) -> Array:
	var out: Array = []
	for d in HORSE_DELTAS:
		var c: int = p.c + d[0]
		var r: int = p.r + d[1]
		if not Rules.in_board(c, r):
			continue
		# 蹩马腿：走两格的那个方向上、紧邻的那一格不能有子
		var lc: int = p.c + (d[0] / 2 if abs(d[0]) == 2 else 0)
		var lr: int = p.r + (d[1] / 2 if abs(d[1]) == 2 else 0)
		if game.piece_at(lc, lr) != null:
			continue
		_push(game, p, out, c, r)
	return out


static func _chariot(game, p) -> Array:
	var out: Array = []
	for d in ORTHO:
		out.append_array(_ray(game, p, d[0], d[1], false))
	return out


static func _cannon(game, p) -> Array:
	var out: Array = []
	for d in ORTHO:
		out.append_array(_ray(game, p, d[0], d[1], true))
	return out


static func _king(game, p) -> Array:
	var out: Array = []
	for d in ORTHO:
		var c: int = p.c + d[0]
		var r: int = p.r + d[1]
		if not Rules.in_board(c, r) or not Rules.in_palace(p.owner, c, r):
			continue
		_push(game, p, out, c, r)
	return out


static func _advisor(game, p) -> Array:
	var out: Array = []
	for d in DIAG:
		var c: int = p.c + d[0]
		var r: int = p.r + d[1]
		if not Rules.in_board(c, r) or not Rules.in_palace(p.owner, c, r):
			continue
		_push(game, p, out, c, r)
	return out


static func _elephant(game, p) -> Array:
	var out: Array = []
	for d in [[2, 2], [2, -2], [-2, 2], [-2, -2]]:
		var c: int = p.c + d[0]
		var r: int = p.r + d[1]
		if not Rules.in_board(c, r):
			continue
		# 象永不过河（它不认桥）
		if Rules.crosses_river(p.r, r):
			continue
		# 塞象眼：田字中心有子则走不过去
		if game.piece_at(p.c + d[0] / 2, p.r + d[1] / 2) != null:
			continue
		_push(game, p, out, c, r)
	return out


# ---------------------------------------------------------------- 工具

## 车 / 炮的直线扫描。is_cannon 时按炮的隔子吃子规则处理
static func _ray(game, p, dc: int, dr: int, is_cannon: bool) -> Array:
	var out: Array = []
	var c: int = p.c + dc
	var r: int = p.r + dr
	var screen: bool = false
	while Rules.in_board(c, r):
		var t = game.piece_at(c, r)
		if not is_cannon:
			if t == null:
				_push(game, p, out, c, r)
				c += dc
				r += dr
				continue
			_push(game, p, out, c, r)
			break
		# 炮
		if not screen:
			if t == null:
				_push(game, p, out, c, r)
				c += dc
				r += dr
				continue
			screen = true
			c += dc
			r += dr
			continue
		if t == null:
			c += dc
			r += dr
			continue
		_push(game, p, out, c, r)   # 炮架之后的第一个子
		break
	return out


static func _push(game, p, out: Array, c: int, r: int) -> void:
	if not Rules.in_board(c, r):
		return
	var t = game.piece_at(c, r)
	if t != null:
		if t.owner == p.owner:
			return                              # 不能吃己方 / 落在己方身上
		if t.is_king() and game.is_shielded(t.owner):
			return                              # 空城计期间，吃主将的那一步非法
		if not _cross_ok(game, p, c, r):
			return
		out.append({"c": c, "r": r, "cap": t.id})
		return
	if not _cross_ok(game, p, c, r):
		return
	out.append({"c": c, "r": r, "cap": ""})


## 过河判定：桥 + 象堵桥
static func _cross_ok(game, p, c2: int, r2: int) -> bool:
	if not Rules.crosses_river(p.r, r2):
		return true
	if p.kind_now() == "horse":
		return true                             # 骑兵跃河，不受桥与象阻拦
	# 落点上的敌方象，把整条通道堵死
	var blocker = game.piece_at(p.c, r2)
	if blocker != null and blocker.is_elephant() and blocker.owner != p.owner:
		return false
	return game.bridge_open(p.c)
