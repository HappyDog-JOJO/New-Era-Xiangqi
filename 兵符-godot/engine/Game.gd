extends RefCounted
## 对局状态与动作。
##
## 【架构约定】
##   · 只用 RefCounted，绝不 extends Node / 不发信号 / 不碰场景树
##   · 随机数走注入种子的 rng —— 同一颗种子必然复现同一副牌（回放、撤销、联网全靠它）
##   · 状态变化只通过 do_* 方法发生，方便以后加「动作日志 → 撤销 / 回放」

const Rules := preload("res://engine/Rules.gd")
const Piece := preload("res://engine/Piece.gd")
const MoveGen := preload("res://engine/MoveGen.gd")

const AP_PER_TURN := 2
const POP_CAP := 8            ## 2 人局每人 8；4 人 2v2 每队 10
const ELEPHANT_CAP := Rules.ELEPHANT_CAP
const HAND_LIMIT := 5

# ------------------------------------------------------------------ 状态

var pieces: Array = []
var deck: Array = []
var discard: Array = []
var hands: Dictionary = {"r": [], "b": []}
var effects: Array = []       ## 持续效果，见 add_effect
var turn: String = "r"
var ap: int = AP_PER_TURN
var move_used: bool = false   ## ← 每回合全盘只能移动一次
var turn_no: int = 1
var phase: String = "deploy"  ## deploy | play | over
var deploy_left: Dictionary = {"r": 3, "b": 3}
var deploy_turn: String = "r"
var winner: String = ""
var log_lines: Array = []
var last_scout: Dictionary = {}   ## 「探马」最近一次侦察的结果，供 UI 读取

var _uid: int = 0
var rng := RandomNumberGenerator.new()
var _probing: bool = false      ## 解将试算期间置 true，让动作门禁放行（防递归）


# ------------------------------------------------------------------ 开局

func new_game(p_seed: int = 0) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = p_seed

	pieces.clear()
	deck.clear()
	discard.clear()
	effects.clear()
	hands = {"r": [], "b": []}
	log_lines.clear()
	_uid = 0

	turn = "r"
	ap = AP_PER_TURN
	move_used = false
	turn_no = 1
	phase = "deploy"
	deploy_left = {"r": 3, "b": 3}
	deploy_turn = "r"
	winner = ""

	# 主将与士：不是卡牌，开局即在场（§3.4）
	_spawn("r", "king", Rules.KING_START.r.x, Rules.KING_START.r.y)
	for v in Rules.ADVISOR_START.r:
		_spawn("r", "advisor", v.x, v.y)
	_spawn("b", "king", Rules.KING_START.b.x, Rules.KING_START.b.y)
	for v in Rules.ADVISOR_START.b:
		_spawn("b", "advisor", v.x, v.y)

	deck = _build_deck()   # 60 张
	_shuffle(deck)
	_draw_cards("r", 4)
	_draw_cards("b", 5)
	_log("对局开始。先布阵：红方先放 3 个小兵。")


## 牌库 60 张。
## 【临时配比】锦囊目前只实现 2 种，所以只放这两种（增援 12 / 断桥 6），
## 免得摸到打不出去的「死牌」。其余 12 种接完后再恢复官方配比。
func _build_deck() -> Array:
	var d: Array = []
	for i in 21:
		d.append({"kind": "pawn"})
	for i in 3:
		d.append({"kind": "elephant"})
	for i in 6:
		d.append({"kind": "gear", "gear": "horse"})
	for i in 6:
		d.append({"kind": "gear", "gear": "chariot"})
	for i in 6:
		d.append({"kind": "gear", "gear": "cannon"})
	for i in 12:
		d.append({"kind": "spell", "spell": "增援"})
	for i in 6:
		d.append({"kind": "spell", "spell": "断桥"})
	return d


