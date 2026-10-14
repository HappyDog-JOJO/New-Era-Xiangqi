extends SceneTree
## 无头测试入口。
##
## 跑法：
##   "D:\Game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" `
##       --headless --path "<项目目录>" --script res://tests/TestRunner.gd
##
## 退出码 0 = 全绿，1 = 有失败。可以直接接进 CI。

const Rules := preload("res://engine/Rules.gd")
const Piece := preload("res://engine/Piece.gd")
const Game := preload("res://engine/Game.gd")

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	print("")
	print("兵符 · Godot 引擎测试")
	print("Godot %s" % Engine.get_version_info().string)
	print("========================================")

	_test_geometry()
	_test_pawn()
	_test_horse()
	_test_chariot_and_cannon()
	_test_king_and_advisor()
	_test_elephant()
	_test_bridge_and_blockade()
	_test_move_once_per_turn()
	_test_setup_and_deck()
	_test_deploy_limits()
	_test_effects_countdown()
	_test_spells()
	_test_hand_limit()
	_test_capture_and_win()
	_test_full_game_flow()

	print("========================================")
	print("%d passed, %d failed" % [_pass, _fail])
	print("")
	quit(1 if _fail > 0 else 0)


# ---------------------------------------------------------------- 断言

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


func has(moves: Array, c: int, r: int) -> bool:
	for m in moves:
		if m.c == c and m.r == r:
			return true
	return false


func cap_of(moves: Array, c: int, r: int) -> String:
	for m in moves:
		if m.c == c and m.r == r:
			return m.cap
	return "<no-move>"


# ---------------------------------------------------------------- 夹具

## 空盘：清掉主将士象，phase 直接进入对局。
## 同时清空牌库，让回合推进不会因为摸牌而干扰计数类测试。
func bare() -> Game:
	var g = Game.new()
	g.new_game(12345)
	g.pieces.clear()
	g.effects.clear()
	g.discard.clear()
	g.deck = []
	g.hands = {"r": [], "b": []}
	g.phase = "play"
	g.turn = "r"
	g.ap = 2
	g.move_used = false
	g.winner = ""
	return g


func put(g: Game, owner: String, kind: String, c: int, r: int, gear := ""):
	var p = Piece.new("t%d" % g._next_uid(), owner, kind, c, r)
	p.gear = gear
	p.card = {"kind": kind}
	g.pieces.append(p)
	return p


# ---------------------------------------------------------------- 用例

func _test_geometry() -> void:
	print("\n=== 棋盘几何 ===")
	ok("棋盘 9×10", Rules.COLS == 9 and Rules.ROWS == 10)
	ok("桥在列 3/5/7", Rules.BRIDGE_COLS == [3, 5, 7])
	ok("(1,1) 在盘内", Rules.in_board(1, 1))
	ok("(10,1) 不在盘内", not Rules.in_board(10, 1))
	ok("红方九宫含 (5,2)", Rules.in_palace("r", 5, 2))
	ok("红方九宫不含 (5,4)", not Rules.in_palace("r", 5, 4))
	ok("黑方九宫含 (5,9)", Rules.in_palace("b", 5, 9))
	ok("红方半场是行 1–5", Rules.own_half("r", 5) and not Rules.own_half("r", 6))
	ok("行5→行6 算过河", Rules.crosses_river(5, 6))
	ok("行5→行4 不算过河", not Rules.crosses_river(5, 4))
	ok("红兵到行6 算已过河", Rules.has_crossed("r", 6))
	ok("红兵到行5 未过河", not Rules.has_crossed("r", 5))


func _test_pawn() -> void:
	print("\n=== 小兵 ===")
	var g = bare()
	var p4 = put(g, "r", "pawn", 4, 5)
	var p3 = put(g, "r", "pawn", 3, 5)
	var p5 = put(g, "r", "pawn", 5, 5)
	ok("列4 的兵不能过河", not has(g.legal_moves(p4), 4, 6))
	ok("列3 的兵可以过桥", has(g.legal_moves(p3), 3, 6))
	ok("列5 的兵可以过桥", has(g.legal_moves(p5), 5, 6))

	var g2 = bare()
	var q = put(g2, "r", "pawn", 5, 1)
	var ms = g2.legal_moves(q)
	ok("底线兵可走 1 格", has(ms, 5, 2))
	ok("底线兵可走 2 格", has(ms, 5, 3))
	ok("未过河不能横走", not has(ms, 4, 1))

	var g3 = bare()
	var r2 = put(g3, "r", "pawn", 5, 1)
	put(g3, "r", "pawn", 5, 2)
	var ms3 = g3.legal_moves(r2)
	ok("前方有子：1 格走不了", not has(ms3, 5, 2))
	ok("前方有子：2 格也走不了", not has(ms3, 5, 3))

	var g4 = bare()
	var crossed_pawn = put(g4, "r", "pawn", 7, 7)
	var ms4 = g4.legal_moves(crossed_pawn)
	ok("过河兵可前/左/右", has(ms4, 7, 8) and has(ms4, 6, 7) and has(ms4, 8, 7))
	ok("过河兵不能后退", not has(ms4, 7, 6))

	var g5 = bare()
	var bp = put(g5, "b", "pawn", 7, 4)
	var ms5 = g5.legal_moves(bp)
	ok("黑卒过河后可横走", has(ms5, 6, 4) and has(ms5, 8, 4))
	ok("黑卒向前是行号减小", has(ms5, 7, 3))


