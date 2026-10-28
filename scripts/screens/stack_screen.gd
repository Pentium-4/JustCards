extends BasePopup
## Экран карточек одного стака.
##
## Экран открывается поверх главного экрана с размытием, поэтому он
## наследует BasePopup: анимация появления и исчезновения уже готова.
##
## Как устроено:
##   - данные карточек живут в AppData, экран их только показывает и
##     просит AppData что-то поменять;
##   - сама карточка — отдельная сцена CardView. При листании старая
##     карточка улетает, а новая влетает: это два разных экземпляра CardView;
##   - порядок показа хранится отдельно от данных, в _order. Обычно это
##     [0, 1, 2, 3...], а после перемешивания, например, [2, 0, 3, 1].
##     Сами карточки в стаке при этом не переставляются, поэтому при выходе
##     порядок «сбрасывается» сам собой — просто список выбрасывается.

const CARD_SCENE := preload("res://scenes/ui/card_view.tscn")
const CONFIRM_POPUP_SCENE := preload("res://scenes/popups/confirm_popup.tscn")

const SLIDE_TIME := 0.35

var stack_id := ""

@onready var _card_holder: Control = %CardHolder
@onready var _close_button: IconButton = %CloseButton
@onready var _rotate_all_button: IconButton = %RotateAllButton
@onready var _shuffle_button: IconButton = %ShuffleButton
@onready var _add_card_button: IconButton = %AddCardButton
@onready var _loop_button: IconButton = %LoopButton
@onready var _popup_layer: Control = %PopupLayer

## Порядок показа: номера карточек в стаке.
var _order: Array[int] = []
## Позиция в _order, которая сейчас на экране.
var _position := 0
## Какой стороной сейчас повёрнута текущая карточка.
var _showing_back := false
## Текущая карточка на экране.
var _card: CardView
## Пока идёт анимация, новые команды игнорируем.
var _busy := false
## Куда положить картинку, когда пользователь её выберет.
var _image_target := {}


func setup(id: String) -> void:
	stack_id = id


func _exit_tree() -> void:
	# Экран стака закрыли — его картинки больше не нужны в памяти.
	AppData.clear_texture_cache()


func _ready() -> void:
	super()
	_close_button.pressed.connect(close)
	_rotate_all_button.pressed.connect(_rotate_all)
	_shuffle_button.pressed.connect(_shuffle)
	_add_card_button.pressed.connect(_add_card)
	_loop_button.toggled.connect(_on_loop_toggled)
	ImagePicker.image_picked.connect(_on_image_picked)

	var stack := AppData.find_stack(stack_id)
	_loop_button.set_pressed_no_signal(stack.get("loop", false))
	_loop_button.sync_state()
	for i in AppData.card_count(stack_id):
		_order.append(i)
	_showing_back = _default_back()
	_card = _create_card()


# ---------------------------------------------------------------------------
# Небольшие помощники
# ---------------------------------------------------------------------------

## Номер текущей карточки в стаке.
func _card_index() -> int:
	return _order[_position]


func _side_name() -> String:
	return "back" if _showing_back else "front"


func _current_side() -> Dictionary:
	return AppData.get_side(stack_id, _card_index(), _side_name())


## Режим ROTATE ALL: какой стороной открываются карточки.
func _default_back() -> bool:
	return AppData.find_stack(stack_id).get("show_back", false)


func _is_loop() -> bool:
	return _loop_button.button_pressed


## Создаёт карточку для текущей позиции и подключает её сигналы.
func _create_card() -> CardView:
	var card: CardView = CARD_SCENE.instantiate()
	_card_holder.add_child(card)
	card.pivot_offset = card.size / 2.0
	card.show_side(_current_side())
	_update_navigation(card)
	card.text_edited.connect(_on_text_edited)
	card.add_image_pressed.connect(_on_add_image_pressed)
	card.delete_pressed.connect(_on_delete_pressed)
	card.flip_pressed.connect(_flip)
	card.prev_pressed.connect(_go.bind(-1))
	card.next_pressed.connect(_go.bind(1))
	card.swiped.connect(_go)
	card.image_remove_requested.connect(_on_image_remove_requested)
	return card


func _update_navigation(card: CardView) -> void:
	var count := _order.size()
	card.set_navigation(count > 1, _is_loop() or _position > 0, _is_loop() or _position < count - 1)


func _ask_remove(on_answer: Callable) -> void:
	var popup := CONFIRM_POPUP_SCENE.instantiate()
	popup.answered.connect(on_answer)
	_popup_layer.add_child(popup)


# ---------------------------------------------------------------------------
# Листание
# ---------------------------------------------------------------------------

## direction: +1 = следующая карточка, -1 = предыдущая.
func _go(direction: int) -> void:
	if _busy or _order.size() < 2:
		return
	var new_position := _position + direction
	if _is_loop():
		new_position = wrapi(new_position, 0, _order.size())
	elif new_position < 0 or new_position >= _order.size():
		_bounce(direction) # дальше карточек нет
		return
	_position = new_position
	_showing_back = _default_back() # новая карточка открывается стороной режима
	_replace_card("next" if direction > 0 else "prev")