## 布阵：免费在己方半场任意空点放 3 个小兵
func setup_deploy(owner: String, c: int, r: int) -> bool:
	if phase != "deploy" or deploy_turn != owner or deploy_left[owner] <= 0:
		return false
	if not Rules.in_board(c, r) or not Rules.own_half(owner, r):
		return false
	if piece_at(c, r) != null:
		return false
	var card := _take_pawn_card(owner)
	var p = _spawn(owner, "pawn", c, r)
	p.card = card
	deploy_left[owner] -= 1
	if deploy_left[owner] == 0:
		if owner == "r":
			deploy_turn = "b"
			_log("红方布阵完毕，黑方布阵。")
		else:
			phase = "play"
			_log("布阵完毕，红方先行。")
			start_turn("r", true)
	return true


# ------------------------------------------------------------------ 查询

func piece_at(c: int, r: int):
	for p in pieces:
		if p.c == c and p.r == r:
			return p
	return null


func find_piece(piece_id: String):
	for p in pieces:
		if p.id == piece_id:
			return p
	return null


func king_of(owner: String):
	for p in pieces:
		if p.owner == owner and p.is_king():
			return p
	return null


func count_on_board(owner: String, kind: String) -> int:
	var n := 0
	for p in pieces:
		if p.owner == owner and p.kind == kind:
			n += 1
	return n


func pop_cost_of(p) -> int:
	if p.is_king() or p.is_advisor():
		return 0
	if p.kind == "pawn" and p.gear == "":
		return 1
	return 2


func pop_used(owner: String) -> int:
	var n := 0
	for p in pieces:
		if p.owner == owner:
			n += pop_cost_of(p)
	return n


func hand(owner: String) -> Array:
	return hands[owner]


func legal_moves(p) -> Array:
	return MoveGen.legal_moves(self, p)


# ------------------------------------------------------------------ 将军
#
# 【口径，作者定稿】按象棋完整实现：将军 → 必须应将 → 将死判负，含"不能送将"与"将帅照面"。
#
#   将死（checkmate）= 被将军 **且** 没有任何合法动作能解除它。
#   【Q1=甲】解将的手段**不限于移动**：部署 / 装备 / 解散 / 出锦囊 / 额外摸牌 都算候选。
#             所以 is_checkmate 枚举的是**全部动作**，不是只有走法。
#             这是本作与象棋最大的差别 —— 卡牌就是你的解将手段。
#   【Q2=甲】**不引入困毙**：只有"被将军且无法解除"才判负。
#             动不了子但还能部署 / 摸牌 / 打锦囊 → 游戏继续。
#             平局归 §1.3 的平局条款管（那是独立的一条，与本规则无关）。


## owner 的主将现在被将军吗（含将帅照面）。空城计生效期间恒为 false。
func is_in_check(owner: String) -> bool:
	return MoveGen.is_in_check(self, owner)


func kings_face_each_other() -> bool:
	return MoveGen.kings_face_each_other(self)


## 这一方现在还有没有任何**合法动作**？
## 【被将军时口径不同】Q3=甲：被将军时只有"能解除将军"的动作合法，
## 所以这时候要用 _has_any_escape() 来判，而不是"能随便做点什么就算"。
func has_any_action(owner: String) -> bool:
	if is_in_check(owner):
		return _has_any_escape(owner)
	if _has_any_legal_move(owner):
		return true
	# 部署：手上有兵种牌，且部署区里有空点，且人口够
	for card in hands[owner]:
		var k: String = card.get("kind", "")
		if k == "pawn" or k == "elephant":
			if k == "elephant" and count_on_board(owner, "elephant") >= ELEPHANT_CAP:
				continue
			var cost: int = 1 if k == "pawn" else 2
			if pop_used(owner) + cost > POP_CAP:
				continue
			if deploy_cells(owner).size() > 0:
				return true
		elif k == "gear":
			# 装备：有可装备的小兵（未装备 + 在指挥范围内）
			if pop_used(owner) + 1 > POP_CAP:
				continue
			for p in pieces:
				if p.owner == owner and p.kind == "pawn" and p.gear == "" \
						and in_command_range(owner, p.c, p.r):
					return true
	# 解散：场上除主将/士之外还有单位
	for p in pieces:
		if p.owner == owner and not p.is_king() and not p.is_advisor():
			return true
	# 额外摸牌：牌库或弃牌堆还有牌
	if not deck.is_empty() or not discard.is_empty():
		return true
	# 锦囊
	for i in hands[owner].size():
		if spell_targets(owner, i).get("ok", false):
			return true
	return false


