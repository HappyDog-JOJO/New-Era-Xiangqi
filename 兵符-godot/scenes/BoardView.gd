extends Node2D
## 棋盘视图：只负责「把状态画出来」和「把点击翻译成 (列,行)」。
## 【架构约定】这里不做任何规则判断 —— 规则全在 engine/ 里。
## 它只读 game 的状态，以及 Main 传进来的高亮信息。
##
## 【画法】水墨淡彩。纸用淡墨，但**棋子和交互状态用焦墨 / 朱砂 / 花青压住** ——
## 淡彩不等于低对比，靠的是墨色明度差，不是靠加颜色。
## 棋盘上的 7 种状态一律**形状 + 颜色双重编码**，色弱也能分清。

const Rules := preload("res://engine/Rules.gd")
const Palette := preload("res://scenes/Palette.gd")

const CELL := 46
const MG := 34
const PIECE_R := 18.0            ## 棋子半径。ArchGuard 直接读这个值来断言子放得进纸面。

var game = null
var font: Font = null            ## 棋子与河界用的笔意字体（楷体）

var selected_id: String = ""      ## 当前选中的棋子
var moves: Array = []             ## 要画成点/圈的走法
var targets: Array = []           ## 要画成虚线环的可选目标（部署区 / 锦囊目标）
var trap_cells: Array = []        ## 「死路」格：兵落这里就永远过不了河
var last_move: Array = []         ## 最近一步，淡墨光晕

var _grain: ImageTexture = null   ## 宣纸纹理（惰性生成，只做一次）


func board_size() -> Vector2:
	return Vector2(MG * 2 + (Rules.COLS - 1) * CELL, MG * 2 + (Rules.ROWS - 1) * CELL)


## 宣纸矩形。_draw_paper() 用它，ArchGuard 也用它来断言
## 「四个角的棋子放得进纸面」—— 提成函数是为了让这个几何关系可测。
func board_rect() -> Rect2:
	return Rect2(Vector2.ZERO, board_size())


func pt(c: int, r: int) -> Vector2:
	return Vector2(MG + (c - 1) * CELL, MG + (Rules.ROWS - r) * CELL)


## 本地坐标 → 棋盘格；不在交叉点附近返回 (-1,-1)
func local_to_cell(pos: Vector2) -> Vector2i:
	for c in range(1, Rules.COLS + 1):
		for r in range(1, Rules.ROWS + 1):
			if pos.distance_to(pt(c, r)) <= CELL * 0.5:
				return Vector2i(c, r)
	return Vector2i(-1, -1)


func has_target(c: int, r: int) -> bool:
	for v in targets:
		if v.x == c and v.y == r:
			return true
	return false


# ================================================================== 绘制入口

func _draw() -> void:
	if game == null:
		return
	_ensure_assets()
	_draw_paper()
	_draw_river_band()      # ← 必须在 _draw_grid() 之前，理由见「河界」那一段
	_draw_bridge_decks()    # ← 同上：桥面底色也会盖掉行 5 的河岸线
	_draw_frame()
	_draw_grid()
	_draw_river_text()
	_draw_bridge_rails()    # ← 桥栏与桥板要压在网格线之上
	_draw_marks()
	_draw_pieces()


func _ensure_assets() -> void:
	if font == null:
		font = Palette.brush_font()
	if _grain == null:
		_grain = _make_grain()


# ------------------------------------------------------------------ 文字居中

