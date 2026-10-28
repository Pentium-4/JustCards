# Just Cards — веб-версия (для айфона)

Эта папка — сайт на GitHub Pages. Здесь обычные HTML/CSS/JavaScript, без Godot:
приложение весит ~0,5 МБ и открывается мгновенно. Godot-проект (папка выше)
остаётся для Windows и Android. Формат данных и резервной копии у них общий.

Как устроено (по аналогии с Godot-проектом):

| Файл | Что делает | Аналог в Godot |
|---|---|---|
| `js/main.js` | какой экран показать | `scripts/main.gd` |
| `js/data.js` | данные, сохранение, резервная копия | `autoload/app_data.gd` |
| `js/platform.js` | файлы телефона: копия, выбор фото | `backup_io.gd`, `image_picker.gd` |
| `js/ui.js` | кнопки, слои, масштаб | `icon_button.gd`, `base_popup.gd` |
| `js/gesture.js` | «нажал — подержал — потащил» | `long_press_gesture.gd` |
| `js/popups.js` | создание стака, «REMOVE?» | `scenes/popups/` |
| `js/screens/*.js` | экраны | `scenes/screens/` |
| `style.css` | цвета (в начале файла) и стили | `theme/main_theme.tres` |

Новая версия: поменяй номер в `js/version.js` и `CACHE_NAME` в
`index.service.worker.js`, потом Commit и Push.

Godot больше не экспортирует веб-версию в эту папку (путь экспорта Web
теперь `../build/web`), чтобы случайно не затереть сайт.