## Заменяет текущую карточку на новую с анимацией.
## how: "next", "prev", "add", "delete", "shuffle".
func _replace_card(how: String) -> void:
	_busy = true
	var old := _card
	old.release_word_focus()
	old.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = _create_card()
	var card := _card
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	match how:
		"next", "prev", "shuffle":
			# Старая улетает в одну сторону, новая прилетает с другой.
			var side := 1.0 if how != "prev" else -1.0
			card.position.x = 1300.0 * side
			card.rotation_degrees = 10.0 * side
			tween.tween_property(card, "position:x", 0.0, SLIDE_TIME)
			tween.tween_property(card, "rotation_degrees", 0.0, SLIDE_TIME)
			tween.tween_property(old, "position:x", -1300.0 * side, SLIDE_TIME)
			tween.tween_property(old, "rotation_degrees", -10.0 * side, SLIDE_TIME)
		"add":
			# Новая вылетает снизу поверх старой.
			card.position.y = 2600.0
			tween.tween_property(card, "position:y", 0.0, SLIDE_TIME + 0.1).set_trans(Tween.TRANS_BACK)
		"delete":
			# Старая сжимается и тает, новая проявляется под ней.
			_card_holder.move_child(card, 0)
			card.scale = Vector2.ONE * 0.92
			card.modulate.a = 0.0
			tween.tween_property(old, "scale", Vector2.ONE * 0.6, SLIDE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tween.tween_property(old, "modulate:a", 0.0, SLIDE_TIME)
			tween.tween_property(card, "scale", Vector2.ONE, SLIDE_TIME).set_delay(0.15)
			tween.tween_property(card, "modulate:a", 1.0, SLIDE_TIME).set_delay(0.15)

	await tween.finished
	old.queue_free()
	_busy = false


## Лёгкий толчок, когда листать дальше некуда.
func _bounce(direction: int) -> void:
	_busy = true
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(_card, "position:x", -40.0 * direction, 0.1)
	tween.tween_property(_card, "position:x", 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	_busy = false


func _unhandled_input(event: InputEvent) -> void:
	# На ПК можно листать стрелками клавиатуры (если не печатаем слово).
	if event.is_action_pressed("ui_left"):
		_go(-1)
	elif event.is_action_pressed("ui_right"):
		_go(1)


# ---------------------------------------------------------------------------
# Кнопки
# ---------------------------------------------------------------------------

func _flip() -> void:
	if _busy:
		return
	_busy = true
	_showing_back = not _showing_back
	await _card.flip_to(_current_side())
	_busy = false


## ROTATE ALL: переключает режим стака, и текущая карточка поворачивается
## стороной этого режима.
func _rotate_all() -> void:
	if _busy:
		return
	var show_back := not _default_back()
	AppData.set_show_back(stack_id, show_back)
	if _showing_back != show_back:
		_flip()


func _add_card() -> void:
	if _busy:
		return
	var new_index := AppData.add_card(stack_id)
	# Новая карточка встаёт сразу после текущей в порядке показа.
	_position = mini(_position + 1, _order.size())
	_order.insert(_position, new_index)
	_showing_back = _default_back()
	_replace_card("add")


func _shuffle() -> void:
	if _busy or _order.size() < 2:
		_wiggle(_shuffle_button)
		return
	_order.shuffle()
	_position = 0
	_showing_back = _default_back()
	_replace_card("shuffle")


func _on_loop_toggled(on: bool) -> void:
	AppData.set_loop(stack_id, on)
	_update_navigation(_card)


func _on_delete_pressed() -> void:
	if _busy:
		return
	_ask_remove(func(yes: bool):
		if yes:
			_delete_current_card()
	)


func _delete_current_card() -> void:
	var removed := _card_index()
	AppData.delete_card(stack_id, removed)
	# Убираем номер из порядка показа, а номера после него сдвигаем на 1,
	# потому что в стаке карточки после удалённой тоже сдвинулись.
	_order.remove_at(_position)
	for i in _order.size():
		if _order[i] > removed:
			_order[i] -= 1
	if _order.is_empty():
		_order.append(0) # стак не бывает пустым: AppData создал новую карточку
	_position = mini(_position, _order.size() - 1)
	_showing_back = _default_back()
	_replace_card("delete")


func _on_text_edited(text: String) -> void:
	AppData.set_card_text(stack_id, _card_index(), _side_name(), text)


# ---------------------------------------------------------------------------
# Картинки
# ---------------------------------------------------------------------------

func _on_add_image_pressed() -> void:
	_image_target = {"index": _card_index(), "side": _side_name()}
	ImagePicker.pick_image()


func _on_image_picked(image: Image) -> void:
	if _image_target.is_empty():
		return
	AppData.set_card_image(stack_id, _image_target["index"], _image_target["side"], image)
	# Если пользователь всё ещё на той же стороне той же карточки — показываем.
	if _image_target["index"] == _card_index() and _image_target["side"] == _side_name():
		_card.show_side(_current_side())
	_image_target = {}


func _on_image_remove_requested() -> void:
	_ask_remove(func(yes: bool):
		_card.finish_image_drag(yes)
		if yes:
			AppData.remove_card_image(stack_id, _card_index(), _side_name())
			_card.show_side(_current_side())
	)


func _wiggle(control: Control) -> void:
	control.pivot_offset = control.size / 2.0
	var tween := create_tween()
	for angle in [-12.0, 10.0, -6.0, 3.0, 0.0]:
		tween.tween_property(control, "rotation_degrees", angle, 0.06)
