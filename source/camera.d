module camera;

import gl3n.linalg;
import gl3n.math;

enum DragMode
{
    none,
    rotate,
    pan,
    fastPan
}

struct ArcballCamera
{
    vec3 target = vec3(0, 0, 0);
    float distance = 3.0f;
    quat orientation = quat.identity;

    bool dragging;
    DragMode dragMode = DragMode.none;
    vec2 lastMouse;
    quat dragStartOrientation = quat.identity;
    vec3 dragStartArcballVec = vec3(0, 0, 1);

    float panSpeed = 0.002f;
    float fastPanMultiplier = 4.0f;
    float zoomSpeed = 0.12f;
    float minDistance = 0.05f;
    float maxDistance = 10000.0f;
    float pendingScroll;

    void registerScroll(float wheelDelta)
    {
        pendingScroll += wheelDelta;
    }

    float consumeScrollPending()
    {
        float value = pendingScroll;
        pendingScroll = 0.0f;
        return value;
    }

    void fitToBounds(vec3 minBound, vec3 maxBound, float fovDegrees = 45.0f, float padding = 1.2f)
    {
        target = (minBound + maxBound) * 0.5f;
        auto halfExtent = (maxBound - minBound) * 0.5f;
        float radius = halfExtent.length;  // 中心→コーナーの距離
        if (radius < 1e-4f)
            radius = 1.0f;
        import gl3n.math : PI;
        float halfFovRad = fovDegrees * 0.5f * (PI / 180.0f);
        distance = max(radius / sin(halfFovRad) * padding, 1.0f);
        orientation = quat.identity;
    }

    mat4 viewMatrix() const
    {
        vec3 eyeOffset = orientation * vec3(0, 0, distance);
        vec3 eye = target + eyeOffset;
        vec3 up = orientation * vec3(0, 1, 0);
        return mat4.look_at(eye, target, up);
    }

    mat4 projectionMatrix(float width, float height) const
    {
        return mat4.perspective(width, height, 45.0f, 0.01f, maxDistance * 4.0f);
    }

    /// View matrix for the corner orientation gizmo (rotation only, no pan).
    mat4 gizmoViewMatrix(float eyeDistance = 2.5f) const
    {
        vec3 eye = orientation * vec3(0, 0, eyeDistance);
        vec3 up = orientation * vec3(0, 1, 0);
        return mat4.look_at(eye, vec3(0, 0, 0), up);
    }

    void resetDrag()
    {
        dragging = false;
        dragMode = DragMode.none;
    }

    void beginDrag(DragMode mode, vec2 mousePos, vec2 viewportSize)
    {
        dragging = true;
        dragMode = mode;
        lastMouse = mousePos;
        dragStartOrientation = orientation;

        if (mode == DragMode.rotate)
            dragStartArcballVec = mapToSphere(mousePos, viewportSize);
    }

    void updateDrag(vec2 mousePos, vec2 viewportSize)
    {
        if (!dragging)
            return;

        final switch (dragMode)
        {
        case DragMode.rotate:
            applyArcballRotation(mousePos, viewportSize);
            break;
        case DragMode.pan:
            applyPan(mousePos, 1.0f, viewportSize);
            break;
        case DragMode.fastPan:
            applyPan(mousePos, fastPanMultiplier, viewportSize);
            break;
        case DragMode.none:
            break;
        }

        lastMouse = mousePos;
    }

    void zoom(float wheelDelta)
    {
        if (wheelDelta == 0.0f)
            return;

        float factor = 1.0f - wheelDelta * zoomSpeed;
        distance = clamp(distance * factor, minDistance, maxDistance);
    }

    private void applyArcballRotation(vec2 mousePos, vec2 viewportSize)
    {
        vec3 current = mapToSphere(mousePos, viewportSize);
        vec3 axis = cross(dragStartArcballVec, current);

        if (axis.magnitude < 1e-6f)
            return;

        float dotValue = clamp(dot(dragStartArcballVec, current), -1.0f, 1.0f);
        float angle = acos(dotValue);
        quat delta = quat.axis_rotation(angle, axis.normalized);
        orientation = delta * dragStartOrientation;
        orientation.normalize();
    }

    private void applyPan(vec2 mousePos, float speedMultiplier, vec2 viewportSize)
    {
        vec2 delta = mousePos - lastMouse;
        vec3 right = orientation * vec3(1, 0, 0);
        vec3 up = orientation * vec3(0, 1, 0);
        float scale = distance * panSpeed * speedMultiplier;

        target -= right * (delta.x / viewportSize.x) * scale * viewportSize.x;
        target += up * (delta.y / viewportSize.y) * scale * viewportSize.y;
    }

    private static vec3 mapToSphere(vec2 point, vec2 viewportSize)
    {
        float x = (2.0f * point.x - viewportSize.x) / viewportSize.x;
        float y = (viewportSize.y - 2.0f * point.y) / viewportSize.y;
        float lengthSquared = x * x + y * y;

        if (lengthSquared <= 1.0f)
            return vec3(x, y, sqrt(1.0f - lengthSquared)).normalized;

        float inverseLength = 1.0f / sqrt(lengthSquared);
        return vec3(x * inverseLength, y * inverseLength, 0.0f);
    }
}