## 场上还有没有"能动的棋子"。不看手上的牌。
func _has_any_legal_move(owner: String) -> bool:
	for p in pieces:
		if p.owner != owner:
			continue
		if legal_moves(p).size() > 0:
			return true
	return false


## owner 是否被将死：被将军，且一个能解将的合法动作都没有。
func is_checkmate(owner: String) -> bool:
	if not is_in_check(owner):
		return false
	return not _has_any_escape(owner)


## 有没有办法解除将军。枚举**所有**动作，逐个试算。
##
## 【试算是"有副作用"的】动作会真的部署棋子、扣 AP、移出手牌……
## 所以每一次试算都必须**完整快照 → 执行 → 判定 → 还原**，无论成功失败。
## 早期版本只在成功时还原，结果每次失败试算都往真实局面里塞一个棋子，
## selfplay 立刻报 `[状态异常]`（不重叠 / 越界 / 牌数守恒全破）。别再犯。
func _has_any_escape(owner: String) -> bool:
	# ① 移动：legal_moves 已经滤掉了送将着法，所以**能列出来的就是能解将的**
	if _has_any_legal_move(owner):
		return true

	# ② 部署 / 装备 / 锦囊：逐个真试一遍
	for card_i in range(hands[owner].size() - 1, -1, -1):
		var card: Dictionary = hands[owner][card_i]
		var k: String = card.get("kind", "")

		if k == "pawn" or k == "elephant":
			for v in deploy_cells(owner):
				var tx: int = v.x
				var ty: int = v.y
				var i: int = card_i
				if _probe(func() -> bool: return do_deploy(owner, i, tx, ty), owner):
					return true
		elif k == "gear":
			for p in pieces:
				if p.owner == owner and p.kind == "pawn" and p.gear == "":
					var i2: int = card_i
					var pid: String = p.id
					if _probe(func() -> bool: return do_equip(owner, i2, pid), owner):
						return true
		elif k == "spell":
			var info: Dictionary = spell_targets(owner, card_i)
			if not info.get("ok", false):
				continue
			var targets: Array = []
			if info.get("kind", "") == "cell":
				for v in info.cells:
					targets.append({"c": v.x, "r": v.y})
			elif info.get("kind", "") == "column":
				for col in info.columns:
					targets.append({"col": col})
			else:
				targets.append({})
			for t in targets:
				var i3: int = card_i
				if _probe(func() -> bool: return do_play_spell(owner, i3, t), owner):
					return true

	# ③ 解散：把自己的子拿掉也可能消除威胁（典型：它正好是对方炮的炮架）
	for p in pieces.duplicate():
		if p.owner != owner or p.is_king() or p.is_advisor():
			continue
		var pid2: String = p.id
		if _probe(func() -> bool: return do_disband(owner, pid2), owner):
			return true

	# ④ 额外摸牌：摸一张本身解不了将（牌不落场），所以**不视为解将手段**。
	#    这是有意省略，不是遗漏 —— 否则"被将军时摸一张牌"会变成合法应着。
	return false


## 试算一个动作：**快照 → 执行 → 判定是否解将 → 无论如何都还原**。
## 【递归陷阱】被试算的动作在收尾时会走 _finish_action，而它又要判将军、
## 又要试算…… 所以试算期间 _probing = true，让 _finish_action 直接放行（外层自己会判）。
func _probe(act: Callable, owner: String) -> bool:
	var snap: Dictionary = _snapshot_for_probe()
	_probing = true
	var ok: bool = act.call()
	_probing = false
	var escaped: bool = ok and not is_in_check(owner)
	_restore_from_probe(snap)          # ← 成功失败都要还原，这是这个 bug 的关键
	return escaped


