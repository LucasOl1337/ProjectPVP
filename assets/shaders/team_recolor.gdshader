shader_type canvas_item;

uniform bool active = false;
uniform vec4 target_color : source_color = vec4(1.0, 0.2, 0.3, 1.0);
uniform float hue_min : hint_range(0.0, 1.0) = 0.45;
uniform float hue_max : hint_range(0.0, 1.0) = 0.75;
uniform float feather : hint_range(0.0, 0.25) = 0.05;
uniform float sat_min : hint_range(0.0, 1.0) = 0.20;
uniform float val_min : hint_range(0.0, 1.0) = 0.15;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

// Função para converter RGB para HSV
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// Função para converter HSV para RGB
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float _hue_weight(float h, float a, float b, float f) {
	float w = 0.0;
	if (a <= b) {
		w = smoothstep(a, a + f, h) * (1.0 - smoothstep(b - f, b, h));
	} else {
		float w1 = smoothstep(a, a + f, h);
		float w2 = 1.0 - smoothstep(b - f, b, h);
		w = max(w1, w2);
	}
	return clamp(w, 0.0, 1.0);
}

void fragment() {
    vec4 current_color = texture(TEXTURE, UV);
    
    if (active && current_color.a > 0.0) {
        vec3 current_hsv = rgb2hsv(current_color.rgb);
        vec3 target_hsv = rgb2hsv(target_color.rgb);

		float w_hue = _hue_weight(current_hsv.x, hue_min, hue_max, feather);
		float w_sat = smoothstep(sat_min, sat_min + 0.10, current_hsv.y);
		float w_val = smoothstep(val_min, val_min + 0.20, current_hsv.z);
		float w = w_hue * w_sat * w_val * intensity;

		if (w > 0.0) {
			vec3 new_hsv = vec3(target_hsv.x, current_hsv.y, current_hsv.z);
			vec3 recolored = hsv2rgb(new_hsv);
			current_color.rgb = mix(current_color.rgb, recolored, clamp(w, 0.0, 1.0));
		}
    }
    
    COLOR = current_color;
}
