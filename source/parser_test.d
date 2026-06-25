module parser_test;

import std.stdio;
import geo_parser;

void main()
{
    auto model = parseGeoFile("data/cube.geo.xml");
    writeln("name=", model.name);
    writeln("vertices=", model.vertexCount);
    writeln("triangles=", model.triangleCount);
    writeln("triangle_batches=", model.triangles.length);
    writeln("line_batches=", model.lineBatchCount);
}
