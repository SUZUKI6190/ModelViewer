#define CIMGUI_DEFINE_ENUMS_AND_STRUCTS
#include "cimgui.h"

extern "C" {

ImFontAtlas* mv_imgui_font_atlas(void)
{
    return igGetIO()->Fonts;
}

void mv_imgui_io_set_display_size(float width, float height)
{
    ImGuiIO* io = igGetIO();
    io->DisplaySize.x = width;
    io->DisplaySize.y = height;
}

void mv_imgui_io_set_delta_time(float deltaTime)
{
    igGetIO()->DeltaTime = deltaTime;
}

void mv_imgui_io_set_mouse_pos(float x, float y)
{
    ImGuiIO* io = igGetIO();
    io->MousePos.x = x;
    io->MousePos.y = y;
}

void mv_imgui_io_set_mouse_down(int button, int down)
{
    igGetIO()->MouseDown[button] = down;
}

void mv_imgui_io_set_mouse_wheel(float wheelY)
{
    igGetIO()->MouseWheel = wheelY;
}

void mv_imgui_io_set_modifiers(int ctrl, int shift, int alt, int winKey)
{
    ImGuiIO* io = igGetIO();
    io->KeyCtrl = ctrl;
    io->KeyShift = shift;
    io->KeyAlt = alt;
    io->KeySuper = winKey;
}

void mv_imgui_font_set_tex_id(void* texId)
{
    igGetIO()->Fonts->TexID = texId;
}

int mv_imgui_want_capture_mouse(void)
{
    return igGetIO()->WantCaptureMouse ? 1 : 0;
}

float mv_imgui_mouse_wheel(void)
{
    return igGetIO()->MouseWheel;
}

}