## 动作收尾校验（Q3=甲）。**每个会改动盘面的动作在返回 true 之前都要过这一关。**
##
## 【为什么是"事后校验"而不是"事前拦截"】
## 事前拦（"被将军就一律不许多做"）是错的：被将军时**恰恰需要放行能解将的动作**。
## 只有做完之后看结果，才能同时覆盖两件事：
##   ① **不能送将** —— 原本没被将，做完自己反而挨将了 → 撤销
##   ② **必须应将** —— 原本挨着将，做完还挨着 → 撤销
##
## 【递归陷阱】_has_any_escape() 靠"真的执行一次动作再看结果"来试算解将，
## 而每个 do_* 收尾时又要过这一关 —— 不设旗标就会无限递归。
## 试算期间 _probing = true，这里直接放行（外层自己会判）。
##
## 【撤销靠整局快照】动作会连带改 AP / 弃牌堆 / 手牌 / 效果表，手工还原必漏。
##
## 【没有主将的局面直接放行】单元测试常用"清空棋子的空盘"（bare()），
## 那种局面判不了将军，也就没有"送将 / 应将"可言。不回滚，否则测试会莫名失败。
func _finish_action(owner: String, snap: Dictionary) -> bool:
	if _probing:
		return true
	if king_of(owner) == null:
		return true
	if is_in_check(owner):
		_restore_from_probe(snap)
		return false
	return true


## 取快照。试算期间不取 —— 外层 _has_any_escape 已经持有一份完整的了。
func _snap_if_needed() -> Dictionary:
	if _probing:
		return {}
	return _snapshot_for_probe()


## 整局快照。试算期间不取 —— 外层 _probe 已经持有一份完整的了。
## 【为什么必须整局快照而不是"试算后手工还原"】
## 一个动作会连带改 AP、弃牌堆、手牌、效果表、棋子位置……手工还原必然漏。
func _snapshot_for_probe() -> Dictionary:
	return {
		"pieces": pieces.duplicate(),
		"pos": _piece_positions(),
		"deck": deck.duplicate(),
		"discard": discard.duplicate(),
		"hands": {"r": hands.r.duplicate(), "b": hands.b.duplicate()},
		"effects": effects.duplicate(true),
		"ap": ap,
		"move_used": move_used,
		"winner": winner,
		"phase": phase,
		"log_n": log_lines.size(),
	}


func _piece_positions() -> Array:
	var out: Array = []
	for p in pieces:
		out.append([p.c, p.r, p.gear])
	return out


func _restore_from_probe(s: Dictionary) -> void:
	pieces = s.pieces
	deck = s.deck
	discard = s.discard
	hands = s.hands
	effects = s.effects
	ap = s.ap
	move_used = s.move_used
	winner = s.winner
	phase = s.phase
	var pos: Array = s.pos
	for i in pieces.size():
		pieces[i].c = pos[i][0]
		pieces[i].r = pos[i][1]
		pieces[i].gear = pos[i][2]
	# 试算期间写进战报的行要抹掉，否则会污染日志
	if log_lines.size() > s.log_n:
		log_lines.resize(s.log_n)


## 部署区：主将周围曼哈顿距离 ≤ 2 且不过河
func deploy_cells(owner: String) -> Array:
	var out: Array = []
	var king = king_of(owner)
	if king == null:
		return out
	for c in range(1, Rules.COLS + 1):
		for r in range(1, Rules.ROWS + 1):
			if piece_at(c, r) != null:
				continue
			if abs(c - king.c) + abs(r - king.r) > 2:
				continue
			if not Rules.own_half(owner, r):
				continue
			out.append(Vector2i(c, r))
	return out


