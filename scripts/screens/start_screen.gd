extends Control
## Приветственный экран. Умеет только одно: сообщить, что нажали START.
## Куда переходить дальше, решает Main.

signal start_pressed

@onready var _start_button: IconButton = %StartButton


func _ready() -> void:
	_start_button.pressed.connect(start_pressed.emit)
