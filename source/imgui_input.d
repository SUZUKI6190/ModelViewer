module imgui_input;

import bindbc.glfw;
import imgui_helper;

private float g_scrollY;

extern(C) void imgui_scroll_callback(GLFWwindow*, double, double yoffset) nothrow @nogc
{
    g_scrollY += cast(float)yoffset;
}

void installImGuiInput(GLFWwindow* window)
{
    g_scrollY = 0.0f;
    glfwSetScrollCallback(window, &imgui_scroll_callback);
}

float consumeGlfwScroll()
{
    float value = g_scrollY;
    g_scrollY = 0.0f;
    return value;
}

void imguiNewFrameFromGlfw(GLFWwindow* window, float width, float height, float deltaTime)
{
    mv_imgui_io_set_display_size(width, height);
    mv_imgui_io_set_delta_time(deltaTime);

    double mouseX;
    double mouseY;
    glfwGetCursorPos(window, &mouseX, &mouseY);
    mv_imgui_io_set_mouse_pos(cast(float)mouseX, cast(float)mouseY);

    mv_imgui_io_set_mouse_down(0, glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_LEFT) == GLFW_PRESS);
    mv_imgui_io_set_mouse_down(1, glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_RIGHT) == GLFW_PRESS);
    mv_imgui_io_set_mouse_down(2, glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_MIDDLE) == GLFW_PRESS);

    mv_imgui_io_set_mouse_wheel(g_scrollY);
    // Scroll is forwarded to the camera after ImGui processes the frame.

    int ctrl = glfwGetKey(window, GLFW_KEY_LEFT_CONTROL) == GLFW_PRESS
        || glfwGetKey(window, GLFW_KEY_RIGHT_CONTROL) == GLFW_PRESS;
    int shift = glfwGetKey(window, GLFW_KEY_LEFT_SHIFT) == GLFW_PRESS
        || glfwGetKey(window, GLFW_KEY_RIGHT_SHIFT) == GLFW_PRESS;
    int alt = glfwGetKey(window, GLFW_KEY_LEFT_ALT) == GLFW_PRESS
        || glfwGetKey(window, GLFW_KEY_RIGHT_ALT) == GLFW_PRESS;
    int winKey = glfwGetKey(window, GLFW_KEY_LEFT_SUPER) == GLFW_PRESS
        || glfwGetKey(window, GLFW_KEY_RIGHT_SUPER) == GLFW_PRESS;
    mv_imgui_io_set_modifiers(ctrl, shift, alt, winKey);
}
