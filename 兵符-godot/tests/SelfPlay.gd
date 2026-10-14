extends SceneTree
## 自对弈：用贪心策略把一局从布阵打到分出胜负。
##
## 三个目的：
##   ① 让「2 人局能从头打到分出胜负」变成可复现的事实，而不只是一句声明
##   ② 顺带量出「一局大概多少回合」—— 这正是设计上最关心的节奏问题（§4 试玩计划第 0 问）
##   ③ 这套贪心策略就是以后 AI 对手的雏形
##
## 跑法：godot --headless --path <项目> --script res://tests/SelfPlay.gd

const Game := preload("res://engine/Game.gd")
const Rules := preload("res://engine/Rules.gd")

const MAX_TURNS := 400
const SEEDS := [1, 7, 2026, 99, 512, 31337]

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	print("")
	print("兵符 · 自对弈（2 人局能不能分出胜负）")
	print("========================================")

	var wins: int = 0
	var turns_list: Array = []
	var all_consistent: bool = true
	var all_by_capture: bool = true

	for s in SEEDS:
		var r: Dictionary = play_one(s)
		turns_list.append(r.turns)
		if r.winner != "":
			wins += 1
			if not r.by_capture:
				all_by_capture = false
		if not r.consistent:
			all_consistent = false
		print("  种子 %-7d %-16s %4d 回合%s" % [
			s,
			("★ %s胜" % Rules.side_name(r.winner)) if r.winner != "" else "—— 未分胜负",
			r.turns,
			"" if r.consistent else "   [状态异常]",
		])

	print("")
	ok("%d 局里至少有一局分出胜负（%d/%d）" % [SEEDS.size(), wins, SEEDS.size()], wins > 0)
	ok("分出胜负的局都是靠吃掉主将", all_by_capture)
	ok("每一局全程状态自洽（不重叠 / 不越界 / 牌数守恒）", all_consistent)

	if wins > 0:
		var finished: Array = []
		for i in SEEDS.size():
			if turns_list[i] < MAX_TURNS:
				finished.append(turns_list[i])
		var total: int = 0
		for t in finished:
			total += t
		if finished.size() > 0:
			print("  → 分出胜负的 %d 局，平均 %.0f 回合/局，最快 %d、最慢 %d"
				% [finished.size(), float(total) / float(finished.size()),
				finished.min(), finished.max()])

	_finish()


## 打完整一局，返回 { winner, turns, consistent, by_capture }
func play_one(seed_value: int) -> Dictionary:
	var g = Game.new()
	g.new_game(seed_value)

	# 布阵：双方对称，各自把 3 个兵顶到河岸的桥头位置
	for v in [Vector2i(3, 5), Vector2i(5, 5), Vector2i(7, 5)]:
		g.setup_deploy("r", v.x, v.y)
	for v in [Vector2i(3, 6), Vector2i(5, 6), Vector2i(7, 6)]:
		g.setup_deploy("b", v.x, v.y)

	var consistent: bool = g.phase == "play" and _sane(g)
	var turns: int = 0

	while g.winner == "" and turns < MAX_TURNS:
		var who: String = g.turn
		# 一回合 2 AP，能做多少做多少
		for step in Game.AP_PER_TURN:
			if g.winner != "":
				break
			if not act_once(g, who):
				break
		if g.winner != "":
			break                       # 已经分出胜负，不需要再收尾
		# 手牌超额必须弃到上限，否则 end_turn 会被拦下
		while g.must_discard(who) > 0:
			if not g.do_discard(who, 0):
				consistent = false
				break                   # 必须有退出条件：对局结束后 do_discard 会拒绝
		if not g.end_turn():
			consistent = false
			break
		turns += 1
		if not _sane(g):
			consistent = false
			break

	var by_capture: bool = true
	if g.winner != "":
		by_capture = g.king_of(Rules.other_side(g.winner)) == null

	return {"winner": g.winner, "turns": turns, "consistent": consistent, "by_capture": by_capture}


## 走一步（1 AP）。做不了事就返回 false
func act_once(g, who: String) -> bool:
	# ① 移动（每回合全盘只有一次机会）
	if not g.move_used:
		var mv: Dictionary = pick_move(g, who)
		if not mv.is_empty():
			return g.do_move(mv.pid, mv.c, mv.r)
	# ② 人口满了先清理卡死的兵
	#    （小兵过河前不能横走，落在非桥列就永久卡死，还照样占人口）
	if g.pop_used(who) >= Game.POP_CAP:
		var stuck: String = pick_disband(g, who)
		if stuck != "":
			return g.do_disband(who, stuck)
	# ③ 部署
	var di: int = pick_deploy(g, who)
	if di >= 0:
		var cell: Vector2i = pick_deploy_cell(g, who)
		if cell.x > 0:
			return g.do_deploy(who, di, cell.x, cell.y)
	# ④ 实在没事做就多摸一张
	return g.do_draw(who)


