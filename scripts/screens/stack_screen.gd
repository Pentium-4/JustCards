extends BasePopup
## Экран карточек одного стака.
##
## ВРЕМЕННАЯ ВЕРСИЯ (этап 1): показывает название стака и кнопку выхода.
## Сами карточки, переворот и листание появятся на этапе 2.
##
## Экран открывается поверх главного экрана с размытием, поэтому он
## наследует BasePopup: анимация появления и исчезновения уже готова.

var stack_id := ""

@onready var _name_label: Label = %NameLabel
@onready var _close_button: IconButton = %CloseButton


func setup(id: String) -> void:
	stack_id = id


func _ready() -> void:
	super()
	_name_label.text = AppData.find_stack(stack_id).get("name", "")
	_close_button.pressed.connect(close)
