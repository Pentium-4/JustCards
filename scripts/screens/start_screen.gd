extends Control
## Приветственный экран. Умеет только одно: сообщить, что нажали START.
## Куда переходить дальше, решает Main.

signal start_pressed

@onready var _start_button: IconButton = %StartButton
@onready var _version_label: Label = %VersionLabel


func _ready() -> void:
	_start_button.pressed.connect(start_pressed.emit)
	# Номер версии хранится в одном месте: Project Settings > Application >
	# Config > Version. Отсюда же его берут сборки для Windows и Android.
	_version_label.text = "v" + str(ProjectSettings.get_setting("application/config/version"))
