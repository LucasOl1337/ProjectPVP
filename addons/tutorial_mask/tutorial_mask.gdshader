shader_type canvas_item;

// 外部可调节参数
uniform vec2 screen_size = vec2(1920.0, 1080.0); // 当前屏幕大小（自动适配）
uniform vec2 target_pos = vec2(0.0, 0.0); // 透明区域起点坐标（屏幕空间）
uniform vec2 target_size = vec2(100.0, 100.0); // 透明区域宽高
uniform float alpha_strength: hint_range(0.0, 1.0) = 0.0; // 透明强度（0完全透明，1不透明）

void fragment() {
    vec4 original_color = COLOR;

    vec2 screen_uv = UV * screen_size;

    // 区域判断（仅修改目标区域的透明度，其他完全保留）
    bool in_target_area =
        screen_uv.x >= target_pos.x &&
        screen_uv.x <= target_pos.x + target_size.x &&
        screen_uv.y >= target_pos.y &&
        screen_uv.y <= target_pos.y + target_size.y;

    // 仅修改目标区域的 alpha，RGB 完全保留原图
    if (in_target_area) {
        original_color.a = alpha_strength;
    }

    // 最终输出：严格使用采样后的原图颜色
    COLOR = original_color;
}