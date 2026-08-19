shader_type canvas_item;

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;


void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	vec3 flashed = mix(pixel.rgb, vec3(1.0), flash_amount);
	COLOR = vec4(flashed, pixel.a) * COLOR;
}