## 这一格在不在主将的指挥范围内（曼哈顿 ≤ 2，含主将自身格）。
##
## 【为什么不能复用 deploy_cells()】deploy_cells() 返回的是**可落子的空点**，
## 已经把所有被占的格子滤掉了；而装备要判的恰恰是**站在格子上的那个小兵**，
## 拿它去查 deploy_cells() 永远查不到。所以这里是独立的判定。
##
## 【口径】作者定稿：只判曼哈顿 ≤ 2，**不附加「不过河」**。
## 目前红黑双方两个口径等价（主将在九宫里，曼哈顿 ≤ 2 够不到河），
## 但 3 人局蓝方主将在 (5,6)、本阵横跨河界时，附加河界检查会误伤，所以不加。
func in_command_range(owner: String, c: int, r: int) -> bool:
	var king = king_of(owner)
	if king == null:
		return false
	return Rules.within_command_range(c, r, king.c, king.r)


# ------------------------------------------------------------------ 持续效果

## type: bridge_broken / bridge_temp / flood / root / shield
## left: 剩余回合（在「打出者自己的回合开始」时减 1）
func add_effect(type: String, left: int, by: String, extra: Dictionary = {}) -> Dictionary:
	var e := {"id": "e%d" % _next_uid(), "type": type, "left": left, "by": by}
	for k in extra:
		e[k] = extra[k]
	effects.append(e)
	return e


func _find_effect(type: String, key: String = "", value = null):
	for e in effects:
		if e.type != type:
			continue
		if key == "" or e.get(key) == value:
			return e
	return null


func bridge_temp(col: int) -> bool:
	return _find_effect("bridge_temp", "col", col) != null


func bridge_broken(col: int) -> bool:
	return _find_effect("bridge_broken", "col", col) != null


## 桥能不能通行：浮桥优先，其次看是不是断桥
func bridge_open(col: int) -> bool:
	if bridge_temp(col):
		return true
	if Rules.is_bridge_col(col):
		return not bridge_broken(col)
	return false


func is_rooted(piece_id: String) -> bool:
	return _find_effect("root", "pieceId", piece_id) != null


func is_flooded(r: int) -> bool:
	return (r == 5 or r == 6) and _find_effect("flood") != null


func is_shielded(owner: String) -> bool:
	return _find_effect("shield", "owner", owner) != null


func effect_text(e: Dictionary) -> String:
	match e.type:
		"bridge_broken": return "断桥 · 列 %d" % e.col
		"bridge_temp": return "浮桥 · 列 %d" % e.col
		"flood": return "水淹 · 行 5/6 封锁"
		"root":
			var p = find_piece(e.get("pieceId", ""))
			return "绊马索 · %s" % (p.describe() if p != null else "（目标已阵亡）")
		"shield": return "空城计 · %s主将免疫" % Rules.side_name(e.owner)
	return e.type


# ------------------------------------------------------------------ 动作

func do_move(piece_id: String, c: int, r: int) -> bool:
	if phase != "play" or ap < 1 or winner != "":
		return false
	var p = find_piece(piece_id)
	if p == null:
		return false
	# legal_moves 已经滤掉了"送将"着法（见 MoveGen.legal_moves），
	# 所以这里列得出来的都是安全的 —— 被将军时它自动只剩"能解将"的着法。
	if not _has_move(legal_moves(p), c, r):
		return false

	var target = piece_at(c, r)
	if target != null:
		var was_king: bool = target.is_king()
		var target_label: String = target._label()
		_remove(target)
		_log("%s的%s吃掉%s的%s" % [Rules.side_name(p.owner), p._label(),
			Rules.side_name(target.owner), target_label])
		if was_king:
			winner = p.owner
			phase = "over"
			_log("★ %s吃掉了对方主将，获胜！" % Rules.side_name(p.owner))
	p.c = c
	p.r = r
	ap -= 1
	move_used = true        # ← 每回合全盘只能移动一次
	return true


