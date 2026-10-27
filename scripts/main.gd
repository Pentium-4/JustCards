extends Control
## Main — «режиссёр» приложения. Решает, какой экран сейчас показан.
##
## Экраны ничего не знают друг о друге. Каждый экран только сообщает
## сигналом, что случилось («нажали START», «открыли стак»), а Main решает,
## что показать дальше. Правило, которое стоит запомнить:
##     сигналы идут вверх (экран → Main), вызовы идут вниз (Main → экран).
## Благодаря этому любой экран можно переделать, не трогая остальные.

const START_SCREEN := preload("res://scenes/screens/start_screen.tscn")
const STACKS_SCREEN := preload("res://scenes/screens/stacks_screen.tscn")
const STACK_SCREEN := preload("res://scenes/screens/stack_screen.tscn")

const FADE_TIME := 0.35

@onready var _screens: Control = %Screens

var _current_screen: Control


func _ready() -> void:
	# На Android кнопка «Назад» по умолчанию закрывает приложение.
	# Отключаем это и решаем сами (см. _go_back).
	get_tree().quit_on_go_back = false
	var start := START_SCREEN.instantiate()
	start.start_pressed.connect(_show_stacks)
	_switch_to(start)


func _show_stacks() -> void:
	var stacks := STACKS_SCREEN.instantiate()
	stacks.stack_opened.connect(_open_stack)
	_switch_to(stacks)


## Экран стака открывается ПОВЕРХ экрана стаков (чтобы под ним было
## размытое меню), поэтому старый экран не убираем.
func _open_stack(stack_id: String) -> void:
	var stack_screen := STACK_SCREEN.instantiate()
	stack_screen.setup(stack_id)
	_screens.add_child(stack_screen)


## Плавная смена экрана: новый проявляется, старый растворяется и удаляется.
func _switch_to(new_screen: Control) -> void:
	var old_screen := _current_screen
	_current_screen = new_screen
	new_screen.modulate.a = 0.0
	_screens.add_child(new_screen)
	var tween := create_tween().set_parallel()
	tween.tween_property(new_screen, "modulate:a", 1.0, FADE_TIME)
	if old_screen:
		old_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tween.tween_property(old_screen, "modulate:a", 0.0, FADE_TIME)
		tween.chain().tween_callback(old_screen.queue_free)


# ---------------------------------------------------------------------------
# Кнопка «Назад» на Android и Esc на ПК
# ---------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()


## Закрывает самый верхний попап или экран стака. Если закрывать нечего,
## выходит из приложения (только на Android, на ПК окно закрывают крестиком).
func _go_back() -> void:
	# Все попапы и экран стака сами записываются в группу "popups"
	# (см. BasePopup). Последний в группе — самый верхний на экране.
	var popups := get_tree().get_nodes_in_group(BasePopup.GROUP)
	for i in range(popups.size() - 1, -1, -1):
		var popup: BasePopup = popups[i]
		if not popup.is_closing():
			popup.cancel()
			return
	if OS.has_feature("android"):
		get_tree().quit()
