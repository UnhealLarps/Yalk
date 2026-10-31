shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float dots_count = 20.0; 

void fragment() {
    vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
    float aspect = screen_size.x / screen_size.y;
    vec2 uv = UV * vec2(dots_count, dots_count / aspect);
    vec2 repeated_uv = fract(uv);
    float dist = distance(repeated_uv, vec2(0.5));
    float radius = progress * 0.707;
    float dot_alpha = smoothstep(radius, radius - 0.05, dist);
    COLOR = vec4(0.0, 0.0, 0.0, dot_alpha);
}