func do_deploy(owner: String, hand_index: int, c: int, r: int) -> bool:
	if phase != "play" or ap < 1 or turn != owner:
		return false
	var snap: Dictionary = _snap_if_needed()
	var card = _card_at(owner, hand_index)
	if card == null:
		return false
	if card.kind != "pawn" and card.kind != "elephant":
		return false
	if card.kind == "elephant" and count_on_board(owner, "elephant") >= ELEPHANT_CAP:
		return false
	var cost: int = 1 if card.kind == "pawn" else 2
	if pop_used(owner) + cost > POP_CAP:
		return false
	if not deploy_cells(owner).has(Vector2i(c, r)):
		return false

	hands[owner].remove_at(hand_index)
	var p = _spawn(owner, card.kind, c, r)
	p.card = card
	ap -= 1
	_log("%s在%s部署了%s（人口 %d/%d）" % [Rules.side_name(owner),
		Rules.cell_name(c, r), card.kind, pop_used(owner), POP_CAP])
	return _finish_action(owner, snap)


func do_equip(owner: String, hand_index: int, piece_id: String) -> bool:
	if phase != "play" or ap < 1 or turn != owner:
		return false
	var snap: Dictionary = _snap_if_needed()
	var card = _card_at(owner, hand_index)
	if card == null or card.kind != "gear":
		return false
	var p = find_piece(piece_id)
	if p == null or p.owner != owner or p.kind != "pawn" or p.gear != "":
		return false
	# 装备只能在主将的指挥范围内进行（作者定稿；规则书 v0.5 尚未收录）
	# 主将不能过河，所以过河的小兵**永远无法再被装备** —— 这是有意的战术后果。
	if not in_command_range(owner, p.c, p.r):
		return false
	if pop_used(owner) + 1 > POP_CAP:      # 装备让该单位 1 → 2 人口
		return false

	hands[owner].remove_at(hand_index)
	p.gear = card.gear
	p.gear_card = card
	ap -= 1
	_log("%s的%s装备了%s，成为%s" % [Rules.side_name(owner), p._label(), card.gear, p.kind_now()])
	return _finish_action(owner, snap)


func do_disband(owner: String, piece_id: String) -> bool:
	if phase != "play" or ap < 1 or turn != owner:
		return false
	var snap: Dictionary = _snap_if_needed()
	var p = find_piece(piece_id)
	if p == null or p.owner != owner:
		return false
	if p.is_king() or p.is_advisor():
		return false                       # 主将与士不能被解散
	var label: String = p._label()
	_remove(p)
	ap -= 1
	_log("%s解散了自己的%s（人口 %d/%d）" % [Rules.side_name(owner), label, pop_used(owner), POP_CAP])
	# 解散也可能解将：典型是它正好挡着对方车的路线，或者它正是对方炮的炮架
	return _finish_action(owner, snap)


# ------------------------------------------------------------------ 锦囊
#
# 【当前范围】只实现 2 种：**增援**、**断桥**。
#   其余 12 种留到流程跑通之后再补；牌库也暂时只放这两种，
#   这样摸到的每一张锦囊都是能打出去的，不会出现「死牌」。
#
# 加一种新锦囊的步骤（机械的四步）：
#   ① SPELL_COST / SPELL_DUR 各加一行
#   ② spell_targets 里加一个分支（决定 UI 高亮什么）
#   ③ _resolve_spell 里加一个分支（真正结算）
#   ④ _build_deck 里放开张数，并补断言

const SPELL_COST := {"增援": 1, "断桥": 1}
const SPELL_DUR := {"增援": 0, "断桥": 3}


