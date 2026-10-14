extends RefCounted
## 水墨配色与字体 —— 全项目唯一的色值来源。
##
## 【为什么要有这个文件】之前 20 个硬编码色值散在 BoardView 和 Main 里，
## 结果一个 `#c0392b` 身兼三职（断桥 / 可吃 / 被缚）、一个 `#1f5fa8` 兼两职
## （浮桥 / 可选目标）。这种「一个颜色兼几个语义」的问题，散着写根本看不出来。
##
## 【配色纪律】**只有两个强调色**：
##   朱砂 CINNABAR —— 红方 / 吃子（危险）/ 断桥
##   花青 INDIGO   —— 选中 / 可选目标（操作）/ 浮桥
## 其余一律走**墨分五色**（焦 / 重 / 中 / 淡 / 清），不引入第三个色相。
##
## 棋盘上的 7 种状态同时用**形状**和**颜色**两重编码，不只靠颜色 ——
## 色弱玩家光看颜色分不出「可走」和「可吃」，但小圆点 vs 带齿圈的形状能分清。

# ---------------------------------------------------------------- 纸与裱
const PAPER      := Color("#f7f4ec")   ## 宣纸：棋盘面
const PAPER_HI   := Color("#fcfaf4")   ## 纸的高光：棋子底色（比纸再亮一点，好让子浮起来）
const PAPER_DIM  := Color("#ece7db")   ## 纸的暗部：河界带
const MOUNT      := Color("#d9d3c4")   ## 裱褙绢色：窗口底色
const MOUNT_DIM  := Color("#cbc4b2")   ## 裱边暗部：面板分隔线

# ---------------------------------------------------------------- 墨分五色
const INK_BURNT  := Color("#1c1a17")   ## 焦墨：黑方、正文
const INK_HEAVY  := Color("#3a352d")   ## 重墨：标题、按钮字
const INK_MID    := Color("#6b6459")   ## 中墨：网格线、次要文字
const INK_LIGHT  := Color("#a49c8d")   ## 淡墨：辅助线、死路标记
const INK_PALE   := Color("#cfc8b8")   ## 清墨：极淡的痕（最近一步的光晕）

# ---------------------------------------------------------------- 两个强调色
const CINNABAR   := Color("#a8322a")   ## 朱砂：红方 / 吃子 / 断桥
const INDIGO     := Color("#3a5a7a")   ## 花青：选中 / 可选目标 / 浮桥

# ---------------------------------------------------------------- 字体
## 棋子字与标题用楷体（有笔意）。系统没有楷体就退到宋体，再退到衬线。
const BRUSH_NAMES := [
	"KaiTi", "楷体", "STKaiti", "Kaiti SC", "SimSun", "宋体",
	"Noto Serif CJK SC", "serif",
]

## 面板小字用黑体。12px 的楷体在屏幕上会糊成一片，可读性优先。
const TEXT_NAMES := [
	"Microsoft YaHei UI", "Microsoft YaHei", "SimHei",
	"Noto Sans CJK SC", "PingFang SC", "sans-serif",
]


static func make_font(names: Array) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	return f


## 棋子 / 标题用的笔意字体
static func brush_font() -> Font:
	return make_font(BRUSH_NAMES)


## 面板小字用的无衬线字体
static func text_font() -> Font:
	return make_font(TEXT_NAMES)