## 把一行字**以 at.x 为水平中心**画出来，at.y 是基线。
##
## 【踩过的坑】不要用 draw_string 自带的 alignment + width 来居中：
## 实测 `draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_CENTER, w, ...)` 会从
## `pos.x + w/2` 起头，也就是**整行偏右半个宽度**。棋子字曾因此全部跑到圆圈外面
## （圈是空的，字挤在圈的右边），而且缩放看截图时完全看不出来，放大才露出来。
func _draw_centered(text: String, at: Vector2, size: int, col: Color) -> void:
	if font == null:
		return
	draw_string(font, centered_text_pos(text, at, size), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## 纯计算版，方便 ArchGuard 直接断言「字到底居中没有」
func centered_text_pos(text: String, at: Vector2, size: int) -> Vector2:
	if font == null:
		return at
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return Vector2(at.x - w * 0.5, at.y)


# ------------------------------------------------------------------ 纸

func _draw_paper() -> void:
	var r: Rect2 = board_rect()
	draw_rect(r, Palette.PAPER, true)

	# 由上到下极淡的渐变：挂轴上面受光、下面略沉
	var bands := 26
	var bh: float = r.size.y / float(bands)
	for i in bands:
		var t: float = float(i) / float(bands - 1)
		var c := Palette.PAPER_DIM
		c.a = t * t * 0.16
		draw_rect(Rect2(r.position.x, r.position.y + i * bh, r.size.x, bh + 1.0), c, true)

	# 宣纸纤维
	if _grain != null:
		draw_texture_rect(_grain, r, true, Color(1, 1, 1, 0.6))


func _draw_frame() -> void:
	var r: Rect2 = board_rect()
	# 装裱边：一粗一细两道墨线。水墨讲留白，所以不画厚重的木框。
	draw_rect(r.grow(-4.0), Palette.INK_MID, false, 1.8)
	draw_rect(r.grow(-11.0), Palette.INK_LIGHT, false, 0.8)


# ------------------------------------------------------------------ 网格

func _draw_grid() -> void:
	# 九宫不加底纹。试过淡色矩形，但 draw_rect 没有柔边，怎么调都像盖了个灰方块；
	# 真象棋盘本来也只靠两条斜线标九宫，留白反而干净。
	var ink: Color = Palette.INK_MID
	# 横线 10 条，最外两条略重
	for r in range(1, Rules.ROWS + 1):
		var wide: bool = r == 1 or r == Rules.ROWS
		draw_line(pt(1, r), pt(Rules.COLS, r), ink, 1.5 if wide else 1.0)
	# 竖线：1 与 9 贯通，2–8 在河界断开
	for c in range(1, Rules.COLS + 1):
		var edge: bool = c == 1 or c == Rules.COLS
		var w: float = 1.5 if edge else 1.0
		if edge:
			draw_line(pt(c, 1), pt(c, Rules.ROWS), ink, w)
		else:
			draw_line(pt(c, 6), pt(c, Rules.ROWS), ink, w)
			draw_line(pt(c, 1), pt(c, 5), ink, w)
	# 九宫斜线
	draw_line(pt(4, 1), pt(6, 3), ink, 1.0)
	draw_line(pt(6, 1), pt(4, 3), ink, 1.0)
	draw_line(pt(4, 8), pt(6, 10), ink, 1.0)
	draw_line(pt(6, 8), pt(4, 10), ink, 1.0)


# ------------------------------------------------------------------ 河界
#
# 【为什么拆成两半】河带是一块**不透明的填充矩形**（PAPER_DIM = #ece7db），
# 范围正好是 `x ∈ [列1, 列9], y ∈ [行6, 行5]`。
# 它原来画在 _draw_grid() **之后**，于是把网格线压掉了：
#   · 行 5 的河岸横线几乎整条消失（被吃掉约 90%，肉眼就是「少了一条线」）
#   · 行 6 的河岸横线只被吃掉下沿一半，所以还看得见
#   · 列 1 / 列 9 的贯通竖线在河带内从 2px 缩成 1px
# 两沿被吃的比例不同，所以症状是「只少一条」而不是「少两条」。
# 【修法】底色与水纹画在网格**之前**，文字画在网格**之后**。
# 【不要改回去】ArchGuard 有一条规则盯着这个调用顺序。

func _draw_river_band() -> void:
	# 行 6 在上、行 5 在下（行号越大越靠下）
	var y_hi: float = pt(1, 6).y
	var y_lo: float = pt(1, 5).y
	var x0: float = pt(1, 1).x
	var x1: float = pt(Rules.COLS, 1).x

	# 河带：一档淡墨扫过
	draw_rect(Rect2(x0, y_hi, x1 - x0, y_lo - y_hi), Palette.PAPER_DIM, true)

	# 几笔水纹
	for i in 3:
		var pts := PackedVector2Array()
		var wy: float = y_hi + 13.0 + float(i) * 10.0
		for k in range(0, 29):
			var t: float = float(k) / 28.0
			pts.append(Vector2(x0 + t * (x1 - x0), wy + sin(t * TAU * 1.6 + float(i) * 1.7) * 2.2))
		var wc := Palette.INK_PALE
		wc.a = 0.55
		draw_polyline(pts, wc, 1.0)


func _draw_river_text() -> void:
	var y_hi: float = pt(1, 6).y
	var y_lo: float = pt(1, 5).y
	var mid: float = (y_hi + y_lo) * 0.5

	# 楚河 / 汉界：**必须避开三座桥**（列 3 / 5 / 7），
	# 所以分别居中在列 2 和列 8 上 —— 放中间一定会被桥压住。
	_draw_centered("楚 河", Vector2(pt(2, 1).x, mid + 7.5), 20, Palette.INK_MID)
	_draw_centered("汉 界", Vector2(pt(8, 1).x, mid + 7.5), 20, Palette.INK_MID)


# ------------------------------------------------------------------ 桥
#
# 【为什么拆成两半】桥面是一块填充矩形，范围正好 `x ∈ [桥心±9], y ∈ [行6, 行5]`。
# Godot 的 draw_rect 覆盖的是「像素中心落在矩形内」的那些行 —— 于是
# **行 6 那条河岸线落在矩形上边界之外、逃掉了；行 5 那条落在矩形内、被吃掉了**。
# 症状就是你看到的那句：上沿的河岸线横穿桥面，下沿的在桥面处断开，两头不一致。
# （像素实测：上沿 y=263 是 `100-380` 一条连续线；
#   下沿 y=309 是 `100-133 / 150-225 / 242-317 / 334-380` ——
#   三个断口 132-150 / 224-242 / 316-334 正好是三座桥的 18px 桥面。）
# 【修法】桥面底色跟河带底色一起画在网格线**之前**；桥栏、桥板、断桥标记画在**之后**。
# 【不要改回去】ArchGuard 盯着这两个调用顺序。

func _draw_bridge_decks() -> void:
	var y_hi: float = pt(1, 6).y
	var y_lo: float = pt(1, 5).y
	for col in Rules.BRIDGE_COLS:
		if not game.bridge_open(col):
			continue
		var cx: float = pt(col, 1).x
		var deck := Palette.PAPER_HI
		if game.bridge_temp(col):
			deck = Palette.INDIGO
			deck.a = 0.22
		draw_rect(Rect2(cx - 9.0, y_hi, 18.0, y_lo - y_hi), deck, true)


func _draw_bridge_rails() -> void:
	var y_hi: float = pt(1, 6).y
	var y_lo: float = pt(1, 5).y
	var mid: float = (y_hi + y_lo) * 0.5

	for col in Rules.BRIDGE_COLS:
		var cx: float = pt(col, 1).x
		var is_temp: bool = game.bridge_temp(col)
		var is_open: bool = game.bridge_open(col)

		if not is_open:
			# 断桥：只留四截断头 + 中央一个朱砂叉
			for sy in [y_hi, y_lo]:
				var d: float = 9.0 if sy == y_hi else -9.0
				draw_line(Vector2(cx - 9.0, sy), Vector2(cx - 9.0, sy + d), Palette.CINNABAR, 1.8)
				draw_line(Vector2(cx + 9.0, sy), Vector2(cx + 9.0, sy + d), Palette.CINNABAR, 1.8)
			draw_line(Vector2(cx - 6.5, mid - 6.5), Vector2(cx + 6.5, mid + 6.5), Palette.CINNABAR, 2.2)
			draw_line(Vector2(cx - 6.5, mid + 6.5), Vector2(cx + 6.5, mid - 6.5), Palette.CINNABAR, 2.2)
			continue

		# 通 / 浮桥：三道横板 + 两侧桥栏（桥面已在 _draw_bridge_decks 里画过）
		var edge: Color = Palette.INDIGO if is_temp else Palette.INK_MID
		for i in 3:
			var by: float = y_hi + (y_lo - y_hi) * (float(i) + 0.5) / 3.0
			draw_line(Vector2(cx - 9.0, by), Vector2(cx + 9.0, by), edge, 1.2)
		draw_line(Vector2(cx - 9.0, y_hi), Vector2(cx - 9.0, y_lo), edge, 1.7)
		draw_line(Vector2(cx + 9.0, y_hi), Vector2(cx + 9.0, y_lo), edge, 1.7)


# ------------------------------------------------------------------ 标记

func _draw_marks() -> void:
	# ① 最近一步：淡墨**方框**。
	# 一开始画的是实心圆光晕，结果是一坨硬边灰饼，看着像脏点不像痕迹。
	# 改方形：圆圈已经被「可吃 / 选中 / 可部署」占满了，方形是不会认错的形状。
	for v in last_move:
		var q: Vector2 = pt(v.x, v.y)
		var s := 15.0
		draw_rect(Rect2(q - Vector2(s, s), Vector2(s * 2.0, s * 2.0)),
			Palette.INK_LIGHT, false, 1.6)

	# ② 死路：淡墨叉。形状编码，不靠颜色。
	# 画小一点、实一点 —— 太大太虚会和旁边的花青虚线圈糊成一片噪声。
	for v in trap_cells:
		var q: Vector2 = pt(v.x, v.y)
		draw_line(q + Vector2(-5.0, -5.0), q + Vector2(5.0, 5.0), Palette.INK_MID, 1.8)
		draw_line(q + Vector2(-5.0, 5.0), q + Vector2(5.0, -5.0), Palette.INK_MID, 1.8)

	# ③ 可选目标：花青**虚线**环（虚线本身就是形状编码）
	for v in targets:
		_dashed_ring(pt(v.x, v.y), 17.5, Palette.INDIGO, 2.2, 10)

	# ④ 走法
	for m in moves:
		var p: Vector2 = pt(m.c, m.r)
		if m.cap != "":
			# 可吃：朱砂环 + 四道短齿 —— 和小圆点完全不同的轮廓
			draw_arc(p, 18.5, 0.0, TAU, 32, Palette.CINNABAR, 2.6)
			for k in 4:
				var ang: float = TAU * float(k) / 4.0 + PI * 0.25
				var d := Vector2(cos(ang), sin(ang))
				draw_line(p + d * 13.5, p + d * 21.5, Palette.CINNABAR, 2.0)
		else:
			# 可走：焦墨实心小圆点
			var dot := Palette.INK_HEAVY
			dot.a = 0.62
			draw_circle(p, 5.5, dot)


## 虚线圈：draw_arc 没有虚线模式，自己分成若干段画
func _dashed_ring(center: Vector2, radius: float, col: Color, width: float, segs: int) -> void:
	var step: float = TAU / float(segs)
	var on: float = step * 0.58
	for i in segs:
		var a0: float = float(i) * step
		draw_arc(center, radius, a0, a0 + on, 6, col, width)


# ------------------------------------------------------------------ 棋子

func _draw_pieces() -> void:
	for piece in game.pieces:
		var p: Vector2 = pt(piece.c, piece.r)
		var side: Color = Palette.CINNABAR if piece.owner == "r" else Palette.INK_BURNT

		# ① 投影：2D 里没有模糊，用三圈递减透明度假装柔光
		for i in 3:
			var sh := Palette.INK_BURNT
			sh.a = 0.05 + 0.028 * float(i)
			draw_circle(p + Vector2(1.7, 2.5), PIECE_R + 3.5 - float(i) * 1.7, sh)

		# ② 子面（比纸再亮一档，好让子从纸面上浮起来）
		draw_circle(p, PIECE_R, Palette.PAPER_HI)

		# ③ 外圈 + ④ 内圈：象棋子的双圈
		draw_arc(p, PIECE_R, 0.0, TAU, 40, side, 2.2)
		var inner := side
		inner.a = 0.5
		draw_arc(p, PIECE_R - 4.2, 0.0, TAU, 36, inner, 0.9)

		# ⑤ 字。楷体笔画细，20px 下有点飘 —— 微偏移重绘一次当假粗体。
		var ch: String = piece._label()
		_draw_centered(ch, p + Vector2(0.0, 7.8), 21, side)
		_draw_centered(ch, p + Vector2(0.6, 7.8), 21, side)

		# ⑥ 装备角标：一枚小印，写**装备后的兵种**（马/车/炮），不是「兵」。
		# 10px 的楷体糊成一团，所以放大到 16px 框 + 12px 字，再描一次加粗。
		if piece.gear != "":
			var bp: Vector2 = p + Vector2(PIECE_R - 7.0, PIECE_R - 7.0)
			draw_rect(Rect2(bp - Vector2(8, 8), Vector2(16, 16)), side, true)
			var gl: String = piece.gear_label()
			_draw_centered(gl, bp + Vector2(0.0, 4.2), 12, Palette.PAPER_HI)
			_draw_centered(gl, bp + Vector2(0.4, 4.2), 12, Palette.PAPER_HI)

		# ⑦ 被缚：重墨一个字（朱砂已经身兼两职了，这里不再加红）
		if game.is_rooted(piece.id):
			_draw_centered("缚", p + Vector2(0.0, -PIECE_R - 0.5), 12, Palette.INK_HEAVY)

		# ⑧ 空城计护罩
		if piece.is_king() and game.is_shielded(piece.owner):
			draw_arc(p, PIECE_R + 3.5, 0.0, TAU, 36, Palette.INDIGO, 1.8)

	# ⑨ 选中最后画，保证盖在所有子上：花青粗环 + 四角括号
	if selected_id != "":
		var sel = game.find_piece(selected_id)
		if sel != null:
			var p: Vector2 = pt(sel.c, sel.r)
			draw_arc(p, 20.0, 0.0, TAU, 40, Palette.INDIGO, 2.8)
			var e := 24.0
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var corner: Vector2 = p + Vector2(sx * e, sy * e)
					draw_line(corner, corner - Vector2(sx * 7.0, 0.0), Palette.INDIGO, 2.6)
					draw_line(corner, corner - Vector2(0.0, sy * 7.0), Palette.INDIGO, 2.6)


# ------------------------------------------------------------------ 宣纸纤维

## 96×96 可平铺的纤维纹理。用纯函数哈希而不是随机数 ——
## 每次启动纹理必须一模一样，否则重绘时会闪。
func _make_grain() -> ImageTexture:
	var n := 96
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		var fib: float = _hash01(y * 7 + 3)          # 每行的纤维深浅
		for x in n:
			var g: float = _hash01(x * 31 + y * 17 + 5)
			var v: float = 0.5 + (g - 0.5) * 0.5 + (fib - 0.5) * 0.7
			var a: float = clampf(absf(v - 0.5), 0.0, 1.0) * 0.5
			img.set_pixel(x, y, Color(0.42, 0.39, 0.33, a))
	return ImageTexture.create_from_image(img)


func _hash01(i: int) -> float:
	var x: int = (i * 1103515245 + 12345) & 0x7fffffff
	x = (x ^ (x >> 13)) * 1274126177
	x = x & 0x7fffffff
	return float(x % 100003) / 100003.0
