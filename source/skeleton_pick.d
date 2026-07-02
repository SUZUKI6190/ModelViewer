module skeleton_pick;

import std.algorithm : clamp, max;
import std.math;

import gl3n.linalg;

import camera;
import skeleton;

enum pickRadiusFactor = 0.10f;
enum pickMinRadius = 0.02f;
enum pickRadiusTolerance = 1.5f;

void buildPickRay(
    vec2 mousePos,
    vec2 viewportSize,
    ref const(ArcballCamera) camera,
    mat4 viewMatrix,
    mat4 projectionMatrix,
    out vec3 rayOrigin,
    out vec3 rayDir)
{
    vec3 eyeOffset = camera.orientation * vec3(0, 0, camera.distance);
    rayOrigin = camera.target + eyeOffset;

    const float ndcX = (2.0f * mousePos.x / viewportSize.x) - 1.0f;
    const float ndcY = 1.0f - (2.0f * mousePos.y / viewportSize.y);
    vec4 rayClip = vec4(ndcX, ndcY, -1.0f, 1.0f);

    mat4 invProj = projectionMatrix.inverse;
    mat4 invView = viewMatrix.inverse;
    vec4 rayEye = invProj * rayClip;
    rayEye = vec4(rayEye.x, rayEye.y, -1.0f, 0.0f);
    rayDir = (invView * rayEye).xyz.normalized;
}

bool rayCapsuleIntersect(
    vec3 rayOrigin,
    vec3 rayDir,
    vec3 capA,
    vec3 capB,
    float radius,
    out float hitDistance)
{
    vec3 axis = capB - capA;
    const float axisLenSq = dot(axis, axis);

    if (axisLenSq <= 1e-12f)
    {
        vec3 oc = rayOrigin - capA;
        const float b = dot(oc, rayDir);
        const float c = dot(oc, oc) - radius * radius;
        const float disc = b * b - c;
        if (disc < 0.0f)
            return false;
        hitDistance = max(0.0f, -b - sqrt(disc));
        return true;
    }

    vec3 w = rayOrigin - capA;
    const float d = axisLenSq;
    const float e = dot(axis, rayDir);
    const float f = dot(rayDir, rayDir);
    const float g = dot(axis, w);
    const float h = dot(rayDir, w);
    const float denom = d * f - e * e;

    float sc;
    float tc;
    if (fabs(denom) < 1e-12f)
    {
        sc = 0.0f;
        tc = g / d;
    }
    else
    {
        sc = (e * g - h * d) / denom;
        tc = (e * h - g * f) / denom;
    }

    sc = max(0.0f, sc);
    tc = clamp(tc, 0.0f, 1.0f);

    vec3 pointOnRay = rayOrigin + rayDir * sc;
    vec3 pointOnSeg = capA + axis * tc;
    const float distSq = (pointOnRay - pointOnSeg).length_squared;
    if (distSq > radius * radius)
        return false;

    hitDistance = sc;
    return true;
}

private vec3 transformPoint(mat4 transform, vec3 point)
{
    vec4 result = transform * vec4(point, 1.0f);
    return vec3(result.x, result.y, result.z);
}

private float pickRadiusForLength(float length)
{
    float radius = length > minBoneLength
        ? max(length * pickRadiusFactor, pickMinRadius)
        : pickMinRadius;
    return radius * pickRadiusTolerance;
}

int pickBoneAtScreen(
    vec2 mousePos,
    vec2 viewportSize,
    ref const(ArcballCamera) camera,
    mat4 viewMatrix,
    mat4 projectionMatrix,
    ref const(SkeletonRuntime) runtime,
    bool usePosedMatrices)
{
    if (!runtime.active || runtime.boneLength.length == 0)
        return -1;

    vec3 rayOrigin;
    vec3 rayDir;
    buildPickRay(mousePos, viewportSize, camera, viewMatrix, projectionMatrix, rayOrigin, rayDir);

    const mat4[] worldMatrices = usePosedMatrices ? runtime.currentWorld : runtime.bindWorld;

    int bestBone = -1;
    float bestDistance = float.max;

    foreach (i; 0 .. runtime.boneCount)
    {
        if (i >= worldMatrices.length || i >= runtime.boneLength.length)
            continue;

        const float length = runtime.boneLength[i];
        const mat4 boneMatrix = worldMatrices[i];
        const vec3 capA = transformPoint(boneMatrix, vec3(0, 0, 0));
        const vec3 capB = transformPoint(boneMatrix, vec3(0, length, 0));
        const float radius = pickRadiusForLength(length);

        float hitDistance;
        if (!rayCapsuleIntersect(rayOrigin, rayDir, capA, capB, radius, hitDistance))
            continue;

        if (hitDistance < bestDistance)
        {
            bestDistance = hitDistance;
            bestBone = cast(int)i;
        }
    }

    return bestBone;
}
