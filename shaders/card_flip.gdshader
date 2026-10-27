// Шейдер переворота для всей карточки.
// Он висит на корне карточки, а все её дочерние узлы используют его через
// галочку Use Parent Material — поэтому поворачивается всё сразу.
shader_type canvas_item;

#include "res://shaders/card_flip.gdshaderinc"

void vertex() {
	float q;
	VERTEX = flip_vertex(VERTEX, MODEL_MATRIX, q);
}