func _test_horse() -> void:
	print("\n=== 骑兵（马）===")
	var g = bare()
	var h = put(g, "r", "horse", 5, 5, "horse")
	var ms = g.legal_moves(h)
	ok("8 个方向", ms.size() == 8, ms.size())
	ok("可跃河 (4,7)", has(ms, 4, 7))
	ok("可跃河 (6,7)", has(ms, 6, 7))

	var g2 = bare()
	var h2 = put(g2, "r", "horse", 5, 5, "horse")
	put(g2, "b", "pawn", 5, 6)          # 蹩马腿
	var ms2 = g2.legal_moves(h2)
	ok("蹩马腿：向上两路被封", not has(ms2, 4, 7) and not has(ms2, 6, 7))
	ok("其余方向仍可走", has(ms2, 3, 4) or has(ms2, 3, 6))


func _test_chariot_and_cannon() -> void:
	print("\n=== 战车 / 炮兵 ===")
	var g = bare()
	var ch = put(g, "r", "chariot", 4, 3, "chariot")
	ok("列4 的车冲不过河", not has(g.legal_moves(ch), 4, 7))
	ok("列4 的车能到河边", has(g.legal_moves(ch), 4, 5))

	var g2 = bare()
	var ch2 = put(g2, "r", "chariot", 3, 3, "chariot")
	ok("列3 的车可以过桥", has(g2.legal_moves(ch2), 3, 7))

	var g3 = bare()
	g3.add_effect("bridge_broken", 3, "b", {"col": 3})
	var ch3 = put(g3, "r", "chariot", 3, 3, "chariot")
	ok("断桥后车过不去", not has(g3.legal_moves(ch3), 3, 7))
	g3.add_effect("bridge_temp", 2, "r", {"col": 3})
	ok("浮桥覆盖断桥后可以过", has(g3.legal_moves(ch3), 3, 7))

	var g4 = bare()
	var ca = put(g4, "r", "cannon", 5, 1, "cannon")
	put(g4, "r", "pawn", 5, 3)                    # 炮架（己方）
	var t1 = put(g4, "b", "pawn", 5, 4)           # 炮架后第一个子 → 可吃
	put(g4, "b", "pawn", 5, 5)                    # 更远一个 → 吃不到
	var ms4 = g4.legal_moves(ca)
	ok("炮不能落在炮架上", not has(ms4, 5, 3))
	ok("炮可走到 (5,2)", has(ms4, 5, 2))
	ok("炮不能越过炮架落空", not has(ms4, 5, 4) or cap_of(ms4, 5, 4) != "")
	ok("炮可吃炮架后第一个子", cap_of(ms4, 5, 4) == t1.id)
	ok("炮吃不到更远的第二个子", not has(ms4, 5, 5))


func _test_king_and_advisor() -> void:
	print("\n=== 主将 / 士 ===")
	var g = bare()
	var k = put(g, "r", "king", 5, 2)
	var ms = g.legal_moves(k)
	ok("帅在中心 4 个走法", ms.size() == 4, ms.size())
	ok("帅不出九宫 (5,4)", not has(ms, 5, 4))

	var g2 = bare()
	var k2 = put(g2, "r", "king", 4, 1)
	ok("帅在角上不能出九宫 (3,1)", not has(g2.legal_moves(k2), 3, 1))

	var g3 = bare()
	var a = put(g3, "r", "advisor", 5, 2)
	var ms3 = g3.legal_moves(a)
	ok("士在中心 4 个走法（四个角）", ms3.size() == 4, ms3.size())
	ok("士不能直走 (5,3)", not has(ms3, 5, 3))

	var g4 = bare()
	var a4 = put(g4, "r", "advisor", 4, 1)
	var ms4 = g4.legal_moves(a4)
	ok("士在角上只能回中心", ms4.size() == 1 and has(ms4, 5, 2), ms4)

	var g5 = bare()
	var a5 = put(g5, "r", "advisor", 5, 2)
	var en = put(g5, "b", "pawn", 4, 1)
	ok("士可以吃闯进九宫的敌人", cap_of(g5.legal_moves(a5), 4, 1) == en.id)


