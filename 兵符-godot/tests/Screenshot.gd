extends SceneTree
## 截图工具：开一个真窗口渲染主场景，把画面存成 PNG 后立刻退出。
##
## 【为什么需要它】无头测试只能验证数据对不对，验证不了「画得出来吗」。
## 到目前它已经抓到两个断言抓不到的 bug：
##   ① 棋盘底板少算两侧留白 → 边行的棋子挂在纸外面（当时 245 条断言全绿）
##   ② draw_string 传 alignment=CENTER + width 会从 pos.x + w/2 起头
##      → 棋子圆圈是空的，字全挤在圈右边（缩放看截图看不出来，放大才露）
##
## 它出两张图：
##   _shot.png        —— 开局布阵状态（平时验收用这张）
##   _shot_states.png —— 一个「什么状态都有」的盘面，用来核对几种状态编码是否分得开
##
## 跑法：run.bat shot      （会闪一个窗口，属正常）

const Rules := preload("res://engine/Rules.gd")

const OUT_A := "res://_shot.png"
const OUT_B := "res://_shot_states.png"
const WARMUP := 4              ## 等 _draw 真的跑完，1 帧不够


func _initialize() -> void:
	var packed = load("res://scenes/Main.tscn")
	if packed == null:
		printerr("主场景加载失败")
		quit(1)
		return
	var main = packed.instantiate()
	root.add_child(main)
	main.setup()

	# ---- 图一：开局布阵（能看到蓝圈部署区、灰叉死路、两侧的士）----
	main.game.phase = "play"
	main.game.turn = "r"
	main.game.ap = 2
	main.game.move_used = false
	main.game.hands.r = [{"kind": "pawn"}, {"kind": "pawn"}]
	main._rebuild_hand()
	main.click_card(0)
	if not await _shoot(main, OUT_A):
		quit(1)
		return
	print("  图一 布阵状态：死路格 ", main.trap_cells.size(),
		" · 可部署格 ", main.view.targets.size())

	# ---- 图二：把所有状态编码摆在一张盘上 ----
	_build_state_board(main)
	if not await _shoot(main, OUT_B):
		quit(1)
		return
	print("  图二 状态验收：选中走法 ", main.sel_moves.size(),
		" · 可部署 ", main.view.targets.size(), " · 死路 ", main.view.trap_cells.size())

	print("截图完成。验收要点：棋子字必须在圈**正中**（偏右就是又踩了 draw_string 那个坑）。")
	quit(0)


func _shoot(main, path: String) -> bool:
	for i in WARMUP:
		await process_frame
	var img: Image = root.get_texture().get_image()
	var out: String = ProjectSettings.globalize_path(path)
	var err: int = img.save_png(out)
	if err != OK:
		printerr("存图失败 err=", err, " path=", out)
		return false
	print("已存 ", out, "  ", img.get_size())
	return true


## 摆一个「每种状态都有」的盘面：选中 / 可走 / 可吃 / 可部署 / 死路 /
## 最近一步 / 断桥 / 浮桥 / 已装备 / 被缚 / 空城计。
func _build_state_board(main) -> void:
	var g = main.game
	g.phase = "play"
	g.turn = "r"
	g.ap = 2
	g.move_used = false

	g.pieces.clear()
	g._spawn("r", "king", 5, 2)
	g._spawn("b", "king", 5, 9)
	g._spawn("r", "advisor", 4, 1)
	g._spawn("r", "advisor", 6, 1)
	g._spawn("b", "advisor", 4, 10)
	g._spawn("b", "advisor", 6, 10)
	g._spawn("r", "pawn", 3, 5)
	g._spawn("b", "pawn", 7, 6)

	var rook = g._spawn("r", "chariot", 5, 5)
	rook.gear = "horse"          # 注意：gear 存的是英文兵种名，不是「马」
	var rooted = g._spawn("r", "cannon", 3, 6)
	g.add_effect("root", 2, "b", {"pieceId": rooted.id})
	g.add_effect("shield", 2, "b", {"owner": "b"})
	g.add_effect("bridge_temp", 2, "r", {"col": 5})
	g.add_effect("bridge_broken", 3, "r", {"col": 7})

	# 被缚要挂在**别的**子身上：挂到选中的子上的话它就走不动，
	# 可走/可吃一个都验收不到（第一版就踩了这个坑，moves 一直是 0）。
	main.selected_id = rook.id
	main.sel_moves = g.legal_moves(rook)
	main.view.last_move = [Vector2i(5, 4)]

	g.hands = {"r": [{"kind": "pawn"}], "b": []}
	main._rebuild_hand()
	var cells: Array = g.deploy_cells("r")
	var traps: Array = []
	for v in cells:
		if not Rules.is_bridge_col(v.x):
			traps.append(v)
	main.hint_text = "状态验收\n选中=花青粗环+四角括号 ｜ 可走=焦墨点 ｜ 可吃=朱砂齿圈 ｜ 可部署=花青虚线\n死路=灰叉 ｜ 最近一步=淡墨方框 ｜ 断桥=朱砂叉 ｜ 浮桥=花青桥\n已装备=方印（写装备后的兵种）｜ 被绊=缚 ｜ 空城计=花青环"
	main._refresh()
	# _refresh 会用 _current_targets() 覆盖 targets，所以摆完再写回去
	main.view.targets = cells
	main.view.trap_cells = traps
	main.view.queue_redraw()
