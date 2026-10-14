extends SceneTree
## 架构护栏：三条铁律不能只写在 README 里，得让测试真的盯着。
##
##   铁律一：engine/ 必须是纯逻辑 —— 不 extends Node、不碰场景树、不依赖 res://scenes
##   铁律二：随机数必须可注入种子 —— 不许用全局 randi/randf/randomize
##   铁律三：改状态只能走 do_* 方法 —— 从反射里核对接口是否齐全
##
## 用正则扫描 + Godot 反射。粗糙，但足够在有人手滑时当场报警。

var passed: int = 0
var failed: int = 0

const Palette := preload("res://scenes/Palette.gd")


func ok(cond: bool, what: String, extra = "") -> void:
	if cond:
		passed += 1
		print("  PASS  ", what)
	else:
		failed += 1
		print("  FAIL  ", what, ("  → " + str(extra)) if str(extra) != "" else "")


## 正则命中返回 true。用 lookbehind 区分「全局随机」和「rng.xxx」
func _hits(text: String, pattern: String) -> bool:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return false
	return re.search(text) != null


func _initialize() -> void:
	print("")
	print("兵符 · 架构护栏")
	print("========================================")

	var dir: DirAccess = DirAccess.open("res://engine")
	ok(dir != null, "engine/ 目录存在")
	if dir == null:
		_finish()
		return

	var files: Array = []
	dir.list_dir_begin()
	var fn: String = dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".gd"):
			files.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	files.sort()

	ok(files.size() >= 4, "engine/ 下至少 4 个 .gd（实际 %d）" % files.size(), files)

	# ---- 铁律一：引擎不许变成 Node、不许碰场景树 ----
	# 注意 ^\s*extends 不匹配注释行（注释以 # 开头）
	var banned: Array = [
		["(?m)^\\s*extends\\s+Node\\b", "继承 Node"],
		["\\bget_node\\s*\\(", "访问场景树"],
		["\\badd_child\\s*\\(", "挂子节点"],
		["\\bsignal\\s+\\w+\\s*\\(", "声明信号"],
		["res://scenes", "依赖场景层"],
		["(?<![\\w.])load\\s*\\(", "运行时 load（preload 可以）"],
	]
	# 这几个文件本来就用 preload 互相引用，属于编译期依赖，合法
	for f in files:
		var text: String = _strip_comments(_read("res://engine/" + f))
		ok(text.strip_edges() != "", "能读到 engine/" + f)
		if text.strip_edges() == "":
			continue
		for pair in banned:
			ok(not _hits(text, pair[0]),
				"engine/%s 不%s" % [f, pair[1]],
				"命中 `%s`" % pair[0])

	# ---- 铁律二：随机数必须可注入种子 ----
	var rng_banned: Array = [
		["(?<![\\w.])randi\\s*\\(", "randi()"],
		["(?<![\\w.])randf\\s*\\(", "randf()"],
		["(?<![\\w.])randi_range\\s*\\(", "randi_range()"],
		["(?<![\\w.])randf_range\\s*\\(", "randf_range()"],
		["\\brandomize\\s*\\(", "randomize()"],
	]
	for f in files:
		var text: String = _strip_comments(_read("res://engine/" + f))
		if text.strip_edges() == "":
			continue
		var bad: String = ""
		for pair in rng_banned:
			if _hits(text, pair[0]):
				bad = pair[1]
				break
		ok(bad == "", "engine/%s 不用全局随机" % f, "用了 %s，请改用 RandomNumberGenerator" % bad)

	# ---- 引擎文件能独立 load，关键常量没被改跑偏 ----
	var rules_scr = load("res://engine/Rules.gd")
	ok(rules_scr != null, "Rules.gd 可独立 load")
	if rules_scr != null:
		var c: Dictionary = rules_scr.get_script_constant_map()
		ok(c.get("COLS", 0) == 9, "Rules.COLS == 9", c.get("COLS", null))
		ok(c.get("ROWS", 0) == 10, "Rules.ROWS == 10", c.get("ROWS", null))
		ok(c.get("BRIDGE_COLS", []) == [3, 5, 7], "桥只有列 3/5/7", c.get("BRIDGE_COLS", null))
		ok(c.get("ELEPHANT_CAP", 0) == 2, "象上限 2", c.get("ELEPHANT_CAP", null))

	var game_scr = load("res://engine/Game.gd")
	ok(game_scr != null, "Game.gd 可独立 load")
	if game_scr != null:
		var gc: Dictionary = game_scr.get_script_constant_map()
		ok(gc.get("POP_CAP", 0) == 8, "人口上限 8", gc.get("POP_CAP", null))
		ok(gc.get("HAND_LIMIT", 0) == 5, "手牌上限 5", gc.get("HAND_LIMIT", null))
		ok(gc.get("AP_PER_TURN", 0) == 2, "每回合 2 行动点", gc.get("AP_PER_TURN", null))

		# ---- 铁律三：do_* 接口齐全（反射核对，不靠字符串猜） ----
		var names: Array = []
		for m in game_scr.get_script_method_list():
			names.append(m.get("name", ""))
		for need in ["do_move", "do_deploy", "do_equip", "do_disband",
				"do_draw", "do_discard", "do_play_spell", "end_turn", "start_turn"]:
			ok(names.has(need), "Game.gd 定义了 %s()" % need)

		# 动作日志是撤销/回放/AI 的地基，别被人删了
		ok(names.has("_log"), "Game.gd 保留了动作日志 _log()")

	# MoveGen 必须提供唯一的合法走法来源
	var mg_scr = load("res://engine/MoveGen.gd")
	ok(mg_scr != null, "MoveGen.gd 可独立 load")
	if mg_scr != null:
		var mn: Array = []
		for m in mg_scr.get_script_method_list():
			mn.append(m.get("name", ""))
		ok(mn.has("legal_moves"), "MoveGen.gd 提供 legal_moves()")

	# ---- 场景层不许重复实现规则 ----
	var board: String = _read("res://scenes/BoardView.gd")
	ok(not board.contains("func legal_moves"), "BoardView 不重复实现合法走法")

	# ---- 视图几何自洽：棋子必须放得进底板 ----
	# 这条是从一张截图里抓出来的 bug：底板宽高少算了两侧各 MG 的留白，
	# 结果行 1 / 行 10 的棋子被木板边缘切掉一半，而当时所有断言都是绿的。
	# 关键是要断言「真正拿去 draw 的那个矩形」（board_rect），不是 board_size ——
	# 当初出 bug 的时候 board_size 和 pt 都是对的，断言它们等于什么都没测。
	var bv_scr = load("res://scenes/BoardView.gd")
	ok(bv_scr != null, "BoardView.gd 可独立 load")
	if bv_scr != null:
		var bv = bv_scr.new()
		var br: Rect2 = bv.board_rect()
		# 读 BoardView 真正用的那个半径，不要在这里写死一个数字 ——
		# 写死的话哪天半径调大了，断言就悄悄失效了。
		var rad: float = bv.PIECE_R
		var inner: Rect2 = br.grow(-rad)
		var corners: Array = [Vector2i(1, 1), Vector2i(9, 1), Vector2i(1, 10), Vector2i(9, 10)]
		for cell in corners:
			ok(inner.has_point(bv.pt(cell.x, cell.y)),
				"四角 %s 的棋子放得进纸面（半径 %.0f）" % [str(cell), rad])
		# 两条边线之间必须是「网格跨度」，也就是纸面扣掉两侧留白
		ok(is_equal_approx(bv.pt(9, 1).x - bv.pt(1, 1).x, br.size.x - 2.0 * bv.MG),
			"横向：网格跨度 = 纸面宽 - 两侧留白")
		# 注意行号是反的：行 1 画在最下面，所以纵向取绝对值
		ok(is_equal_approx(absf(bv.pt(1, 10).y - bv.pt(1, 1).y), br.size.y - 2.0 * bv.MG),
			"纵向：网格跨度 = 纸面高 - 两侧留白")

		# ---- 河带与桥面必须画在网格线之下 ----
		# 这两条是从同一类 bug 里抓出来的：「用不透明的填充矩形去盖一块区域」
		# 时，如果它画在网格线之后，就会把网格线吃掉。
		#   ① 河带（范围 x∈[列1,列9], y∈[行6,行5]）→ 吃掉了行 5 的河岸横线
		#   ② 桥面（范围 x∈[桥心±9], y∈[行6,行5]）→ 只吃掉行 5、不吃行 6，
		#      于是「上沿的河岸线横穿桥面、下沿的在桥面处断开」，两头样式不一致
		# 注意 draw_rect 覆盖的是「像素中心落在矩形内」的行，所以同一个矩形
		# 会对上下两条边界线产生**不同**的效果 —— 这就是症状为什么是「只坏一头」。
		var order_src: String = _strip_comments(_read("res://scenes/BoardView.gd"))
		var i_grid: int = order_src.find("_draw_grid()")
		ok(i_grid >= 0, "BoardView 有 _draw_grid()")
		for pair in [["_draw_river_band()", "河带底色"], ["_draw_bridge_decks()", "桥面底色"]]:
			var i_call: int = order_src.find(pair[0])
			ok(i_call >= 0, "BoardView 有 %s（%s）" % [pair[0], pair[1]])
			ok(i_call >= 0 and i_grid >= 0 and i_call < i_grid,
				"%s画在网格线之前（否则会盖掉行 5 的河岸横线）" % pair[1],
				"i_call=%d i_grid=%d" % [i_call, i_grid])

		# ---- 文字居中 ----
		# 这条也是从放大截图里抓出来的：棋子圆圈是空的，字全挤在圈的右边 ——
		# draw_string 传 alignment=CENTER + width 时会从 pos.x + width/2 起头。
		var raw: String = _strip_comments(_read("res://scenes/BoardView.gd"))
		ok(not raw.contains("HORIZONTAL_ALIGNMENT_CENTER"),
			"棋盘文字不靠 draw_string 的 alignment 居中（实测会偏右半个宽度）",
			"请改用 _draw_centered / centered_text_pos")
		bv.font = Palette.brush_font()
		for probe in ["将", "帅", "士", "兵", "楚 河"]:
			var at := Vector2(200.0, 100.0)
			var tw: float = bv.font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
			var pos: Vector2 = bv.centered_text_pos(probe, at, 21)
			ok(is_equal_approx(pos.x + tw * 0.5, at.x),
				"「%s」水平居中于 %.0f（实宽 %.1f）" % [probe, at.x, tw])
			ok(is_equal_approx(pos.y, at.y), "「%s」基线不被改动" % probe)
		bv.free()

	_finish()


## 去掉 GDScript 的行注释再扫。
## 否则「注释里提到某个坏模式」会被误判成真的用了它 ——
## 我写文档解释这个 draw_string 的坑时就把自己拦下来了。
## 局限：不处理字符串里的 `#`（本项目只在调色板里有 `Color("#rrggbb")`，
## 而那几个检查跟颜色无关，截断了也无所谓）。
func _strip_comments(src: String) -> String:
	var out: Array = []
	for line in src.split("\n"):
		var cut: int = line.find("#")
		out.append(line if cut < 0 else line.substr(0, cut))
	return "\n".join(out)


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s


func _finish() -> void:
	print("========================================")
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