func _test_elephant() -> void:
	print("\n=== 象 ===")
	var g = bare()
	var e = put(g, "r", "elephant", 3, 1)
	var ms = g.legal_moves(e)
	ok("象走田：(1,3) 与 (5,3)", has(ms, 1, 3) and has(ms, 5, 3))
	ok("象在底线 2 个走法", ms.size() == 2, ms.size())

	var g2 = bare()
	var e2 = put(g2, "r", "elephant", 5, 5)
	var ms2 = g2.legal_moves(e2)
	ok("象永不过河", not has(ms2, 3, 7) and not has(ms2, 7, 7))
	ok("象在己方半场仍可走田", has(ms2, 3, 3) and has(ms2, 7, 3))

	var g3 = bare()
	var e3 = put(g3, "r", "elephant", 3, 1)
	put(g3, "b", "pawn", 2, 2)                    # 象眼
	var ms3 = g3.legal_moves(e3)
	ok("塞象眼：走不到 (1,3)", not has(ms3, 1, 3))
	ok("另一侧不受影响 (5,3)", has(ms3, 5, 3))

	var g4 = bare()
	var e4 = put(g4, "b", "elephant", 5, 6)
	var ms4 = g4.legal_moves(e4)
	ok("黑象不过河到行 4", not has(ms4, 3, 4) and not has(ms4, 7, 4))
	ok("黑象可走到行 8", has(ms4, 3, 8) and has(ms4, 7, 8))


func _test_bridge_and_blockade() -> void:
	print("\n=== 象 · 堵桥（v0.5 精确规则）===")
	var g = bare()
	put(g, "b", "elephant", 3, 6)                 # 黑象站在黑方桥头
	var rp = put(g, "r", "pawn", 3, 5)
	ok("河对岸的兵：不能过桥", not has(g.legal_moves(rp), 3, 6))
	ok("河对岸的兵：也吃不掉这头象", not has(g.legal_moves(rp), 3, 6))

	var g2 = bare()
	put(g2, "b", "elephant", 3, 6)
	var rc = put(g2, "r", "chariot", 3, 3, "chariot")
	ok("战车沿列3 过不了河", not has(g2.legal_moves(rc), 3, 6))
	ok("战车仍能到己方桥头 (3,5)", has(g2.legal_moves(rc), 3, 5))

	var g3 = bare()
	put(g3, "b", "elephant", 3, 6)
	var rh = put(g3, "r", "horse", 2, 4, "horse")
	ok("马不受影响：可跃河吃象", cap_of(g3.legal_moves(rh), 3, 6) ==
		g3.piece_at(3, 6).id)

	var g4 = bare()
	var be = put(g4, "b", "elephant", 3, 6)
	var crossed_ch = put(g4, "r", "chariot", 5, 6, "chariot")   # 已从别的桥过河
	ok("已过河的棋子可以吃掉象", cap_of(g4.legal_moves(crossed_ch), 3, 6) == be.id)

	var g5 = bare()
	put(g5, "b", "elephant", 5, 8)                # 象在自家半场，但不在桥头
	var ch5 = put(g5, "r", "chariot", 5, 3, "chariot")
	ok("象不在桥头就不堵桥", has(g5.legal_moves(ch5), 5, 7))


func _test_move_once_per_turn() -> void:
	print("\n=== 每回合全盘只能移动一次 ===")
	var g = bare()
	var a = put(g, "r", "pawn", 1, 3)
	var b = put(g, "r", "pawn", 2, 3)
	ok("未移动时有走法", g.legal_moves(a).size() > 0)
	ok("移动后 move_used 置位", g.do_move(a.id, 1, 4) and g.move_used)
	ok("同一棋子不能再动", g.legal_moves(a).size() == 0)
	ok("别的棋子也不能动（全盘一次）", g.legal_moves(b).size() == 0)
	ok("剩余 AP 仍有 1", g.ap == 1)
	ok("但可以部署（移动名额与 AP 是两回事）", _can_deploy_after_move())

	var g2 = bare()
	var c2 = put(g2, "r", "pawn", 1, 3)
	g2.start_turn("r", true)
	ok("新回合重置 move_used", not g2.move_used and g2.legal_moves(c2).size() > 0)


func _can_deploy_after_move() -> bool:
	var g = bare()
	put(g, "r", "king", 5, 2)
	var p = put(g, "r", "pawn", 1, 3)
	g.do_move(p.id, 1, 4)
	g.hands.r = [{"kind": "pawn"}]
	g.ap = 2
	return g.do_deploy("r", 0, 5, 1)


