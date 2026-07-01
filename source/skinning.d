module skinning;

import std.algorithm : max, min, sort;

import geo_model;

enum MAX_BONE_INFLUENCES = 4;

struct VertexSkinData
{
    int[MAX_BONE_INFLUENCES] boneIds = [-1, -1, -1, -1];
    float[MAX_BONE_INFLUENCES] weights = [0, 0, 0, 0];

    @property bool hasWeights() const
    {
        return boneIds[0] >= 0 && weights[0] > 0;
    }

    @property float weightSum() const
    {
        float sum = 0;
        foreach (w; weights)
            sum += w;
        return sum;
    }

    @property size_t influenceCount() const
    {
        size_t count;
        foreach (i; 0 .. MAX_BONE_INFLUENCES)
        {
            if (boneIds[i] >= 0 && weights[i] > 0)
                count++;
        }
        return count;
    }
}

struct FlatBone
{
    string name;
}

struct SkinningData
{
    FlatBone[] bones;
    VertexSkinData[] vertices;
    size_t mismatchPairBones;
    size_t outOfRangeIndices;
    size_t influencedVertices;
    size_t unweightedVertices;
    size_t multiInfluenceVertices;
    size_t truncatedVertices;
    size_t maxRawInfluences;
}

private struct Influence
{
    int boneId;
    float weight;
}

void flattenBones(const BoneNode[] roots, ref FlatBone[] bones)
{
    foreach (root; roots)
        flattenBone(root, bones);
}

private void flattenBone(ref const(BoneNode) bone, ref FlatBone[] bones)
{
    bones ~= FlatBone(bone.name);
    foreach (child; bone.children)
        flattenBone(child, bones);
}

SkinningData buildSkinningData(const TriangleBatch batch)
{
    SkinningData result;
    flattenBones(batch.skeleton.bones, result.bones);

    const vertexCount = batch.vertexCount;
    result.vertices.length = vertexCount;

    Influence[][] rawInfluences;
    rawInfluences.length = vertexCount;

    void walkBone(ref const(BoneNode) bone, ref size_t boneIndex)
    {
        if (bone.weights.length != bone.targetIndices.length)
            result.mismatchPairBones++;

        if (bone.weights.length == bone.targetIndices.length)
        {
            foreach (i; 0 .. bone.weights.length)
            {
                if (bone.weights[i] <= 0)
                    continue;

                const vi = bone.targetIndices[i];
                if (vi >= vertexCount)
                {
                    result.outOfRangeIndices++;
                    continue;
                }

                rawInfluences[vi] ~= Influence(cast(int)boneIndex, bone.weights[i]);
            }
        }

        boneIndex++;
        foreach (child; bone.children)
            walkBone(child, boneIndex);
    }

    size_t boneIndex = 0;
    foreach (bone; batch.skeleton.bones)
        walkBone(bone, boneIndex);

    foreach (vi; 0 .. vertexCount)
    {
        if (rawInfluences[vi].length == 0)
            continue;

        result.maxRawInfluences = max(result.maxRawInfluences, rawInfluences[vi].length);
        finalizeVertex(result.vertices[vi], rawInfluences[vi], result);
    }

    result.unweightedVertices = vertexCount - result.influencedVertices;
    return result;
}

private void finalizeVertex(ref VertexSkinData skin, Influence[] influences, ref SkinningData stats)
{
    Influence[] merged = mergeInfluences(influences);
    if (merged.length == 0)
        return;

    float sum = 0;
    foreach (inf; merged)
        sum += inf.weight;
    if (sum <= 0)
        return;

    sort!((a, b) => a.weight > b.weight)(merged);

    stats.influencedVertices++;
    if (merged.length > 1)
        stats.multiInfluenceVertices++;
    if (merged.length > MAX_BONE_INFLUENCES)
        stats.truncatedVertices++;

    const n = min(merged.length, MAX_BONE_INFLUENCES);
    float topSum = 0;
    foreach (i; 0 .. n)
        topSum += merged[i].weight;

    foreach (i; 0 .. n)
    {
        skin.boneIds[i] = merged[i].boneId;
        skin.weights[i] = merged[i].weight / topSum;
    }
}

private Influence[] mergeInfluences(Influence[] influences)
{
    if (influences.length <= 1)
        return influences;

    Influence[] merged;
    merged.reserve(influences.length);

    foreach (inf; influences)
    {
        bool found;
        foreach (ref existing; merged)
        {
            if (existing.boneId != inf.boneId)
                continue;
            existing.weight += inf.weight;
            found = true;
            break;
        }
        if (!found)
            merged ~= inf;
    }

    return merged;
}

int findBoneIndex(const SkinningData data, string boneName)
{
    foreach (i, bone; data.bones)
    {
        if (bone.name == boneName)
            return cast(int)i;
    }
    return -1;
}

struct VertexGroupCheckResult
{
    size_t groupsChecked;
    size_t missingBone;
    size_t indexOutOfRange;
    size_t weightMismatch;
}

VertexGroupCheckResult checkVertexGroups(const TriangleBatch batch, const SkinningData skinning)
{
    VertexGroupCheckResult result;

    foreach (group; batch.vertexGroups)
    {
        result.groupsChecked++;
        const boneId = findBoneIndex(skinning, group.name);
        if (boneId < 0)
        {
            result.missingBone++;
            continue;
        }

        foreach (vi; group.indices)
        {
            if (vi >= skinning.vertices.length)
            {
                result.indexOutOfRange++;
                continue;
            }

            auto skin = skinning.vertices[vi];
            bool matched;
            foreach (i; 0 .. MAX_BONE_INFLUENCES)
            {
                if (skin.boneIds[i] == boneId && skin.weights[i] > 0)
                {
                    matched = true;
                    break;
                }
            }
            if (!matched)
                result.weightMismatch++;
        }
    }

    return result;
}