## 找一个小兵：还在己方半场、又不在桥列 —— 它永远过不了河，是纯废子
func pick_disband(g, who: String) -> String:
	for p in g.pieces:
		if p.owner != who or p.kind != "pawn" or p.gear != "":
			continue
		if Rules.has_crossed(who, p.r):
			continue
		if Rules.is_bridge_col(p.c):
			continue
		return p.id
	return ""


## 部署位置：优先桥列，其次越靠近河越好
func pick_deploy_cell(g, who: String) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score: int = -9999
	for v in g.deploy_cells(who):
		var score: int = 0
		if Rules.is_bridge_col(v.x):
			score += 100
		score += v.y if who == "r" else (Rules.ROWS + 1 - v.y)
		if score > best_score:
			best_score = score
			best = v
	return best


## 贪心策略：吃主将 > 划算的吃子 > 朝对方主将推进
func pick_move(g, who: String) -> Dictionary:
	var enemy: String = Rules.other_side(who)

	# ① 能直接吃主将就吃
	for p in g.pieces:
		if p.owner != who:
			continue
		for m in g.legal_moves(p):
			if m.cap == "":
				continue
			var t = g.find_piece(m.cap)
			if t != null and t.is_king():
				return {"pid": p.id, "c": m.c, "r": m.r}

	# ② 划算的吃子：目标价值 >= 自己价值；
	#    例外：凡是在对方九宫里的吃子都值得 —— 那是唯一能摸到主将的路
	var best: Dictionary = {}
	var best_gain: int = -99
	for p in g.pieces:
		if p.owner != who:
			continue
		for m in g.legal_moves(p):
			if m.cap == "":
				continue
			var t = g.find_piece(m.cap)
			if t == null:
				continue
			var gain: int = value_of(t) - value_of(p)
			if Rules.in_palace(t.owner, t.c, t.r):
				gain = maxi(gain, 1)
			if gain >= 0 and gain > best_gain:
				best_gain = gain
				best = {"pid": p.id, "c": m.c, "r": m.r}
	if not best.is_empty():
		return best

	# ③ 朝对方主将推进（不动自己的主将）
	var ek = g.king_of(enemy)
	if ek == null:
		return {}
	var best_d: int = 9999
	var adv: Dictionary = {}
	for p in g.pieces:
		if p.owner != who or p.is_king():
			continue
		for m in g.legal_moves(p):
			if m.cap != "":
				continue                    # 不划算的吃子就算了
			var d: int = _advance_cost(p, m.c, m.r, ek)
			if d < best_d:
				best_d = d
				adv = {"pid": p.id, "c": m.c, "r": m.r}
	return adv


## 推进代价：离对方主将越近越好，但**必须惩罚"往非桥列靠河"**
## 因为小兵过河前不能横走，落在非桥列就是永久卡死
func _advance_cost(p, c: int, r: int, ek) -> int:
	var d: int = abs(c - ek.c) + abs(r - ek.r)
	var kind: String = p.kind_now()
	if kind != "horse" and not Rules.has_crossed(p.owner, r):
		if not Rules.is_bridge_col(c):
			d += 40 if kind == "pawn" else 8
	return d


## 手上第一张能部署的兵种牌
func pick_deploy(g, who: String) -> int:
	var hand: Array = g.hands[who]
	for i in hand.size():
		var k: String = hand[i].get("kind", "")
		if k == "pawn" or k == "elephant":
			return i
	return -1


func value_of(p) -> int:
	match p.kind_now():
		"chariot": return 9
		"cannon": return 5
		"horse": return 4
		"advisor": return 2
		"elephant": return 2
		"pawn": return 1
	return 0


## 状态自洽检查：棋子不重叠、都在盘内、牌数守恒
func _sane(g) -> bool:
	var seen := {}
	for p in g.pieces:
		if not Rules.in_board(p.c, p.r):
			return false
		var k: int = p.c * 100 + p.r
		if seen.has(k):
			return false
		seen[k] = true
	var n: int = g.deck.size() + g.discard.size() + g.hands.r.size() + g.hands.b.size()
	for p in g.pieces:
		if p.is_card_piece():
			n += 1
			if not p.gear_card.is_empty():
				n += 1
	return n == 60


func ok(title: String, cond: bool, extra = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % title)
	else:
		_fail += 1
		if str(extra) == "":
			print("  FAIL  %s" % title)
		else:
			print("  FAIL  %s   -> %s" % [title, str(extra)])


func _finish() -> void:
	print("========================================")
	print("%d passed, %d failed" % [_pass, _fail])
	print("")
	quit(1 if _fail > 0 else 0)
