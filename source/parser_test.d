module parser_test;

import std.stdio;
import geo_parser;

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
    }
}
