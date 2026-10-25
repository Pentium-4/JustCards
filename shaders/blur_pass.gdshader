// Один проход размытия по Гауссу: берёт то, что уже нарисовано на экране
// под этим прямоугольником, и размывает в одном направлении.
// Полное размытие = два прохода: горизонтальный, потом вертикальный
// (так быстрее, чем размывать сразу во все стороны). Смотри blur_overlay.tscn.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
// Направление прохода: (1, 0) — по горизонтали, (0, 1) — по вертикали.
uniform vec2 direction = vec2(1.0, 0.0);
// Радиус размытия в пикселях макета (ширина макета = 1125).
uniform float radius : hint_range(0.0, 120.0) = 0.0;
// Цвет, которым слегка затемняется фон, и его сила.
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 0.0);

const int TAPS = 16; // сколько выборок в каждую сторону

void fragment() {
	// Переводим радиус из пикселей макета в доли экрана, чтобы размытие
	// выглядело одинаково и в маленьком окне на ПК, и на телефоне.
	vec2 design_px = vec2(1.0, SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x) / 1125.0;
	vec2 step_uv = direction * design_px * radius / float(TAPS);

	vec3 color = texture(screen_texture, SCREEN_UV).rgb;
	float total = 1.0;
	for (int i = 1; i <= TAPS; i++) {
		float t = float(i) / float(TAPS);
		float w = exp(-4.0 * t * t); // вес по Гауссу: дальние пиксели влияют меньше
		color += texture(screen_texture, SCREEN_UV + step_uv * float(i)).rgb * w;
		color += texture(screen_texture, SCREEN_UV - step_uv * float(i)).rgb * w;
		total += 2.0 * w;
	}
	color /= total;
	color = mix(color, tint.rgb, tint.a);
	COLOR = vec4(color, 1.0);
}
