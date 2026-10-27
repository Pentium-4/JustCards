extends BasePopup
## Универсальный попап «REMOVE?» с ответами да / нет.
##
## Он не знает, ЧТО удаляется: стак, карточка или картинка. Он только
## отправляет сигнал answered(true или false), а решает экран, который
## его открыл. Поэтому один попап подходит для всего приложения.

signal answered(yes: bool)

## Текст вопроса.
@export var question := "REMOVE?":
	set(value):
		question = value
		if is_node_ready():
			_question_label.text = value

@onready var _question_label: Label = %QuestionLabel
@onready var _yes_button: IconButton = %YesButton
@onready var _no_button: IconButton = %NoButton


func _ready() -> void:
	super()
	_question_label.text = question
	_yes_button.pressed.connect(_answer.bind(true))
	_no_button.pressed.connect(_answer.bind(false))


## «Назад» / Esc означает «нет».
func cancel() -> void:
	_answer(false)


func _answer(yes: bool) -> void:
	if _closing:
		return
	answered.emit(yes)
	close()
