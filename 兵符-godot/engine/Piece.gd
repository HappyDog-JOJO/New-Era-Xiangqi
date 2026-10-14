extends RefCounted
## 一个棋子（纯数据）。
##
## 【架构约定】主将与士「不是卡牌」：它们的 card 为空字典，
## 被吃时不进弃牌堆。只有 card 非空的棋子才会在阵亡时把牌送去弃牌堆。

const Rules := preload("res://engine/Rules.gd")

var id: String = ""
var owner: String = "r"        ## "r" / "b"
var kind: String = "pawn"      ## king / advisor / elephant / pawn / horse / chariot / cannon
var c: int = 1
var r: int = 1
var gear: String = ""          ## "" 或 horse / chariot / cannon
var card: Dictionary = {}      ## 打出它的那张兵种牌（主将 / 士为空）
var gear_card: Dictionary = {} ## 叠在它下面的装备牌


func _init(p_id := "", p_owner := "r", p_kind := "pawn", p_c := 1, p_r := 1) -> void:
	id = p_id
	owner = p_owner
	kind = p_kind
	c = p_c
	r = p_r


## 移动时实际使用的兵种：装了装备就按装备走
func kind_now() -> String:
	return gear if gear != "" else kind


## 是不是「卡牌棋子」——决定阵亡时会不会产生弃牌
func is_card_piece() -> bool:
	return kind != "king" and kind != "advisor"


func is_king() -> bool:
	return kind == "king"


func is_advisor() -> bool:
	return kind == "advisor"


func is_elephant() -> bool:
	return kind == "elephant"


func locate() -> Vector2i:
	return Vector2i(c, r)


func describe() -> String:
	return "%s%s%s" % [Rules.side_name(owner), _label(), Rules.cell_name(c, r)]


func _label() -> String:
	match kind:
		"king": return "帅" if owner == "r" else "将"
		"advisor": return "仕" if owner == "r" else "士"
		"elephant": return "相" if owner == "r" else "象"
		"pawn": return "兵" if owner == "r" else "卒"
		"horse": return "马"
		"chariot": return "车"
		"cannon": return "炮"
	return kind


## 装备角标上写的字 —— 让人一眼看出这个兵「现在按什么走」。
## 不写「兵」是因为那不是信息：小兵装上马之后，玩家真正要知道的是它变成马了。
func gear_label() -> String:
	match gear:
		"horse": return "马"
		"chariot": return "车"
		"cannon": return "炮"
	return "装"
