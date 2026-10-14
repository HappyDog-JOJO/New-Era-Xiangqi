extends SceneTree
## 界面冒烟测试：无头加载主场景，直接调用交互方法，
## 验证「点棋盘 / 点手牌 / 结束回合」这条链路真的接到了引擎上。
##
## 跑法：
##   godot --headless --path <项目> --script res://tests/UiSmoke.gd

const Rules := preload("res://engine/Rules.gd")

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	print("")
	print("兵符 · 界面冒烟测试")
	print("========================================")

	var packed = load("res://scenes/Main.tscn")
	ok("主场景能加载", packed != null)
	if packed == null:
		_finish()
		return

	var main = packed.instantiate()
	root.add_child(main)          # 触发 _enter_tree（_ready 可能要等第一帧）
	main.setup()                  # 幂等，保证无头环境下也完成初始化
	ok("场景就绪，引擎已创建", main.game != null)
	ok("棋盘视图已创建", main.view != null)
	ok("按钮已创建", main.btn_end != null and main.btn_draw != null)
	if main.game == null:
		_finish()
		return

	# —— 排版：区块不许互相压 ——
	# 起因：验收截图时放了一段 5 行的长提示，直接盖到下面的【持续效果】上。
	#
	# 【为什么比「框」就够】Label 的最小高度 = 它文字需要的高度，Godot 会把
	# Control.size 撑到不小于最小尺寸 —— 所以 size **如实反映内容**。
	# 反过来说：文字永远不会「溢出自己的框」，它只会把框撑大去压别人。
	# 所以能抓到这个 bug 的只有「a 的下边缘 vs b 的上边缘」，不是行数。
	#
	# （我先后写错过两版：① 用 get_visible_line_count() —— 实测它永远等于
	#   get_line_count()，等于没测；② 自己按行数×行高算 —— 因为上面那条
	#   撑大机制，永远算得过。两版都"通过"了，但都没用。是拿掉封顶跑一遍
	#   才发现断言根本不响。）
	await process_frame
	ok("提示区不压到持续效果区", _no_overlap(main.hint, main.effects_label),
		_gap_info(main.hint, main.effects_label))
	ok("持续效果区不压到按钮行", _no_overlap(main.effects_label, main.btn_end),
		_gap_info(main.effects_label, main.btn_end))
	ok("按钮行不压到战报区", _no_overlap(main.btn_end, main.log_label),
		_gap_info(main.btn_end, main.log_label))

	# 放一段 4 行长提示：hint 的 88px 高度就是为它留的
	main.hint_text = "状态验收\n选中=花青粗环+四角括号 ｜ 可走=焦墨点 ｜ 可吃=朱砂齿圈 ｜ 可部署=花青虚线\n死路=灰叉 ｜ 最近一步=淡墨方框 ｜ 断桥=朱砂叉 ｜ 浮桥=花青桥\n已装备=方印（写装备后的兵种）｜ 被绊=缚 ｜ 空城计=花青环"
	main._refresh()
	await process_frame
	ok("4 行长提示之后提示区仍不压到持续效果区", _no_overlap(main.hint, main.effects_label),
		_gap_info(main.hint, main.effects_label))

	# 效果挂满 —— 这就是 MAX_EFFECT_LINES 封顶存在的理由
	for i in 8:
		main.game.add_effect("bridge_broken", 3, "r", {"col": 3})
	main._refresh()
	await process_frame
	ok("效果挂满 8 条后效果区仍不压到按钮行", _no_overlap(main.effects_label, main.btn_end),
		_gap_info(main.effects_label, main.btn_end))
	main.game.effects.clear()

	# 棋盘与面板 / 手牌的相对位置
	ok("棋盘右边缘不压到面板",
		main.view.position.x + main.view.board_rect().size.x <= main.PANEL_X,
		[main.view.position.x + main.view.board_rect().size.x, main.PANEL_X])
	ok("棋盘下边缘不压到手牌区",
		main.view.position.y + main.view.board_rect().size.y <= main.HAND_Y,
		[main.view.position.y + main.view.board_rect().size.y, main.HAND_Y])
	ok("战报区不超出窗口底部",
		main.log_label.position.y + main.log_label.size.y <= 660.0,
		main.log_label.position.y + main.log_label.size.y)

	# —— 布阵 ——
	ok("开局是布阵阶段", main.game.phase == "deploy")
	main.click_cell(1, 5)
	main.click_cell(2, 5)
	main.click_cell(3, 5)
	ok("红方放下 3 个", main.game.deploy_left.r == 0)
	main.click_cell(1, 6)
	main.click_cell(2, 6)
	main.click_cell(3, 6)
	ok("布阵完成，进入对局", main.game.phase == "play")
	ok("轮到红方", main.game.turn == "r")
	ok("手牌按钮数与手牌一致", main.hand_root.get_child_count() == main.game.hands.r.size(),
		[main.hand_root.get_child_count(), main.game.hands.r.size()])

	# —— 选子与移动 ——
	# 挑一个「真的走得动」的红兵：列 1/2 的兵卡在河边过不去，是合法局面
	var cand = null
	for p in main.game.pieces:
		if p.owner == "r" and p.kind == "pawn" and main.game.legal_moves(p).size() > 0:
			cand = p
			break
	ok("找得到一个能走的红兵", cand != null)
	if cand == null:
		_finish()
		return
	main.click_cell(cand.c, cand.r)
	ok("点自己的子会选中它", main.selected_id == cand.id)
	ok("并且高亮了走法", main.sel_moves.size() > 0, main.sel_moves.size())

	if main.sel_moves.size() > 0:
		var m: Dictionary = main.sel_moves[0]
		main.click_cell(m.c, m.r)
		ok("点目标格真的移动了", cand.c == m.c and cand.r == m.r)
		ok("移动名额已用掉", main.game.move_used)
		ok("选中状态已清空", main.selected_id == "")

	# —— 点手牌部署 ——
	var before: int = main.game.pieces.size()
	main.game.turn = "r"
	main.game.ap = 2
	main.game.move_used = false
	main.game.hands.r = [{"kind": "pawn"}]
	main._rebuild_hand()
	main.click_card(0)
	ok("点兵牌进入部署模式", main.mode == "deploy_card")
	var cells: Array = main.view.targets
	ok("高亮了部署区", cells.size() > 0, cells.size())

	# —— 死路预警：兵落在非桥列，就永远过不了河（规则书 §2.2）——
	ok("兵牌进入部署模式时会标出死路格", main.trap_cells.size() > 0, main.trap_cells.size())
	ok("死路格不在桥列上",
		not main.trap_cells.any(func(v): return Rules.is_bridge_col(v.x)))
	ok("死路格都是合法部署点",
		main.trap_cells.all(func(v): return cells.has(v)))
	ok("棋盘视图收到了死路格", main.view.trap_cells.size() == main.trap_cells.size())

	# 象不该被标成死路（象不过河，堵桥才是它的用法）
	main.game.hands.r = [{"kind": "elephant"}]
	main._rebuild_hand()
	main.click_card(0)
	ok("象牌不标死路格", main.trap_cells.is_empty(), main.trap_cells.size())
	main._clear_pending()

	# 换回兵牌，继续走原来的部署流程
	main.game.hands.r = [{"kind": "pawn"}]
	main._rebuild_hand()
	main.click_card(0)
	cells = main.view.targets

	if cells.size() > 0:
		main.click_cell(cells[0].x, cells[0].y)
		ok("点格子真的部署出来了", main.game.pieces.size() == before + 1)
		ok("部署后回到空闲模式", main.mode == "")

	# —— 断桥 ——
	main.game.hands.r = [{"kind": "spell", "spell": "断桥"}]
	main.game.ap = 2
	main._rebuild_hand()
	main.click_card(0)
	ok("点断桥进入选列模式", main.mode == "spell_column")
	main.click_cell(3, 6)
	ok("列 3 被断", not main.game.bridge_open(3))
	ok("结算后回到空闲模式", main.mode == "")

	# —— 结束回合 ——
	var prev: String = main.game.turn
	main.press_end_turn()
	ok("回合交给了对手", main.game.turn != prev, main.game.turn)

	# —— 超额手牌必须先弃 ——
	main.game.turn = "r"
	var six: Array = []
	for i in 6:
		six.append({"kind": "pawn"})
	main.game.hands.r = six
	main.press_end_turn()
	ok("超额时进入弃牌模式，回合没交出去",
		main.discard_mode and main.game.turn == "r")
	main.click_card(0)
	ok("弃够之后自动退出弃牌模式", not main.discard_mode)

	# —— 重开 ——
	main.press_restart()
	ok("重开后回到布阵阶段", main.game.phase == "deploy")
	ok("重开后效果清空", main.game.effects.is_empty())

	# —— 走到分出胜负：UI 必须报出赢家，并且拒绝再操作 ——
	# 前面测的都是「点击有没有接到引擎上」，这一段测的是终局有没有真的关掉交互。
	main.game.phase = "play"
	main.game.turn = "r"
	main.game.ap = 2
	main.game.move_used = false
	var ek = main.game.king_of("b")
	ok("黑方主将在自己的九宫里", ek != null and Rules.in_palace("b", ek.c, ek.r))
	if ek == null:
		_finish()
		return
	var rook = main.game._spawn("r", "chariot", ek.c, ek.r - 1)
	main._refresh()
	ok("摆好一台能吃到主将的战车", main.game.legal_moves(rook).size() > 0)

	# 从 UI 走，不直接调 do_move
	main.click_cell(rook.c, rook.r)
	ok("战车被选中", main.selected_id == rook.id)
	main.click_cell(ek.c, ek.r)
	ok("从 UI 吃掉主将 → 引擎判红方胜", main.game.winner == "r", main.game.winner)
	ok("状态栏报出赢家", main.status.text.contains("获胜"), main.status.text)
	ok("提示栏报出赢家", main.hint_text.contains("获胜"), main.hint_text)
	ok("结束回合按钮已禁用", main.btn_end.disabled)
	ok("摸牌按钮已禁用", main.btn_draw.disabled)
	ok("终局后选中状态已清空", main.selected_id == "")

	# 终局后所有入口都得装死（UI 挡一层，引擎自己再挡一层）
	var n_before: int = main.game.pieces.size()
	var ap_before: int = main.game.ap
	main.click_cell(5, 5)
	main.press_end_turn()
	main.press_draw()
	main.click_card(0)
	ok("终局后点棋盘 / 结束回合 / 摸牌 / 出牌都不改变局面",
		main.game.pieces.size() == n_before
		and main.game.ap == ap_before
		and main.game.winner == "r")

	# 只有「重开一局」能救回来
	main.press_restart()
	ok("重开后赢家被清掉", main.game.winner == "")
	ok("重开后又能点棋盘了", main.game.phase == "deploy")

	_finish()


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


## a 的下边缘有没有越过 b 的上边缘。
## 这是唯一能抓到「区块互相压」的判据 —— 因为 Label 的 size 会被内容撑大，
## 所以 size 反映的是真实占位，而文字不会溢出自己的框。
func _no_overlap(a: Control, b: Control) -> bool:
	return a.position.y + a.size.y <= b.position.y


func _gap_info(a: Control, b: Control) -> String:
	return "「%s」下边缘 %.0f 越过「%s」上边缘 %.0f（超出 %.0f）" % [
		a.name, a.position.y + a.size.y, b.name, b.position.y,
		a.position.y + a.size.y - b.position.y]


func _finish() -> void:
	print("========================================")
	print("%d passed, %d failed" % [_pass, _fail])
	print("")
	quit(1 if _fail > 0 else 0)