## 这张锦囊现在能不能打、需要选什么目标。UI 靠它决定高亮什么。
## 返回 { ok, kind, reason, cells, columns, pieces }
##   kind: none / cell / column
func spell_targets(owner: String, hand_index: int) -> Dictionary:
	var res := {"ok": false, "kind": "none", "reason": "",
		"cells": [], "columns": [], "pieces": []}
	var card = _card_at(owner, hand_index)
	if card == null or card.get("kind", "") != "spell":
		res.reason = "这不是一张锦囊牌"
		return res
	if phase != "play" or winner != "":
		res.reason = "现在不是对局中"
		return res
	if turn != owner:
		res.reason = "还没轮到你"
		return res
	var name: String = card.spell
	if not SPELL_COST.has(name):
		res.reason = "「%s」还没实现" % name
		return res
	if ap < SPELL_COST[name]:
		res.reason = "AP 不足（需要 %d，只剩 %d）" % [SPELL_COST[name], ap]
		return res

	match name:
		"增援":
			if pop_used(owner) + 1 > POP_CAP:
				res.reason = "人口已满"
				return res
			res.kind = "cell"
			res.cells = deploy_cells(owner)
			res.ok = res.cells.size() > 0
			if not res.ok:
				res.reason = "部署区里没有空点"

		"断桥":
			res.kind = "column"
			for col in Rules.BRIDGE_COLS:
				if not bridge_broken(col):
					res.columns.append(col)
			res.ok = res.columns.size() > 0
			if not res.ok:
				res.reason = "三座桥都已经被断了"

	return res


## 打出锦囊。target 按 spell_targets 返回的 kind：
##   cell   -> {"c": int, "r": int}
##   column -> {"col": int}
##   none   -> {}
func do_play_spell(owner: String, hand_index: int, target: Dictionary = {}) -> bool:
	var info: Dictionary = spell_targets(owner, hand_index)
	if not info.ok:
		return false
	var snap: Dictionary = _snap_if_needed()
	var card = _card_at(owner, hand_index)
	var name: String = card.spell

	# 先验证目标、再动手：目标不合法时既不掉 AP 也不弃牌
	if not _resolve_spell(owner, name, target):
		return false

	hands[owner].remove_at(hand_index)
	discard.append(card)
	ap -= SPELL_COST[name]
	# 锦囊也能解将（Q1=甲）。目前实现的两个都不改变将军状态，
	# 但"声东击西 / 移形换位 / 火攻"接进来之后，这一行就是它们的护栏。
	return _finish_action(owner, snap)


func _resolve_spell(owner: String, name: String, target: Dictionary) -> bool:
	match name:
		"增援":
			var c: int = target.get("c", -1)
			var r: int = target.get("r", -1)
			if pop_used(owner) + 1 > POP_CAP:
				return false
			if not deploy_cells(owner).has(Vector2i(c, r)):
				return false
			var p = _spawn(owner, "pawn", c, r)
			p.card = _take_pawn_card(owner)
			_log("%s用「增援」在%s免费部署了一个小兵"
				% [Rules.side_name(owner), Rules.cell_name(c, r)])
			return true

		"断桥":
			var col: int = target.get("col", -1)
			if not Rules.is_bridge_col(col) or bridge_broken(col):
				return false
			add_effect("bridge_broken", SPELL_DUR["断桥"], owner, {"col": col})
			_log("%s用「断桥」炸毁了列 %d 的桥（%d 个回合）"
				% [Rules.side_name(owner), col, SPELL_DUR["断桥"]])
			return true

	return false


## 额外摸牌（1 AP）
func do_draw(owner: String) -> bool:
	if phase != "play" or turn != owner or ap < 1 or winner != "":
		return false
	if deck.is_empty() and discard.is_empty():
		return false
	_draw_cards(owner, 1)
	ap -= 1
	return true


# ------------------------------------------------------------------ 回合

func start_turn(who: String, first: bool = false) -> void:
	turn = who
	ap = AP_PER_TURN
	move_used = false                      # ← 移动机会在整顿阶段重置

	# 统一结算：打出者自己的回合开始时，把自己留下的持续效果各减 1
	var kept: Array = []
	for e in effects:
		if e.by != who:
			kept.append(e)
			continue
		e.left -= 1
		if e.left > 0:
			kept.append(e)
		else:
			_log("「%s」的持续回合数用尽，效果结束。" % effect_text(e))
	effects = kept

	if not first:
		_log("—— 轮到%s（第 %d 回合）——" % [Rules.side_name(who), turn_no])
	_draw_cards(who, 1)

	# 将军结算（放在摸牌之后：先让"应着"的牌到位，再判生死）
	_resolve_check_state(who)


