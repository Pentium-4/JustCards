class_name StackTile
extends Control
## Плитка одного стака в таблице на главном экране.
##
## Плитка только сообщает о жестах сигналами. Сами жесты распознаёт
## LongPressGesture (тот же объект используется для картинки на карточке).
## Что делать при переносе (показать корзину, удалить стак), решает экран.
## Плитка про корзину ничего не знает.

signal tapped(stack_id: String)
signal drag_started(tile: StackTile, pointer_position: Vector2)
signal drag_moved(pointer_position: Vector2)
signal drag_ended(pointer_position: Vector2)

var stack_id := ""

var _gesture := LongPressGesture.new()

@onready var _name_label: Label = %NameLabel


func _ready() -> void:
	# Пересылаем сигналы жеста наружу, добавляя к ним «кто это».
	_gesture.tapped.connect(func(): tapped.emit(stack_id))
	_gesture.drag_started.connect(func(pos: Vector2): drag_started.emit(self, pos))
	_gesture.drag_moved.connect(drag_moved.emit)
	_gesture.drag_ended.connect(drag_ended.emit)


func setup(id: String, stack_name: String) -> void:
	stack_id = id
	if not is_node_ready():
		await ready
	_name_label.text = stack_name


func _gui_input(event: InputEvent) -> void:
	# Если жест «съел» событие (тащим плитку), список не прокручивается.
	if _gesture.handle_input(event):
		accept_event()


func _process(delta: float) -> void:
	_gesture.update(delta, get_global_mouse_position())


## Плитка-«призрак», которая летает за пальцем во время переноса:
## выглядит так же, но на нажатия не реагирует.
func make_ghost() -> StackTile:
	var ghost: StackTile = load(scene_file_path).instantiate()
	ghost.setup(stack_id, _name_label.text)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.set_process(false)
	return ghost