func _test_setup_and_deck() -> void:
	print("\n=== 开局 / 牌库（v0.5）===")
	var g = Game.new()
	g.new_game(1)
	ok("牌库共 60 张", g.deck.size() + g.hands.r.size() + g.hands.b.size() == 60,
		g.deck.size() + g.hands.r.size() + g.hands.b.size())
	ok("开局就有红帅", g.king_of("r") != null and g.king_of("r").c == 5 and g.king_of("r").r == 2)
	ok("开局就有黑将", g.king_of("b") != null and g.king_of("b").r == 9)
	ok("每方自带 2 个士", g.count_on_board("r", "advisor") == 2 and g.count_on_board("b", "advisor") == 2)
	ok("红士在 (4,1)(6,1)", g.piece_at(4, 1) != null and g.piece_at(4, 1).is_advisor()
		and g.piece_at(6, 1) != null and g.piece_at(6, 1).is_advisor())
	ok("黑士在 (4,10)(6,10)", g.piece_at(4, 10) != null and g.piece_at(4, 10).is_advisor())
	ok("先手 4 张 / 后手 5 张", g.hands.r.size() == 4 and g.hands.b.size() == 5)
	ok("主将与士不占人口", g.pop_used("r") == 0)
	ok("主将与士不是卡牌棋子", not g.king_of("r").is_card_piece()
		and not g.piece_at(4, 1).is_card_piece())

	# 牌库里没有士
	var deck_all: Array = g.deck.duplicate()
	deck_all.append_array(g.hands.r)
	deck_all.append_array(g.hands.b)
	var advisors := 0
	var elephants := 0
	var pawns := 0
	for c in deck_all:
		if c.get("kind", "") == "advisor":
			advisors += 1
		elif c.get("kind", "") == "elephant":
			elephants += 1
		elif c.get("kind", "") == "pawn":
			pawns += 1
	ok("牌库里没有士牌", advisors == 0, advisors)
	ok("象 3 张", elephants == 3, elephants)
	ok("小兵 21 张（含被吃掉前的）", pawns == 21, pawns)

	# 布阵流程
	var g2 = Game.new()
	g2.new_game(7)
	for v in [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5)]:
		g2.setup_deploy("r", v.x, v.y)
	ok("红方放下 3 个后轮到黑方", g2.deploy_turn == "b" and g2.deploy_left.r == 0)
	ok("黑方不能放在红方半场", not g2.setup_deploy("b", 5, 3))
	for v in [Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6)]:
		g2.setup_deploy("b", v.x, v.y)
	ok("布阵完毕进入对局", g2.phase == "play")
	ok("进入对局后红方已摸牌", g2.hands.r.size() >= 4)


