class_name StackTile
extends Control
## Плитка одного стака в таблице на главном экране.
##
## Плитка только распознаёт жесты и сообщает о них сигналами:
##   - короткое нажатие            → tapped
##   - долгое нажатие и перенос    → drag_started / drag_moved / drag_ended
##   - обычный свайп               → ничего не делаем, событие уходит
##                                   к ScrollContainer, и он прокручивает список
## Что делать при переносе (показать корзину, удалить стак), решает экран.
## Плитка про корзину ничего не знает.

signal tapped(stack_id: String)
signal drag_started(tile: StackTile, pointer_position: Vector2)
signal drag_moved(pointer_position: Vector2)
signal drag_ended(pointer_position: Vector2)

## Сколько секунд держать палец, чтобы поднять плитку.
const LONG_PRESS_TIME := 0.45
## Если палец сдвинулся дальше этого (в пикселях макета) до срабатывания
## долгого нажатия, значит, пользователь прокручивает список.
const MOVE_TOLERANCE := 24.0

var stack_id := ""

@onready var _name_label: Label = %NameLabel

# Состояние жеста. Это маленький «конечный автомат»: плитка всегда
# находится в одном из трёх состояний.
enum Gesture { NONE, PRESSING, DRAGGING }
var _gesture := Gesture.NONE
var _press_position := Vector2.ZERO
var _press_time := 0.0


func setup(id: String, stack_name: String) -> void:
	stack_id = id
	if not is_node_ready():
		await ready
	_name_label.text = stack_name


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_gesture = Gesture.PRESSING
			_press_position = event.global_position
			_press_time = 0.0
		else:
			_on_release(event.global_position)

	elif event is InputEventMouseMotion and _gesture != Gesture.NONE:
		if _gesture == Gesture.PRESSING:
			if event.global_position.distance_to(_press_position) > MOVE_TOLERANCE:
				_gesture = Gesture.NONE # это прокрутка, а не нажатие
		elif _gesture == Gesture.DRAGGING:
			drag_moved.emit(event.global_position)
			# Событие «съедаем», чтобы список не прокручивался, пока тащим плитку.
			accept_event()


func _process(delta: float) -> void:
	if _gesture != Gesture.PRESSING:
		return
	_press_time += delta
	if _press_time >= LONG_PRESS_TIME:
		_gesture = Gesture.DRAGGING
		drag_started.emit(self, get_global_mouse_position())


func _on_release(pointer_position: Vector2) -> void:
	match _gesture:
		Gesture.PRESSING:
			tapped.emit(stack_id)
		Gesture.DRAGGING:
			drag_ended.emit(pointer_position)
	_gesture = Gesture.NONE


## Плитка-«призрак», которая летает за пальцем во время переноса:
## выглядит так же, но на нажатия не реагирует.
func make_ghost() -> StackTile:
	var ghost: StackTile = load(scene_file_path).instantiate()
	ghost.setup(stack_id, _name_label.text)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.set_process(false)
	return ghost
