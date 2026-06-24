module imgui_helper;

import bindbc.imgui.bind.imgui : ImFontAtlas;

extern (C) {
    ImFontAtlas* mv_imgui_font_atlas();
    void mv_imgui_io_set_display_size(float width, float height);
    void mv_imgui_io_set_delta_time(float deltaTime);
    void mv_imgui_io_set_mouse_pos(float x, float y);
    void mv_imgui_io_set_mouse_down(int button, int down);
    void mv_imgui_io_set_mouse_wheel(float wheelY);
    void mv_imgui_io_set_modifiers(int ctrl, int shift, int alt, int winKey);
    void mv_imgui_font_set_tex_id(void* texId);
    int mv_imgui_want_capture_mouse();
    float mv_imgui_mouse_wheel();
}