func _test_deploy_limits() -> void:
	print("\n=== 部署区 / 人口 / 象上限 ===")
	var g = bare()
	put(g, "r", "king", 5, 2)
	var cells = g.deploy_cells("r")
	ok("红帅起始部署区 11 格", cells.size() == 11, cells.size())
	ok("部署区不过河", not cells.has(Vector2i(5, 6)))
	ok("部署区含 (5,4)", cells.has(Vector2i(5, 4)))
	ok("部署区不含 (5,5)", not cells.has(Vector2i(5, 5)))

	var g2 = bare()
	var k2 = put(g2, "r", "king", 5, 4)
	ok("主将前压后部署区推进（含 (5,5)）", g2.deploy_cells("r").has(Vector2i(5, 5)))
	ok("部署区仍不过河（不含 (5,6)）", not g2.deploy_cells("r").has(Vector2i(5, 6)))

	var g3 = bare()
	put(g3, "r", "king", 5, 2)
	g3.hands.r = [{"kind": "pawn"}, {"kind": "pawn"}, {"kind": "pawn"},
		{"kind": "pawn"}, {"kind": "pawn"}, {"kind": "pawn"}, {"kind": "pawn"}, {"kind": "pawn"}]
	var placed := 0
	for v in [Vector2i(5, 1), Vector2i(4, 1), Vector2i(6, 1), Vector2i(4, 2),
			Vector2i(6, 2), Vector2i(5, 3), Vector2i(4, 3), Vector2i(6, 3)]:
		g3.ap = 2
		if g3.do_deploy("r", 0, v.x, v.y):
			placed += 1
	ok("满编 8 人口可放 8 个小兵", placed == 8 and g3.pop_used("r") == 8, [placed, g3.pop_used("r")])
	g3.ap = 2
	g3.hands.r = [{"kind": "pawn"}]
	ok("满编后不能再部署", not g3.do_deploy("r", 0, 3, 2))

	var g4 = bare()
	put(g4, "r", "king", 5, 2)
	g4.hands.r = [{"kind": "pawn"}, {"kind": "gear", "gear": "chariot"}]
	g4.do_deploy("r", 0, 5, 1)
	var target = g4.piece_at(5, 1)
	g4.ap = 2
	ok("装备成功，人口 1 → 2", g4.do_equip("r", 0, target.id) and g4.pop_used("r") == 2)

	# —— 装备名必须都是 MoveGen 认识的兵种 ——
	# 起因：做界面验收时我把 gear 写成了中文「马」，结果 kind_now() 返回一个
	# MoveGen 不认识的字符串，legal_moves 直接返回空数组**而且不报任何错** ——
	# 那个子静默地变成了一块石头。这种坑必须有断言拦着。
	var all_cards: Array = Game.new()._build_deck()
	ok("一副牌 60 张", all_cards.size() == 60, all_cards.size())
	var bad_gear: Array = []
	for card in all_cards:
		if card.get("kind", "") == "gear" and not ["horse", "chariot", "cannon"].has(card.gear):
			bad_gear.append(card.gear)
	ok("牌库里的装备名都是已知兵种", bad_gear.is_empty(), bad_gear)

	for gn in ["horse", "chariot", "cannon"]:
		var ge = bare()
		put(ge, "r", "king", 5, 2)
		ge.hands.r = [{"kind": "pawn"}, {"kind": "gear", "gear": gn}]
		ge.do_deploy("r", 0, 5, 1)
		var t2 = ge.piece_at(5, 1)
		ge.ap = 2
		ge.do_equip("r", 0, t2.id)
		ok("装上「%s」之后这个子真的走得动" % gn, ge.legal_moves(t2).size() > 0,
			ge.legal_moves(t2).size())
		ok("「%s」的角标有字可写" % gn, t2.gear_label() != "装", t2.gear_label())

	# —— 装备的指挥范围限制（作者定稿：小兵必须在主将曼哈顿 ≤ 2 内）——
	# 规则书 v0.5 的 §3.2 / §7.2 都还没写这条，只在作者口述里，所以这里钉死防止回退。
	print("\n=== 装备的指挥范围 ===")
	var gr = bare()
	var gk = put(gr, "r", "king", 5, 2)
	var near_p = put(gr, "r", "pawn", 5, 4)      # 曼哈顿 2，正好在边界上
	var far_p = put(gr, "r", "pawn", 1, 5)       # 曼哈顿 7，范围外
	ok("曼哈顿 2 算在范围内（边界含）", gr.in_command_range("r", 5, 4))
	ok("曼哈顿 3 不算在范围内", not gr.in_command_range("r", 5, 5))
	ok("主将自身那一格算在范围内（距离 0）", gr.in_command_range("r", 5, 2))
	# 规则书 §2.3：指挥范围是「以主将为中心的菱形」，形状完整时 13 点。
	# 红帅在 (5,2) 时行 0 不存在，所以盘内只剩 12 点 —— 这里把这个差也钉住，
	# 免得以后有人写了「恒等于 13」的注释而被误导。
	var diamond: int = 0
	for dc in range(-2, 3):
		for dr in range(-2, 3):
			if abs(dc) + abs(dr) <= 2 and Rules.in_board(gk.c + dc, gk.r + dr):
				diamond += 1
	ok("红帅在 (5,2)：盘内指挥范围 12 点（完整菱形 13，行 0 出盘）", diamond == 12, diamond)
	var mid_king = put(gr, "b", "king", 5, 6)     # 棋盘中部，菱形完整
	var full: int = 0
	for dc in range(-2, 3):
		for dr in range(-2, 3):
			if abs(dc) + abs(dr) <= 2 and Rules.in_board(5 + dc, 6 + dr):
				full += 1
	ok("主将在棋盘中部 (5,6)：菱形完整 13 点（规则书 §2.3）", full == 13, full)
	# 部署区 ⊆ 指挥范围：部署区里不可能出现范围外的点
	var all_in: bool = true
	for v in gr.deploy_cells("r"):
		if not gr.in_command_range("r", v.x, v.y):
			all_in = false
	ok("部署区 ⊆ 指挥范围（§2.3）", all_in)

	gr.hands.r = [{"kind": "gear", "gear": "horse"}, {"kind": "gear", "gear": "horse"}]
	gr.ap = 2
	ok("范围内的小兵可以装备", gr.do_equip("r", 0, near_p.id))
	var hand_before: int = gr.hands.r.size()     # 上面成功了一次，这里只剩 1 张
	gr.ap = 2
	ok("范围外的小兵装不了", not gr.do_equip("r", 0, far_p.id))
	ok("被拒绝时不掉 AP", gr.ap == 2, gr.ap)
	ok("被拒绝时不弃牌", gr.hands.r.size() == hand_before, [gr.hands.r.size(), hand_before])

	# —— 主将一移动，同一个兵的「能不能装」立刻翻转 ——
	# 这条是关键：证明判定用的是**主将当前位置**，而不是小兵被部署时的那个区域。
	var gm = bare()
	var mk = put(gm, "r", "king", 5, 2)
	var mp = put(gm, "r", "pawn", 5, 4)          # 离帅曼哈顿 2 → 可装
	gm.hands.r = [{"kind": "gear", "gear": "chariot"}]
	ok("主将在 (5,2) 时，兵在范围内", gm.in_command_range("r", mp.c, mp.r))
	mk.r = 1                                    # 主将退到底线
	ok("主将退到 (5,1) 后，同一个兵出范围",
		not gm.in_command_range("r", mp.c, mp.r))
	gm.ap = 2
	ok("于是这个兵装不了了", not gm.do_equip("r", 0, mp.id))
	mk.r = 2                                    # 主将回来
	ok("主将回到 (5,2) 后，又能装了", gm.in_command_range("r", mp.c, mp.r))

	# —— 过河的兵永远无法再被装备（主将不能过河）——
	var gc = bare()
	put(gc, "r", "king", 5, 2)
	var crossed = put(gc, "r", "pawn", 5, 7)
	gc.hands.r = [{"kind": "gear", "gear": "cannon"}]
	gc.ap = 2
	ok("过河的小兵装不了装备", not gc.do_equip("r", 0, crossed.id))

	var g5 = bare()
	put(g5, "r", "king", 5, 2)
	g5.hands.r = [{"kind": "elephant"}, {"kind": "elephant"}, {"kind": "elephant"}]
	for v in [Vector2i(4, 1), Vector2i(6, 1)]:
		g5.ap = 2
		g5.do_deploy("r", 0, v.x, v.y)
	ok("象可以放 2 个", g5.count_on_board("r", "elephant") == 2)
	g5.ap = 2
	ok("第 3 个象被拦下", not g5.do_deploy("r", 0, 5, 1))
	ok("被拦下时不扣 AP", g5.ap == 2)

	var g6 = bare()
	put(g6, "r", "king", 5, 2)
	var dp = put(g6, "r", "pawn", 5, 1)
	g6.do_disband("r", dp.id)
	ok("解散释放人口", g6.pop_used("r") == 0 and g6.find_piece(dp.id) == null)
	ok("解散小兵不扣 AP 之外的代价", g6.ap == 1)


