extends Control
## Главный экран: таблица стаков, кнопка «+», корзина и кнопка резервной копии.
##
## Как экран связан с остальным приложением:
##   - данные берёт из AppData и подписан на его сигнал stacks_changed;
##   - когда стак открывают, отправляет сигнал stack_opened, а Main
##     показывает экран карточек. Сам экран про экран карточек не знает.

signal stack_opened(stack_id: String)

const TILE_SCENE := preload("res://scenes/ui/stack_tile.tscn")
const CREATE_POPUP_SCENE := preload("res://scenes/popups/create_stack_popup.tscn")
const CONFIRM_POPUP_SCENE := preload("res://scenes/popups/confirm_popup.tscn")

const SAVE_ICON := preload("res://assets/icons/icon_save.svg")
const LOAD_ICON := preload("res://assets/icons/icon_load.svg")
const SAVE_COLOR := Color("#FB7C5E")
const LOAD_COLOR := Color(0.988, 0.482, 0.31, 0.7)

## Насколько далеко от корзины (в пикселях макета) ещё засчитывается попадание.
const TRASH_MAGNET := 50.0

@onready var _scroll: SmoothScrollContainer = %Scroll
@onready var _grid: GridContainer = %Grid
@onready var _add_button: IconButton = %AddButton
@onready var _scroll_bar: VScrollBar = %ScrollBar
@onready var _backup_button: IconButton = %BackupButton
@onready var _trash_button: IconButton = %TrashButton
@onready var _drag_layer: Control = %DragLayer
@onready var _popup_layer: Control = %PopupLayer

# Всё про текущий перенос плитки
var _drag_tile: StackTile
var _drag_ghost: StackTile
var _drag_offset := Vector2.ZERO
var _scroll_lock := 0
var _over_trash := false

var _backup_shows_save := true


func _ready() -> void:
	AppData.stacks_changed.connect(_rebuild_grid)
	BackupIO.backup_loaded.connect(_on_backup_loaded)
	_add_button.pressed.connect(_open_create_popup)
	_backup_button.pressed.connect(_on_backup_pressed)
	_trash_button.pressed.connect(_wiggle.bind(_trash_button))

	# Наш собственный ползунок справа «делит» значения с невидимым
	# ползунком ScrollContainer: двигается один — двигается и другой.
	var inner_bar := _scroll.get_v_scroll_bar()
	_scroll_bar.share(inner_bar)
	inner_bar.changed.connect(_update_scroll_bar_visibility)

	_rebuild_grid()
	_update_backup_button(false)


func _process(_delta: float) -> void:
	# Пока тащим плитку, список стоит на месте.
	if _drag_ghost:
		_scroll.scroll_vertical = _scroll_lock


# ---------------------------------------------------------------------------
# Таблица стаков
# ---------------------------------------------------------------------------

## Пересобирает таблицу по данным из AppData. Вызывается при каждом изменении.
## Пересоздать пару десятков плиток проще и надёжнее, чем искать, что поменялось.
func _rebuild_grid() -> void:
	for child in _grid.get_children():
		if child != _add_button:
			_grid.remove_child(child)
			child.queue_free()

	for stack in AppData.stacks:
		var tile: StackTile = TILE_SCENE.instantiate()
		_grid.add_child(tile)
		tile.setup(stack["id"], stack["name"])
		tile.tapped.connect(_on_tile_tapped)
		tile.drag_started.connect(_on_drag_started)
		tile.drag_moved.connect(_on_drag_moved)
		tile.drag_ended.connect(_on_drag_ended)

	_update_backup_button(true)


func _update_scroll_bar_visibility() -> void:
	# Ползунок виден, только когда стаки не помещаются на экран.
	var bar := _scroll.get_v_scroll_bar()
	_scroll_bar.visible = bar.max_value > bar.page + 1.0


func _find_tile(stack_id: String) -> StackTile:
	for child in _grid.get_children():
		if child is StackTile and child.stack_id == stack_id:
			return child
	return null


func _on_tile_tapped(stack_id: String) -> void:
	stack_opened.emit(stack_id)


# ---------------------------------------------------------------------------
# Создание стака
# ---------------------------------------------------------------------------

func _open_create_popup() -> void:
	var popup := CREATE_POPUP_SCENE.instantiate()
	popup.confirmed.connect(_on_new_stack_confirmed.bind(popup))
	_popup_layer.add_child(popup)


func _on_new_stack_confirmed(stack_name: String, popup: BasePopup) -> void:
	var stack := AppData.create_stack(stack_name)
	var tile := _find_tile(stack["id"])
	if tile:
		_pop_in(tile)
		_scroll.ensure_control_visible.call_deferred(tile)
	# Ждём, пока попап закроется, и открываем новый стак.
	await popup.closed
	stack_opened.emit(stack["id"])


