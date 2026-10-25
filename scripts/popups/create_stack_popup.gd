extends BasePopup
## Попап создания стака: поле для названия, галочка «создать», корзина «отмена».
##
## Попап НЕ создаёт стак сам. Он только сообщает сигналом confirmed,
## какое название ввели, а решение принимает экран, который его открыл.

signal confirmed(stack_name: String)

@onready var _name_edit: LineEdit = %NameEdit
@onready var _confirm_button: IconButton = %ConfirmButton
@onready var _cancel_button: IconButton = %CancelButton


func _ready() -> void:
	super() # запускаем _ready родителя (BasePopup), там анимация появления
	_name_edit.text_changed.connect(_on_text_changed)
	_name_edit.text_submitted.connect(func(_text: String): _confirm())
	_confirm_button.pressed.connect(_confirm)
	_cancel_button.pressed.connect(close)
	_on_text_changed(_name_edit.text)
	_name_edit.grab_focus.call_deferred()


## Пока название пустое, галочка неактивна.
func _on_text_changed(text: String) -> void:
	_confirm_button.disabled = text.strip_edges().is_empty()


func _confirm() -> void:
	if _confirm_button.disabled or _closing:
		return
	confirmed.emit(_name_edit.text.strip_edges())
	close()