func _test_effects_countdown() -> void:
	print("\n=== 持续效果：统一回合计数 ===")
	var g = bare()
	put(g, "r", "king", 5, 2)
	put(g, "b", "king", 5, 9)
	var bh = put(g, "b", "horse", 5, 8, "horse")

	g.add_effect("root", 2, "r", {"pieceId": bh.id})
	ok("绊马索：目标不能动", g.legal_moves(bh).size() == 0)
	g.end_turn()
	ok("黑方第 1 个回合仍被缚", g.legal_moves(bh).size() == 0)
	g.end_turn()   # 回到红方：红方自己的效果 -1
	ok("对手回合不衰减（红方回合才减）", g.is_rooted(bh.id))
	g.end_turn()   # 黑方第 2 个回合
	ok("黑方第 2 个回合仍被缚", g.legal_moves(bh).size() == 0)
	g.end_turn()   # 红方：减到 0
	g.end_turn()   # 黑方第 3 个回合
	ok("黑方第 3 个回合已挣脱", not g.is_rooted(bh.id) and g.legal_moves(bh).size() > 0)

	var g2 = bare()
	put(g2, "r", "king", 5, 2)
	put(g2, "b", "king", 5, 9)
	var rp = put(g2, "r", "pawn", 3, 5)
	g2.add_effect("bridge_broken", 3, "r", {"col": 3})
	ok("打出当回合：桥是断的", not has(g2.legal_moves(rp), 3, 6))
	var blocked: Array = []
	for i in 8:
		g2.end_turn()
		if g2.turn == "b":
			blocked.append(not has(g2.legal_moves(rp), 3, 6))
	ok("断桥 3 回合 = 对手连续 3 个回合过不去，第 4 个恢复",
		blocked == [true, true, true, false], blocked)

	var g3 = bare()
	put(g3, "r", "king", 5, 2)
	var p5 = put(g3, "r", "pawn", 5, 5)
	var p3 = put(g3, "r", "pawn", 3, 3)
	g3.add_effect("flood", 1, "r")
	ok("水淹：行5 不能动", g3.legal_moves(p5).size() == 0)
	ok("水淹：行3 不受影响", g3.legal_moves(p3).size() > 0)

	var g4 = bare()
	var target = put(g4, "b", "horse", 5, 8, "horse")
	g4.add_effect("root", 2, "r", {"pieceId": target.id})
	g4._remove(target)
	ok("目标阵亡后效果不再残留", not g4.is_rooted(target.id))


## 干净局面：轮红方、双方主将在位、手牌由参数指定
func with_hand(cards: Array) -> Game:
	var g = bare()
	put(g, "r", "king", 5, 2)
	put(g, "b", "king", 5, 9)
	g.hands.r = cards
	g.ap = 2
	return g


func _spell(name: String) -> Dictionary:
	return {"kind": "spell", "spell": name}


