extends Control
## 主界面：把引擎状态画出来，并把点击翻译成 engine 的 do_* 调用。
##
## 【架构约定】这一层是唯一允许碰 Node 的地方。
## 规则判断一行都不许写在这里 —— 要什么信息就问 game。
##
## 交互逻辑全部放在普通方法里（click_cell / click_card / press_end_turn），
## 不依赖事件对象，所以可以在无头模式下直接调用来做冒烟测试。

const Game := preload("res://engine/Game.gd")
const Rules := preload("res://engine/Rules.gd")
const Palette := preload("res://scenes/Palette.gd")
const BoardViewScript := preload("res://scenes/BoardView.gd")

const HAND_Y := 556
const PANEL_X := 470

var game = null
var view: Node2D = null
var status: Label = null
var hint: Label = null
var effects_label: Label = null
var log_label: Label = null
var hand_root: Control = null
var btn_draw: Button = null
var btn_end: Button = null
var btn_restart: Button = null

var font: Font = null           ## 面板小字：黑体（12px 楷体在屏幕上会糊）
var brush: Font = null          ## 标题与棋子：楷体（有笔意）
var hint_text := ""
var selected_id := ""
var sel_moves: Array = []
var pending_hand := -1          ## 正在等目标的那张手牌
var mode := ""                  ## "" / deploy_card / equip / spell_cell / spell_column
var discard_mode := false
var trap_cells: Array = []      ## 兵落上去就永远过不了河的格子，交给 BoardView 打叉
var _booted := false


func _ready() -> void:
	setup()


## 幂等：编辑器里由 _ready 触发；无头测试里显式调用
func setup() -> void:
	if _booted:
		return
	_booted = true
	# 两副字：楷体给标题与棋子，黑体给面板小字
	brush = Palette.brush_font()
	font = Palette.text_font()
	# 窗口底色也归调色板管 —— 否则棋盘再好看也像贴在一块默认灰板上
	RenderingServer.set_default_clear_color(Palette.MOUNT)
	game = Game.new()
	game.new_game(20260101)
	_build_ui()
	hint_text = "布阵：红方在自己的半场点 3 个空格放小兵。优先放列 3/5/7 —— 其他列的小兵过不了河。"
	_refresh()


# ---------------------------------------------------------------- 建界面

func _build_ui() -> void:
	view = BoardViewScript.new()
	view.position = Vector2(16, 46)
	view.font = brush
	add_child(view)

	# 裱边：几道发丝线代替方框。水墨讲留白，不画卡片框。
	_mk_rule(Vector2(16, 40), Vector2(1000, 1), Palette.INK_PALE)
	_mk_rule(Vector2(PANEL_X - 12, 46), Vector2(1, 476), Palette.MOUNT_DIM)
	_mk_rule(Vector2(16, HAND_Y - 10), Vector2(436, 1), Palette.INK_PALE)

	# 面板各段的高度必须够长提示语折行用 —— 原来 hint 只有 64px（约 3 行），
	# 一段 5 行的提示会直接盖到下面的【持续效果】上。
	# 这几段的 y 边界由 UiSmoke 的「不重叠」断言盯着。
	status = _mk_label(Vector2(16, 10), Vector2(1000, 30), 16, Palette.INK_BURNT, true)
	hint = _mk_label(Vector2(PANEL_X, 46), Vector2(548, 88), 13, Palette.INK_HEAVY)
	effects_label = _mk_label(Vector2(PANEL_X, 142), Vector2(548, 130), 13, Palette.INK_MID)
	log_label = _mk_label(Vector2(PANEL_X, 360), Vector2(548, 175), 12, Palette.INK_MID)
	# 起个可读名字：排版断言失败时会打印节点名，默认的 @Label@8 看不出是哪个区
	status.name = "状态栏"
	hint.name = "提示区"
	effects_label.name = "效果区"
	log_label.name = "战报区"

	hand_root = Control.new()
	hand_root.position = Vector2(16, HAND_Y)
	hand_root.size = Vector2(1000, 80)
	add_child(hand_root)

	btn_draw = _mk_button(Vector2(PANEL_X, 280), Vector2(170, 34), "额外摸牌（1 AP）")
	btn_draw.name = "摸牌按钮"
	btn_draw.pressed.connect(press_draw)
	btn_end = _mk_button(Vector2(PANEL_X + 180, 280), Vector2(170, 34), "结束回合")
	btn_end.name = "结束回合按钮"
	btn_end.pressed.connect(press_end_turn)
	btn_restart = _mk_button(Vector2(PANEL_X + 360, 280), Vector2(120, 34), "重开一局")
	btn_restart.pressed.connect(press_restart)