## 回合开始时的将军/将死结算。
## 【顺序很重要】必须在效果递减与摸牌**之后**调用：
##   · 空城计可能在这一刻正好到期（它是在打出者自己的回合开始减 1），到期后主将立刻可能挨将；
##   · 摸牌可能摸到解将的锦囊，所以要先摸再判。
func _resolve_check_state(who: String) -> void:
	if phase != "play" or winner != "":
		return
	if not is_in_check(who):
		return
	if is_checkmate(who):
		winner = Rules.other_side(who)
		phase = "over"
		_log("★ %s被将死，%s获胜！" % [Rules.side_name(who), Rules.side_name(winner)])
		return
	_log("%s被将军！必须本回合解除。" % Rules.side_name(who))


## 结束回合。两种情况结束不了：
##   ① 手牌超过上限 —— 必须先 do_discard 弃到上限（§5.2）
##   ② **还身陷将军** —— "必须应将"（Q3=甲）。解不掉就只能继续尝试，
##      真正无解的局面会在回合开始时被判将死（_resolve_check_state）。
func end_turn() -> bool:
	if winner != "" or phase != "play":
		return false
	if must_discard(turn) > 0:
		return false
	if is_in_check(turn):
		return false
	turn_no += 1
	start_turn(Rules.other_side(turn), false)
	return true


## 还差几张才能结束回合
func must_discard(owner: String) -> int:
	return maxi(0, hands[owner].size() - HAND_LIMIT)


## 弃一张手牌（进共用弃牌堆）
func do_discard(owner: String, hand_index: int) -> bool:
	if phase != "play" or turn != owner:
		return false
	var card = _card_at(owner, hand_index)
	if card == null:
		return false
	hands[owner].remove_at(hand_index)
	discard.append(card)
	return true


# ------------------------------------------------------------------ 内部

func _spawn(owner: String, kind: String, c: int, r: int):
	var p = Piece.new("p%d" % _next_uid(), owner, kind, c, r)
	pieces.append(p)
	return p


func _remove(p) -> void:
	pieces.erase(p)
	if p.is_card_piece():
		if not p.card.is_empty():
			discard.append(p.card)
		if not p.gear_card.is_empty():
			discard.append(p.gear_card)
	# 目标阵亡，挂在它身上的持续效果一并消失
	var kept: Array = []
	for e in effects:
		if e.type == "root" and e.get("pieceId", "") == p.id:
			continue
		kept.append(e)
	effects = kept


## 摸牌。注意：函数名不要叫 _draw —— 那是 Godot 的绘图虚函数名
func _draw_cards(owner: String, n: int) -> void:
	for i in n:
		if deck.is_empty():
			if discard.is_empty():
				return
			deck = discard.duplicate()
			discard.clear()
			_shuffle(deck)
			_log("牌库摸空，弃牌堆洗回牌库。")
		hands[owner].append(deck.pop_back())


## 布阵时从小兵堆里抽一张；找不到就现造一张（保证布阵永远能完成）
func _take_pawn_card(owner: String) -> Dictionary:
	for i in range(deck.size() - 1, -1, -1):
		if deck[i].kind == "pawn":
			return deck.pop_at(i)
	return {"kind": "pawn"}


func _card_at(owner: String, index: int):
	if index < 0 or index >= hands[owner].size():
		return null
	return hands[owner][index]


func _has_move(moves: Array, c: int, r: int) -> bool:
	for m in moves:
		if m.c == c and m.r == r:
			return true
	return false


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _next_uid() -> int:
	_uid += 1
	return _uid


func _log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 300:
		log_lines.pop_front()