func _test_spells() -> void:
	print("\n=== 锦囊（当前只实现 2 种）===")
	ok("增援 1 AP", Game.SPELL_COST["增援"] == 1)
	ok("断桥 1 AP", Game.SPELL_COST["断桥"] == 1)
	ok("断桥 3 回合", Game.SPELL_DUR["断桥"] == 3)
	var unimplemented = with_hand([{"kind": "spell", "spell": "火攻"}])
	ok("未实现的锦囊打不出", not unimplemented.spell_targets("r", 0).ok)
	ok("并且说明原因", unimplemented.spell_targets("r", 0).reason.contains("还没实现"))
	var gdeck = Game.new()
	gdeck.new_game(1)
	var kinds: Array = _deck_spell_kinds(gdeck)
	ok("牌库里只有已实现的两种锦囊（增援 / 断桥）",
		_same_strings(kinds, ["增援", "断桥"]), kinds)

	print("\n=== 锦囊 · 增援 ===")
	var g = with_hand([_spell("增援")])
	var t = g.spell_targets("r", 0)
	ok("可以打，要选格子", t.ok and t.kind == "cell")
	ok("可部署格 11 个", t.cells.size() == 11, t.cells.size())
	ok("打出成功", g.do_play_spell("r", 0, {"c": 5, "r": 1}))
	ok("场上多了个小兵", g.piece_at(5, 1) != null and g.piece_at(5, 1).kind == "pawn")
	ok("占 1 人口", g.pop_used("r") == 1)
	ok("扣 1 AP", g.ap == 1)
	ok("锦囊进弃牌堆", g.discard.size() == 1)
	ok("新兵当回合就能移动（不算已移动）", not g.move_used)
	ok("落在部署区外 → 打不出，且不扣 AP",
		not with_hand([_spell("增援")]).spell_targets("r", 0).cells.has(Vector2i(9, 9)))
	var gfull = with_hand([_spell("增援")])
	for i in 8:
		put(gfull, "r", "pawn", i + 1, 5)     # 塞满 8 人口（行 5 在部署区外）
	ok("人口满时打不出", not gfull.spell_targets("r", 0).ok)

	print("\n=== 锦囊 · 断桥 ===")
	var g3 = with_hand([_spell("断桥"), _spell("断桥")])
	var t3 = g3.spell_targets("r", 0)
	ok("要选列，3 个候选", t3.ok and t3.kind == "column" and t3.columns.size() == 3)
	ok("打出成功", g3.do_play_spell("r", 0, {"col": 3}))
	ok("列 3 断了", not g3.bridge_open(3))
	ok("效果剩 3 回合", g3._find_effect("bridge_broken", "col", 3).left == 3)
	ok("同一列不能再断", not g3.do_play_spell("r", 0, {"col": 3}))
	ok("失败时不扣 AP", g3.ap == 1)
	ok("失败时牌还在手上", g3.hands.r.size() == 1)
	ok("其余两列仍可选", g3.spell_targets("r", 0).columns.size() == 2)
	ok("断桥不算移动", not g3.move_used)


func _deck_spell_kinds(g: Game) -> Array:
	var kinds: Array = []
	for c in g.deck:
		if c.get("kind", "") == "spell" and not kinds.has(c.spell):
			kinds.append(c.spell)
	kinds.sort()
	return kinds


