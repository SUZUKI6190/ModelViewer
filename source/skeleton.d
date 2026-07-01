module skeleton;

import std.math;

import gl3n.linalg;

import geo_model;

enum MAX_GPU_BONES = 32;
enum minBoneLength = 1e-4f;

void computeBoneFrame(
    ref const(BoneNode) bone,
    out vec3 xAxis,
    out vec3 yAxis,
    out vec3 zAxis)
{
    vec3 delta = bone.tailPos - bone.pos;
    if (delta.length_squared > minBoneLength * minBoneLength)
        yAxis = delta.normalized;
    else
        yAxis = normalizeAxis(bone.yAxis);

    xAxis = normalizeAxis(bone.xAxis);
    xAxis = xAxis - yAxis * dot(xAxis, yAxis);
    if (xAxis.length_squared <= 1e-12f)
    {
        vec3 reference = fabs(yAxis.y) < 0.9f ? vec3(0, 1, 0) : vec3(1, 0, 0);
        xAxis = cross(reference, yAxis);
    }
    xAxis = xAxis.normalized;
    zAxis = cross(xAxis, yAxis).normalized;
}

mat4 boneLocalMatrix(vec3 origin, vec3 xAxis, vec3 yAxis, vec3 zAxis)
{
    mat4 rotation = mat4(
        xAxis.x, yAxis.x, zAxis.x, 0.0f,
        xAxis.y, yAxis.y, zAxis.y, 0.0f,
        xAxis.z, yAxis.z, zAxis.z, 0.0f,
        0.0f, 0.0f, 0.0f, 1.0f,
    );
    return mat4.translation(origin) * rotation;
}

mat4 bindMatrixFromBone(ref const(BoneNode) bone)
{
    vec3 xAxis;
    vec3 yAxis;
    vec3 zAxis;
    computeBoneFrame(bone, xAxis, yAxis, zAxis);
    return boneLocalMatrix(bone.pos, xAxis, yAxis, zAxis);
}

void flattenBindMatrices(const BoneNode[] roots, ref mat4[] bindWorld)
{
    foreach (root; roots)
        flattenBoneBind(root, bindWorld);
}

private void flattenBoneBind(ref const(BoneNode) bone, ref mat4[] bindWorld)
{
    bindWorld ~= bindMatrixFromBone(bone);
    foreach (child; bone.children)
        flattenBoneBind(child, bindWorld);
}

struct SkeletonRuntime
{
    mat4[] bindWorld;
    mat4[] inverseBind;
    mat4[] currentWorld;
    mat4[] skinMatrices;

    @property bool active() const
    {
        return bindWorld.length > 0;
    }

    @property size_t boneCount() const
    {
        return bindWorld.length;
    }

    void build(const Skeleton skeleton)
    {
        bindWorld = null;
        inverseBind = null;
        currentWorld = null;
        skinMatrices = null;

        if (!skeleton.isValid)
            return;

        flattenBindMatrices(skeleton.bones, bindWorld);
        if (bindWorld.length == 0)
            return;

        inverseBind.length = bindWorld.length;
        currentWorld.length = bindWorld.length;
        skinMatrices.length = bindWorld.length;

        foreach (i; 0 .. bindWorld.length)
        {
            inverseBind[i] = bindWorld[i].inverse;
            currentWorld[i] = bindWorld[i];
            skinMatrices[i] = mat4.identity;
        }
    }

    void applyAutoRotation(float angleRadians, size_t boneIndex = 0)
    {
        if (!active || boneIndex >= bindWorld.length)
            return;

        mat4 localRot = mat4.yrotation(angleRadians);
        currentWorld[boneIndex] = bindWorld[boneIndex] * localRot;

        foreach (i; 0 .. bindWorld.length)
        {
            if (i != boneIndex)
                currentWorld[i] = bindWorld[i];
        }

        updateSkinMatrices();
    }

    void updateSkinMatrices()
    {
        if (!active)
            return;

        foreach (i; 0 .. bindWorld.length)
            skinMatrices[i] = currentWorld[i] * inverseBind[i];
    }
}

private vec3 normalizeAxis(vec3 axis)
{
    if (axis.length_squared <= 1e-12f)
        return vec3(0, 1, 0);
    return axis.normalized;
}
