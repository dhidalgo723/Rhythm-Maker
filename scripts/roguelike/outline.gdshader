shader_type canvas_item;

// Contorno alrededor de la silueta de una imagen con transparencia: los
// pixeles transparentes que tienen alguno opaco a menos de `width` se pintan
// con `outline_color`. La tienda lo usa negro en reposo y blanco al
// seleccionar. La textura necesita `width` pixeles de margen transparente
// alrededor, o el contorno se cortaria en los bordes (RogueArt lo anade).

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float width = 3.0;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	if (color.a < 0.5) {
		float near = 0.0;
		// 16 direcciones: suficiente para que el borde salga redondo.
		for (int i = 0; i < 16; i++) {
			float angle = float(i) * 6.2831853 / 16.0;
			vec2 offset = vec2(cos(angle), sin(angle)) * width * TEXTURE_PIXEL_SIZE;
			near = max(near, texture(TEXTURE, UV + offset).a);
		}
		color = near > 0.5 ? outline_color : vec4(0.0);
	}
	COLOR = color;
}
