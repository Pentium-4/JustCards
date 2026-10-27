// Картинка на карточке:
//   - заполняет квадрат целиком, обрезая лишнее (как «заполнить» в галерее);
//   - скруглённые углы;
//   - участвует в перевороте карточки (та же перспектива, что у остальных).
shader_type canvas_item;

#include "res://shaders/card_flip.gdshaderinc"

uniform vec2 rect_size = vec2(726.0);
uniform vec2 texture_size = vec2(1.0);
uniform float corner_radius = 30.0;

// UV, умноженные на коэффициент перспективы. Делим обратно в fragment():
// так текстура остаётся ровной при повороте, а не «ломается» по диагонали.
varying vec3 perspective_uv;

void vertex() {
	float q;
	VERTEX = flip_vertex(VERTEX, MODEL_MATRIX, q);
	perspective_uv = vec3(UV * q, q);
}

void fragment() {
	vec2 uv = perspective_uv.xy / perspective_uv.z;

	// Заполнение с обрезкой
	float rect_aspect = rect_size.x / rect_size.y;
	float tex_aspect = texture_size.x / texture_size.y;
	vec2 tex_uv = uv;
	if (tex_aspect > rect_aspect) {
		tex_uv.x = 0.5 + (uv.x - 0.5) * rect_aspect / tex_aspect;
	} else {
		tex_uv.y = 0.5 + (uv.y - 0.5) * tex_aspect / rect_aspect;
	}
	vec4 color = texture(TEXTURE, tex_uv);

	// Скруглённые углы: расстояние до края скруглённого прямоугольника
	vec2 p = (uv - 0.5) * rect_size;
	vec2 inner = rect_size * 0.5 - vec2(corner_radius);
	float dist = length(max(abs(p) - inner, 0.0)) - corner_radius;
	float aa = max(fwidth(dist), 0.0001);
	color.a *= 1.0 - smoothstep(-aa, aa, dist);

	COLOR = color * COLOR;
}