func _same_strings(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


func _test_hand_limit() -> void:
	print("\n=== 手牌上限：超额必须弃牌 ===")
	var g = bare()
	var six: Array = []
	for i in 6:
		six.append({"kind": "pawn"})
	g.hands.r = six
	ok("超额 1 张时结束不了回合", g.must_discard("r") == 1 and not g.end_turn())
	ok("回合仍在红方手上", g.turn == "r")
	ok("弃 1 张后手牌到位", g.do_discard("r", 0) and g.must_discard("r") == 0)
	ok("弃掉的牌进弃牌堆", g.discard.size() == 1, g.discard.size())
	ok("然后可以结束回合", g.end_turn())
	ok("回合交给了黑方", g.turn == "b")

	var g2 = bare()
	g2.hands.r = []
	ok("没超额时可以直接结束回合", g2.end_turn())


## 完整流程：布阵 → 用最朴素的策略连续推进若干回合，检查不卡死、状态自洽
func _test_full_game_flow() -> void:
	print("\n=== 完整流程：布阵 → 连续推进 ===")
	var g = Game.new()
	g.new_game(2026)

	ok("布阵前是布阵阶段", g.phase == "deploy")
	for v in [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5)]:
		g.setup_deploy("r", v.x, v.y)
	for v in [Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6)]:
		g.setup_deploy("b", v.x, v.y)
	ok("布阵完成进入对局", g.phase == "play")
	ok("红方先手", g.turn == "r")

	var turns: int = 0
	for t in 40:
		if g.winner != "":
			break
		var who: String = g.turn
		# ① 能部署就部署
		for i in g.hands[who].size():
			var card = g.hands[who][i]
			if card.get("kind", "") == "pawn" or card.get("kind", "") == "elephant":
				var cells = g.deploy_cells(who)
				if cells.size() > 0 and g.do_deploy(who, i, cells[0].x, cells[0].y):
					break
		# ② 否则随便走一步（每回合只有一次机会）
		if not g.move_used:
			for p in g.pieces:
				if p.owner != who:
					continue
				var ms = g.legal_moves(p)
				if ms.size() > 0:
					g.do_move(p.id, ms[0].c, ms[0].r)
					break
		# ③ 手牌超额必须弃到上限
		while g.must_discard(who) > 0:
			g.do_discard(who, 0)
		# ④ 结束回合
		if not g.end_turn():
			break
		turns += 1

	ok("连续推进了 %d 个回合没有卡死" % turns, turns >= 20, turns)
	ok("回合计数同步推进", g.turn_no >= turns)
	ok("盘上棋子不重叠", _no_overlap(g))
	# 注：轮到谁，谁就刚摸完 1 张，所以上限内最多是 HAND_LIMIT + 1
	ok("手牌没有无限累积",
		g.hands.r.size() <= Game.HAND_LIMIT + 1 and g.hands.b.size() <= Game.HAND_LIMIT + 1,
		[g.hands.r.size(), g.hands.b.size()])
	ok("双方主将都还在（40 回合内没被吃掉也算正常）",
		g.king_of("r") != null and g.king_of("b") != null)
	ok("每个棋子都在盘内", _all_on_board(g))
	ok("牌没有凭空消失", _card_conservation(g))


func _no_overlap(g: Game) -> bool:
	var seen := {}
	for p in g.pieces:
		var k: int = p.c * 100 + p.r
		if seen.has(k):
			return false
		seen[k] = true
	return true


func _all_on_board(g: Game) -> bool:
	for p in g.pieces:
		if not Rules.in_board(p.c, p.r):
			return false
	return true


## 牌的总数守恒：场上棋子的牌 + 牌库 + 弃牌堆 + 双方手牌 应该等于开局的总数
func _card_conservation(g: Game) -> bool:
	var n: int = g.deck.size() + g.discard.size() + g.hands.r.size() + g.hands.b.size()
	for p in g.pieces:
		if p.is_card_piece():
			n += 1
			if not p.gear_card.is_empty():
				n += 1
	# 开局牌库 60，布阵从小兵堆里拿走 6 张变成棋子，所以场上+库+弃+手 = 60
	return n == 60


func _test_capture_and_win() -> void:
	print("\n=== 吃子 / 胜负 / 弃牌 ===")
	var g = bare()
	var ch = put(g, "r", "chariot", 5, 1, "chariot")
	var k = put(g, "b", "king", 5, 9)
	ok("战车可直取 (5,9)", has(g.legal_moves(ch), 5, 9))
	g.do_move(ch.id, 5, 9)
	ok("吃掉主将判红方胜", g.winner == "r", g.winner)
	ok("主将从盘上移除", g.find_piece(k.id) == null)
	ok("主将不进弃牌堆", g.discard.size() == 0, g.discard.size())

	var g2 = bare()
	var a = put(g2, "r", "pawn", 1, 1)
	put(g2, "r", "pawn", 1, 2)
	var ms = g2.legal_moves(a)
	ok("不能走/吃己方单位", not has(ms, 1, 2) and not has(ms, 1, 3))

	var g3 = bare()
	var big = put(g3, "r", "chariot", 5, 1, "chariot")
	big.gear_card = {"kind": "gear", "gear": "chariot"}
	var victim = put(g3, "b", "pawn", 5, 3)
	victim.gear = "horse"
	victim.gear_card = {"kind": "gear", "gear": "horse"}
	g3.do_move(big.id, 5, 3)
	ok("被吃单位连同装备一起进弃牌堆", g3.discard.size() == 2, g3.discard.size())

	var g4 = bare()
	put(g4, "r", "king", 5, 2)
	var guard = put(g4, "r", "advisor", 4, 1)
	var enemy = put(g4, "b", "chariot", 5, 9, "chariot")
	g4.turn = "b"
	g4.move_used = false
	g4.do_move(enemy.id, 5, 2)
	ok("士不再代死（护驾已取消）", g4.winner == "b", g4.winner)
	ok("士还在盘上", g4.find_piece(guard.id) != null)

	var g5 = bare()
	var k5 = put(g5, "r", "king", 5, 2)
	var e5 = put(g5, "b", "chariot", 5, 9, "chariot")
	g5.add_effect("shield", 1, "r", {"owner": "r"})
	g5.turn = "b"
	ok("空城计期间吃不到主将", not has(g5.legal_moves(e5), 5, 2))