# ---------------------------------------------------------------------------
# Перенос плитки в корзину
# ---------------------------------------------------------------------------

func _on_drag_started(tile: StackTile, pointer_position: Vector2) -> void:
	_drag_tile = tile
	_drag_ghost = tile.make_ghost()
	_drag_layer.add_child(_drag_ghost)
	_drag_ghost.global_position = tile.global_position
	_drag_ghost.pivot_offset = tile.size / 2.0
	_drag_offset = tile.global_position - pointer_position
	_scroll_lock = _scroll.scroll_vertical
	_scroll.stop_smooth_scroll()
	_over_trash = false

	tile.modulate.a = 0.25
	create_tween().tween_property(_drag_ghost, "scale", Vector2.ONE * 1.12, 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_drag_moved(pointer_position: Vector2) -> void:
	if _drag_ghost == null:
		return
	_drag_ghost.global_position = pointer_position + _drag_offset
	var over := _is_over_trash(pointer_position)
	if over != _over_trash:
		_over_trash = over
		# Подсказка: корзина увеличивается, а плитка уменьшается над ней.
		var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(_trash_button, "scale", Vector2.ONE * (1.25 if over else 1.0), 0.2)
		tween.tween_property(_drag_ghost, "scale", Vector2.ONE * (0.8 if over else 1.12), 0.2)


func _on_drag_ended(pointer_position: Vector2) -> void:
	if _drag_ghost == null:
		return
	create_tween().tween_property(_trash_button, "scale", Vector2.ONE, 0.2)
	if _is_over_trash(pointer_position):
		var popup := CONFIRM_POPUP_SCENE.instantiate()
		popup.answered.connect(_on_delete_answered)
		_popup_layer.add_child(popup)
	else:
		_return_ghost()


func _on_delete_answered(yes: bool) -> void:
	if yes:
		var ghost := _drag_ghost
		AppData.delete_stack(_drag_tile.stack_id)
		_drag_ghost = null
		_drag_tile = null
		var tween := create_tween().set_parallel()
		tween.tween_property(ghost, "scale", Vector2.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(ghost, "modulate:a", 0.0, 0.25)
		tween.chain().tween_callback(ghost.queue_free)
	else:
		_return_ghost()


## Плитка-призрак возвращается на своё место.
func _return_ghost() -> void:
	var ghost := _drag_ghost
	var tile := _drag_tile
	_drag_ghost = null
	_drag_tile = null
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(ghost, "global_position", tile.global_position, 0.3)
	tween.tween_property(ghost, "scale", Vector2.ONE, 0.3)
	tween.chain().tween_callback(func():
		ghost.queue_free()
		if is_instance_valid(tile):
			tile.modulate.a = 1.0
	)


func _is_over_trash(pointer_position: Vector2) -> bool:
	return _trash_button.get_global_rect().grow(TRASH_MAGNET).has_point(pointer_position)


# ---------------------------------------------------------------------------
# Резервная копия: одна кнопка, которая сама решает, что показать
# ---------------------------------------------------------------------------

## Есть стаки → кнопка «сохранить». Нет стаков → кнопка «загрузить».
func _update_backup_button(animated: bool) -> void:
	var show_save := AppData.has_stacks()
	if show_save == _backup_shows_save and animated:
		return
	_backup_shows_save = show_save
	if not animated:
		_apply_backup_look()
		return
	# Кнопка сжимается, меняет иконку и снова вырастает.
	var tween := create_tween()
	tween.tween_property(_backup_button, "scale", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(_apply_backup_look)
	tween.tween_property(_backup_button, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _apply_backup_look() -> void:
	_backup_button.icon_texture = SAVE_ICON if _backup_shows_save else LOAD_ICON
	_backup_button.bg_color = SAVE_COLOR if _backup_shows_save else LOAD_COLOR


func _on_backup_pressed() -> void:
	if AppData.has_stacks():
		BackupIO.save_backup(AppData.export_backup_text())
	else:
		BackupIO.open_backup()


func _on_backup_loaded(text: String) -> void:
	if not AppData.import_backup_text(text):
		_wiggle(_backup_button) # файл не подошёл — кнопка «мотает головой»


# ---------------------------------------------------------------------------
# Маленькие анимации
# ---------------------------------------------------------------------------

func _pop_in(control: Control) -> void:
	control.pivot_offset = control.size / 2.0
	control.scale = Vector2.ZERO
	create_tween().tween_property(control, "scale", Vector2.ONE, 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Покачивание. Например, если просто нажать на корзину: подсказка,
## что в неё нужно перетаскивать, а не нажимать.
func _wiggle(control: Control) -> void:
	control.pivot_offset = control.size / 2.0
	var tween := create_tween()
	for angle in [-12.0, 10.0, -6.0, 3.0, 0.0]:
		tween.tween_property(control, "rotation_degrees", angle, 0.06)