## 一道发丝线。注意 Control 默认会吃掉鼠标事件 —— 不设 IGNORE 的话，
## 它覆盖的区域会让 _unhandled_input 收不到点击，棋盘就点不动了。
func _mk_rule(pos: Vector2, size: Vector2, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _mk_label(pos: Vector2, size: Vector2, fsize: int, col: Color, use_brush := false) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = size
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", brush if use_brush else font)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	add_child(l)
	return l


func _mk_button(pos: Vector2, size: Vector2, text: String) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = size
	b.text = text
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 13)
	_apply_ink_style(b)
	add_child(b)
	return b


## 水墨按钮：一张纸盖一道墨框。不用引擎默认的凸起按钮。
## 覆盖 normal / hover / pressed / disabled / focus 五态 ——
## 这几个按钮没有 loading / error / success 态，就不假装有。
func _apply_ink_style(b: Button, card := false, urgent := false) -> void:
	var pad: int = 5 if card else 10
	var edge: Color = Palette.CINNABAR if urgent else Palette.INK_LIGHT
	b.add_theme_stylebox_override("normal", _sb(Palette.PAPER, edge, 1, 2, pad))
	b.add_theme_stylebox_override("hover", _sb(Palette.PAPER_HI, Palette.INDIGO, 1, 2, pad))
	b.add_theme_stylebox_override("pressed", _sb(Palette.PAPER_DIM, Palette.INDIGO, 2, 2, pad))
	b.add_theme_stylebox_override("disabled", _sb(Palette.MOUNT, Palette.MOUNT_DIM, 1, 2, pad))
	b.add_theme_stylebox_override("focus", _sb(Color(0, 0, 0, 0), Palette.INDIGO, 2, 2, pad))
	b.add_theme_color_override("font_color", Palette.CINNABAR if urgent else Palette.INK_HEAVY)
	b.add_theme_color_override("font_hover_color", Palette.INDIGO)
	b.add_theme_color_override("font_pressed_color", Palette.INDIGO)
	b.add_theme_color_override("font_focus_color", Palette.INK_HEAVY)
	b.add_theme_color_override("font_disabled_color", Palette.INK_LIGHT)


