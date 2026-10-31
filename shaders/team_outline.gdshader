shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);

void fragment() {
	vec4 center_texel = texture(TEXTURE, UV);
	float center_brightness = max(max(center_texel.r, center_texel.g), center_texel.b);
	float center_shape = center_texel.a * step(0.08, center_brightness);
	float surrounding_shape = 0.0;

	for (int x = -4; x <= 4; x++) {
		for (int y = -4; y <= 4; y++) {
			if (x == 0 && y == 0) {
				continue;
			}

			if (x * x + y * y > 16) {
				continue;
			}

			vec2 offset = TEXTURE_PIXEL_SIZE * vec2(float(x), float(y));
			vec4 texel = texture(TEXTURE, UV + offset);
			float brightness = max(max(texel.r, texel.g), texel.b);
			float shape = texel.a * step(0.08, brightness);

			surrounding_shape = max(surrounding_shape, shape);
		}
	}

	float edge = surrounding_shape * (1.0 - center_shape);
	COLOR = vec4(outline_color.rgb, outline_color.a * edge);
}
