shader_type canvas_item;

uniform sampler2D damage_mask;
uniform int damage_channel = 0;


float get_damage(vec4 mask) {
	if (damage_channel == 0) {
		return mask.r;
	}

	if (damage_channel == 1) {
		return mask.g;
	}

	return mask.b;
}


void fragment() {
	vec4 texture_color = texture(TEXTURE, UV);
	vec4 mask = texture(damage_mask, UV);

	float damage = get_damage(mask);

	COLOR = texture_color;
	COLOR.a *= 1.0 - damage;
}
