module parser_test;

import std.algorithm : min;
import std.array : Appender;
import std.format;
import std.stdio;

import geo_model;
import geo_parser;
import skinning;

void main(string[] args)
{
    auto path = args.length > 1 ? args[1] : "data/cube.geo.xml";
    auto model = parseGeoFile(path);
    writeln("file=", path);
    writeln("name=", model.name);
    writeln("vertices=", model.vertexCount);
    writeln("triangles=", model.triangleCount);
    writeln("triangle_batches=", model.triangles.length);
    writeln("line_batches=", model.lineBatchCount);

    foreach (i, batch; model.triangles)
    {
        writeln("triangle_batch[", i, "].skeleton.name=", batch.skeleton.name);
        writeln("triangle_batch[", i, "].skeleton.count=", batch.skeleton.count);
        writeln("triangle_batch[", i, "].skeleton.boneCount=", batch.skeleton.boneCount);
        writeln("triangle_batch[", i, "].vertexGroups=", batch.vertexGroups.length);
        if (batch.skeleton.bones.length > 0)
            writeln("triangle_batch[", i, "].rootBone[0]=", batch.skeleton.bones[0].name);

        logSkinning(i, batch);
    }
}

private void logSkinning(size_t batchIndex, const TriangleBatch batch)
{
    if (!batch.skeleton.isValid)
    {
        writeln("triangle_batch[", batchIndex, "].skinning=skipped (no skeleton)");
        return;
    }

    auto skinning = buildSkinningData(batch);
    writeln("triangle_batch[", batchIndex, "].skinning.bones=", skinning.bones.length);
    writeln("triangle_batch[", batchIndex, "].skinning.vertices=", skinning.vertices.length);
    writeln("triangle_batch[", batchIndex, "].skinning.influenced=", skinning.influencedVertices);
    writeln("triangle_batch[", batchIndex, "].skinning.unweighted=", skinning.unweightedVertices);
    writeln("triangle_batch[", batchIndex, "].skinning.multiInfluence=", skinning.multiInfluenceVertices);
    writeln("triangle_batch[", batchIndex, "].skinning.truncated=", skinning.truncatedVertices);
    writeln("triangle_batch[", batchIndex, "].skinning.maxRawInfluences=", skinning.maxRawInfluences);

    if (skinning.mismatchPairBones > 0)
        writeln("WARN triangle_batch[", batchIndex, "].skinning.mismatchPairBones=", skinning.mismatchPairBones);
    if (skinning.outOfRangeIndices > 0)
        writeln("WARN triangle_batch[", batchIndex, "].skinning.outOfRangeIndices=", skinning.outOfRangeIndices);

    if (skinning.bones.length != batch.skeleton.boneCount)
    {
        writeln("WARN triangle_batch[", batchIndex, "].skinning.boneCountMismatch flat=",
            skinning.bones.length, " tree=", batch.skeleton.boneCount);
    }

    logBonePairStats(batchIndex, batch, skinning);
    logSampleVertices(batchIndex, skinning);

    if (batch.vertexGroups.length > 0)
        logVertexGroupCheck(batchIndex, batch, skinning);
}

private void logBonePairStats(size_t batchIndex, const TriangleBatch batch, const SkinningData skinning)
{
    size_t boneIndex = 0;
    size_t totalPairs;

    void walkBone(ref const(BoneNode) bone)
    {
        const pairCount = min(bone.weights.length, bone.targetIndices.length);
        totalPairs += pairCount;
        writeln("triangle_batch[", batchIndex, "].bone[", boneIndex, "] ", bone.name,
            " pairs=", pairCount);
        boneIndex++;
        foreach (child; bone.children)
            walkBone(child);
    }

    foreach (bone; batch.skeleton.bones)
        walkBone(bone);

    writeln("triangle_batch[", batchIndex, "].skinning.totalPairs=", totalPairs);
}

private void logSampleVertices(size_t batchIndex, const SkinningData skinning)
{
    if (skinning.vertices.length == 0)
        return;

    size_t[] samples;
    samples ~= 0;
    if (skinning.vertices.length > 1)
        samples ~= 1;
    if (skinning.vertices.length > 42)
        samples ~= 42;

    size_t bestMulti = size_t.max;
    size_t bestCount = 0;
    foreach (vi, skin; skinning.vertices)
    {
        const count = skin.influenceCount;
        if (count > bestCount)
        {
            bestCount = count;
            bestMulti = vi;
        }
    }
    if (bestCount > 1 && bestMulti < skinning.vertices.length)
        samples ~= bestMulti;

    foreach (vi; samples)
        writeln("triangle_batch[", batchIndex, "].vertex[", vi, "] ", formatVertexSkin(skinning, vi));
}

private string formatVertexSkin(const SkinningData skinning, size_t vertexIndex)
{
    auto skin = skinning.vertices[vertexIndex];
    if (!skin.hasWeights)
        return "bones=[] sum=0";

    Appender!string builder;
    builder.put("bones=[");
    bool first = true;
    foreach (i; 0 .. MAX_BONE_INFLUENCES)
    {
        if (skin.boneIds[i] < 0 || skin.weights[i] <= 0)
            continue;

        if (!first)
            builder.put(", ");
        first = false;

        string boneName = skin.boneIds[i] < skinning.bones.length
            ? skinning.bones[skin.boneIds[i]].name
            : "?";
        builder.put(format("%s:%d:%s", boneName, skin.boneIds[i], format("%.3f", skin.weights[i])));
    }
    builder.put(format("] sum=%s", format("%.3f", skin.weightSum)));
    return builder.data;
}

private void logVertexGroupCheck(size_t batchIndex, const TriangleBatch batch, const SkinningData skinning)
{
    auto check = checkVertexGroups(batch, skinning);
    writeln("triangle_batch[", batchIndex, "].vertexGroupCheck.groups=", check.groupsChecked);
    if (check.missingBone > 0)
        writeln("WARN triangle_batch[", batchIndex, "].vertexGroupCheck.missingBone=", check.missingBone);
    if (check.indexOutOfRange > 0)
        writeln("WARN triangle_batch[", batchIndex, "].vertexGroupCheck.indexOutOfRange=", check.indexOutOfRange);
    if (check.weightMismatch > 0)
        writeln("WARN triangle_batch[", batchIndex, "].vertexGroupCheck.weightMismatch=", check.weightMismatch);
    else if (check.groupsChecked > 0)
        writeln("triangle_batch[", batchIndex, "].vertexGroupCheck.ok");
}