func _sb(fill: Color, border: Color, bw: int, radius: int, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


# ---------------------------------------------------------------- 输入入口

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = view.to_local(event.position)
		var cell: Vector2i = view.local_to_cell(local)
		if cell.x > 0:
			click_cell(cell.x, cell.y)


## 点棋盘上的某一格
func click_cell(c: int, r: int) -> void:
	if game == null or game.winner != "":
		return

	# ① 布阵阶段
	if game.phase == "deploy":
		if game.setup_deploy(game.deploy_turn, c, r):
			if game.phase == "play":
				hint_text = "布阵完毕。轮到红方：免费摸 1 张，然后花 2 点 AP。"
			else:
				hint_text = "黑方布阵：还需放 %d 个。" % game.deploy_left[game.deploy_turn]
		else:
			hint_text = "只能放在自己半场的空格上。"
		_refresh()
		return

	# ② 有一张牌在等目标
	if mode != "":
		_resolve_pending(c, r)
		_refresh()
		return

	# ③ 选子 / 移动
	var p = game.piece_at(c, r)
	if p != null and p.owner == game.turn:
		selected_id = p.id
		sel_moves = game.legal_moves(p)
		if sel_moves.is_empty():
			hint_text = "%s 这回合动不了（每回合全盘只能移动一次，或已被封住）。" % p._label()
		else:
			hint_text = "选中 %s（%s）：绿点可走，红圈可吃。" % [p._label(), _unit_name(p.kind_now())]
		_refresh()
		return
	if selected_id != "":
		for m in sel_moves:
			if m.c == c and m.r == r:
				_do_move(selected_id, m)
				return
		_clear_selection()
		hint_text = "已取消选择。"
	_refresh()


## 点手牌
func click_card(index: int) -> void:
	if game == null or game.phase != "play" or game.winner != "":
		return
	var hand: Array = game.hands[game.turn]
	if index < 0 or index >= hand.size():
		return

	# 超额弃牌模式
	if discard_mode:
		game.do_discard(game.turn, index)
		if game.must_discard(game.turn) == 0:
			discard_mode = false
			hint_text = "弃牌完毕，可以结束回合了。"
		_refresh()
		return

	var card: Dictionary = hand[index]
	match card.get("kind", ""):
		"pawn", "elephant":
			pending_hand = index
			mode = "deploy_card"
			if card.kind == "pawn":
				hint_text = "点蓝圈部署小兵。灰叉格是死路：兵过河前不能横走，落在非桥列就永远过不了河（只走列 3/5/7）。"
			else:
				hint_text = "点击蓝圈部署%s。" % _unit_name(card.kind)
		"gear":
			var pawns: Array = []
			var locked: int = 0
			for p in game.pieces:
				if p.owner == game.turn and p.kind == "pawn" and p.gear == "":
					if game.in_command_range(game.turn, p.c, p.r):
						pawns.append(Vector2i(p.c, p.r))
					else:
						locked += 1
			if pawns.is_empty():
				if locked > 0:
					hint_text = "没有可装备的小兵：场上有 %d 个未装备的小兵，但都在主将两格之外。" % locked
				else:
					hint_text = "场上没有可装备的小兵。"
				_clear_pending()
			else:
				pending_hand = index
				mode = "equip"
				if locked > 0:
					hint_text = "点击要装备的小兵（蓝圈内）。另有 %d 个在指挥范围外，装不了。" % locked
				else:
					hint_text = "点击要装备的小兵。"
		"spell":
			var info: Dictionary = game.spell_targets(game.turn, index)
			if not info.ok:
				hint_text = info.reason
				_clear_pending()
			else:
				pending_hand = index
				match info.kind:
					"cell":
						mode = "spell_cell"
						hint_text = "点击蓝圈选择目标。"
					"column":
						mode = "spell_column"
						hint_text = "点击要断的那座桥。"
					_:
						mode = ""
						game.do_play_spell(game.turn, index, {})
						hint_text = "锦囊已结算。"
	_refresh()


func press_draw() -> void:
	if game == null:
		return
	if game.do_draw(game.turn):
		hint_text = "额外摸了 1 张，剩余 %d AP。" % game.ap
	_refresh()


func press_end_turn() -> void:
	if game == null or game.phase != "play" or game.winner != "":
		return
	_clear_pending()
	_clear_selection()
	if game.must_discard(game.turn) > 0:
		discard_mode = true
		hint_text = "手牌超过上限，点击手牌弃掉 %d 张才能结束回合。" % game.must_discard(game.turn)
		_refresh()
		return
	if game.end_turn():
		hint_text = "轮到%s。" % Rules.side_name(game.turn)
	_refresh()


func press_restart() -> void:
	game.new_game(20260101)
	_clear_pending()
	_clear_selection()
	discard_mode = false
	hint_text = "布阵：红方在自己的半场点 3 个空格放小兵。优先放列 3/5/7 —— 其他列的小兵过不了河。"
	_refresh()


# ---------------------------------------------------------------- 内部

func _do_move(pid: String, m: Dictionary) -> void:
	game.do_move(pid, m.c, m.r)
	view.last_move = [Vector2i(m.c, m.r)]
	_clear_selection()
	if game.winner != "":
		hint_text = "★ %s获胜！" % Rules.side_name(game.winner)
	else:
		hint_text = "移动完成，剩余 %d AP。" % game.ap
	_refresh()


func _resolve_pending(c: int, r: int) -> void:
	var me: String = game.turn
	match mode:
		"deploy_card":
			if game.do_deploy(me, pending_hand, c, r):
				_clear_pending()
		"equip":
			var p = game.piece_at(c, r)
			if p != null and game.do_equip(me, pending_hand, p.id):
				_clear_pending()
		"spell_cell":
			if game.do_play_spell(me, pending_hand, {"c": c, "r": r}):
				_clear_pending()
		"spell_column":
			if game.do_play_spell(me, pending_hand, {"col": c}):
				_clear_pending()
	if mode != "":
		hint_text = "这个目标不合法。"


func _clear_selection() -> void:
	selected_id = ""
	sel_moves = []


func _clear_pending() -> void:
	pending_hand = -1
	mode = ""


## 当前该高亮哪些格。顺带算出「死路」格给棋盘打叉。
func _current_targets() -> Array:
	trap_cells = []
	var out: Array = []
	match mode:
		"deploy_card":
			out = game.deploy_cells(game.turn)
			# 小兵过河前不能横走，落在非桥列就永久卡死在河边（还占人口）。
			# 这是个踩了才知道的坑，不如提前画个叉。规则书 §2.2 有写。
			if _pending_card().get("kind", "") == "pawn":
				for v in out:
					if not Rules.is_bridge_col(v.x):
						trap_cells.append(v)
		"equip":
			# 只有在主将指挥范围内（曼哈顿 ≤ 2）的未装备小兵才能装。
			# 【注意】这里**不能**用 deploy_cells() 来判：那个函数返回的是空点，
			# 而装备目标是站在格子上的兵，永远查不到。
			for p in game.pieces:
				if p.owner == game.turn and p.kind == "pawn" and p.gear == "" \
						and game.in_command_range(game.turn, p.c, p.r):
					out.append(Vector2i(p.c, p.r))
		"spell_cell", "spell_column":
			if pending_hand >= 0 and pending_hand < game.hands[game.turn].size():
				var info: Dictionary = game.spell_targets(game.turn, pending_hand)
				out = info.cells
				for col in info.columns:
					out.append(Vector2i(col, 5))
					out.append(Vector2i(col, 6))
	return out


## 正在等目标的那张手牌（没有就返回空字典）
func _pending_card() -> Dictionary:
	var hand: Array = game.hands[game.turn]
	if pending_hand < 0 or pending_hand >= hand.size():
		return {}
	return hand[pending_hand]


func _refresh() -> void:
	if game == null or view == null:
		return
	view.game = game
	view.selected_id = selected_id
	view.moves = sel_moves
	view.targets = _current_targets()
	view.trap_cells = trap_cells
	view.font = brush
	view.queue_redraw()

	status.text = _status_text()
	hint.text = hint_text
	effects_label.text = _effects_text()
	log_label.text = _log_text()
	_rebuild_hand()

	btn_end.disabled = game.phase != "play" or game.winner != ""
	btn_draw.disabled = game.phase != "play" or game.ap < 1 or game.winner != ""


func _status_text() -> String:
	if game.winner != "":
		return "★ %s获胜 ★    （点「重开一局」再来）" % Rules.side_name(game.winner)
	if game.phase == "deploy":
		return "布阵阶段 · 轮到%s" % Rules.side_name(game.deploy_turn)
	return "轮到 %s    AP %d    人口  红 %d/%d · 黑 %d/%d    牌库 %d · 弃牌 %d    第 %d 回合" % [
		Rules.side_name(game.turn), game.ap,
		game.pop_used("r"), Game.POP_CAP, game.pop_used("b"), Game.POP_CAP,
		game.deck.size(), game.discard.size(), game.turn_no,
	]


## 效果区最多列几条。不封顶的话，以后锦囊补到 14 种、场上挂满效果时，
## 文字会默默溢出 Label 的高度去压下面的按钮（Label 不会自己裁剪）。
const MAX_EFFECT_LINES := 3


func _effects_text() -> String:
	var lines: Array = ["【持续效果】"]
	if game.effects.is_empty():
		lines.append("（无）")
	var shown := 0
	for e in game.effects:
		if shown >= MAX_EFFECT_LINES:
			break
		lines.append("· %s —— 剩 %d 回合（%s）"
			% [game.effect_text(e), e.left, Rules.side_name(e.by)])
		shown += 1
	if game.effects.size() > MAX_EFFECT_LINES:
		lines.append("· …另有 %d 条" % (game.effects.size() - MAX_EFFECT_LINES))
	lines.append("【桥】" + _bridge_text())
	return "\n".join(lines)


func _bridge_text() -> String:
	var parts: Array = []
	for col in Rules.BRIDGE_COLS:
		var s := "通"
		if game.bridge_temp(col):
			s = "浮桥"
		elif not game.bridge_open(col):
			s = "断"
		parts.append("列%d %s" % [col, s])
	return " ｜ ".join(parts)


func _log_text() -> String:
	var tail: Array = game.log_lines.slice(maxi(0, game.log_lines.size() - 8))
	return "【战报】\n" + "\n".join(tail)


func _rebuild_hand() -> void:
	for ch in hand_root.get_children():
		hand_root.remove_child(ch)     # 立刻脱离父节点，queue_free 是延迟的
		ch.queue_free()
	var hand: Array = game.hands[game.turn]
	var x := 0.0
	for i in hand.size():
		var card: Dictionary = hand[i]
		var b := Button.new()
		b.position = Vector2(x, 0)
		b.size = Vector2(72, 72)
		b.text = _card_text(card)
		b.add_theme_font_override("font", brush)
		b.add_theme_font_size_override("font_size", 14)
		# 弃牌模式下把牌框改成朱砂，提示「现在点牌是弃牌，不是出牌」
		_apply_ink_style(b, true, discard_mode)
		var idx := i
		b.pressed.connect(func(): click_card(idx))
		hand_root.add_child(b)
		x += 78.0


func _card_text(card: Dictionary) -> String:
	match card.get("kind", ""):
		"pawn": return "小兵"
		"elephant": return "象"
		"gear": return _unit_name(card.gear)
		"spell": return "%s\n%dAP" % [card.spell, Game.SPELL_COST.get(card.spell, 1)]
	return "?"


func _unit_name(kind: String) -> String:
	match kind:
		"pawn": return "小兵"
		"horse": return "骑兵"
		"chariot": return "战车"
		"cannon": return "炮兵"
		"advisor": return "士"
		"elephant": return "象"
		"king": return "主将"
	return kind
