// Общая часть шейдеров переворота карточки.
// Подключается через #include в card_flip.gdshader и card_image.gdshader.
//
// Идея: интерфейс в Godot плоский, у него нет настоящего 3D. Поэтому мы
// сами считаем, куда попадёт каждая вершина, если повернуть карточку
// вокруг вертикальной оси и посмотреть на неё через «камеру».
// Ближний край становится больше, дальний меньше — получается перспектива.

// Центр карточки в координатах экрана (вокруг него вращаем).
uniform vec2 flip_pivot = vec2(0.0);
// Угол поворота в радианах. 0 = карточка смотрит прямо на нас.
uniform float flip_angle = 0.0;
// Расстояние до «камеры» в пикселях макета. Меньше = сильнее перспектива.
uniform float flip_distance = 3200.0;

// Возвращает новую позицию вершины. В q записывается коэффициент
// перспективы — он нужен, чтобы картинка не искажалась (см. card_image).
vec2 flip_vertex(vec2 vertex, mat4 model, out float q) {
	vec2 world = (model * vec4(vertex, 0.0, 1.0)).xy;
	vec2 p = world - flip_pivot;
	float z = p.x * sin(flip_angle); // насколько точка приблизилась к нам
	q = flip_distance / (flip_distance - z);
	vec2 projected = flip_pivot + vec2(p.x * cos(flip_angle), p.y) * q;
	return (inverse(model) * vec4(projected, 0.0, 1.0)).xy;
}
