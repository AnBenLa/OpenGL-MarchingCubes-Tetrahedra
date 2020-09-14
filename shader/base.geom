#version 430
layout (points) in;
layout (triangle_strip, max_vertices = 16) out;

out fData
{
    vec3 position;
    vec3 normal;
    vec4 color;
}frag;

layout(binding=0) uniform sampler3D volume;
layout(binding=1) uniform isampler2D edgeTable;
layout(binding=2) uniform isampler2D triTable;

uniform vec3 volume_dimensions;
uniform float iso_value;
uniform float voxel_size;
// 1 if marching cubes, 2 if marching tetrahedra
uniform int mode;

uniform mat4 view;
uniform mat4 projection;
uniform mat4 model;

vec4[8] corner = {
vec4(0, 0, 1, 0),
vec4(1, 0, 1, 0),
vec4(1, 0, 0, 0),
vec4(0, 0, 0, 0),

vec4(0, 1, 1, 0),
vec4(1, 1, 1, 0),
vec4(1, 1, 0, 0),
vec4(0, 1, 0, 0) };

// here the 6 different tetrahedrons are defined
// i.e. the tetrahedra between the cube vertices 3,0,7,6
// i.e. the tetrahedra betweem the cube vertices 7,0,4,6
int tetrahedrons[6][4] = {
{ 3, 0, 7, 6 },
{ 4, 0, 7, 6 },
{ 0, 4, 5, 6 },
{ 5, 6, 1, 0 },
{ 0, 1, 2, 6 },
{ 0, 3, 2, 6 }
};

// given the id of an edge as defined in https://gyazo.com/8ccbba2864de78ed5195693652b6867b find the vertices that create the edge
// i.e. the edge with id 0 is between the vertices 0 and 3 of the current tetrahedra
// i.e. the edge with id 1 is between the vertices 0 and 1 of the current tetrahedra
int tetrahedra_edge_vertex_mapping[6][2] = {
{ 0, 3 },
{ 0, 1 },
{ 0, 2 },
{ 1, 2 },
{ 1, 3 },
{ 2, 3 }
};

// here the edges that create a triangle for the current tetrahedra configuration are specified
// i.e. the configuration with id 1 produces 1 triangle using the edges 0,2,1
int tetrahedra_triangle_map[16][6] = {
{ -1, -1, -1, -1, -1, -1 },
{ 0, 2, 1, -1, -1, -1 },
{ 1, 4, 3, -1, -1, -1 },
{ 4, 0, 2, 4, 2, 3 },
{ 2, 3, 5, -1, -1, -1 },
{ 0, 1, 5, 1, 5, 3 },
{ 1, 2, 5, 1, 5, 4 },
{ 4, 5, 0, -1, -1, -1 },
{ 4, 5, 0, -1, -1, -1 },
{ 1, 2, 5, 1, 5, 4 },
{ 0, 1, 5, 1, 5, 3 },
{ 2, 3, 5, -1, -1, -1 },
{ 4, 0, 2, 4, 2, 3 },
{ 1, 4, 3, -1, -1, -1 },
{ 0, 2, 1, -1, -1, -1 },
{ -1, -1, -1, -1, -1, -1 }
};

// defines which corners make the edge determined by the first index
int edge_vertex_mapping[12][2] = {
{ 0, 1 },
{ 1, 2 },
{ 2, 3 },
{ 0, 3 },
{ 4, 5 },
{ 5, 6 },
{ 6, 7 },
{ 4, 7 },
{ 0, 4 },
{ 1, 5 },
{ 2, 6 },
{ 3, 7 }
};

// has to be done since the texture coordinates are between 0,0,0 and 1,1,1
vec3 texture_position(vec4 position){
    return position.xyz/volume_dimensions;
}

float sample_volume(vec4 position){
    return texture(volume, texture_position(position)).a;
}

vec4 interpolate_vertex(float iso_value, vec4 a, vec4 b, float value_a, float value_b){
    return vec4((a + (iso_value - value_a)*(b - a)/(value_b - value_a)).xyz, 1);
}

void marching_cubes(){
    float[8] corner_sample;
    mat4 mvp = projection * view * model;
    int cube_index = 0;

    int k = 1;

    // sample the volume at each corner and store the result in the corner sample array
    // compute the index of the cube that will define which triangles will be generated
    // this works already
    for (int i = 0; i < 8; i++){
        corner_sample[i] = sample_volume(gl_in[0].gl_Position + corner[i]);
        if (corner_sample[i] < iso_value) cube_index |= k;
        // do a bit shift in order to multiply with 2 faster
        k = k << 1;
    }

    // working!
    int cut_edges = texelFetch(edgeTable, ivec2(cube_index, 0), 0).r;

    vec4[12] vertices;
    k = 1;

    //in case the whole cube is outside the volume
    if (cut_edges == 0)
    return;

    // for all possible vertices that could be generated calculate the new interpolated vertex position if the vertex will be used
    for (int i = 0; i < 12; ++i){
        if ((cut_edges & k) == k){
            int a_index = edge_vertex_mapping[i][0];
            int b_index = edge_vertex_mapping[i][1];
            vec4 a = gl_in[0].gl_Position + corner[a_index];
            vec4 b = gl_in[0].gl_Position + corner[b_index];
            float value_a = corner_sample[a_index];
            float value_b = corner_sample[b_index];
            vertices[i] = interpolate_vertex(iso_value, a, b, value_a, value_b);
        }
        k = k << 1;
    }

    // chech which vertices will form a triangle by looking up in the triangle table
    // generate the triangles
    for (int i = 0; texelFetch(triTable, ivec2(i, cube_index), 0).r != -1; i += 3){
        vec4 vert_a = vertices[texelFetch(triTable, ivec2(i, cube_index), 0).r];
        vec4 vert_b = vertices[texelFetch(triTable, ivec2(i+1, cube_index), 0).r];
        vec4 vert_c = vertices[texelFetch(triTable, ivec2(i+2, cube_index), 0).r];

        vec3 a = vert_a.xyz - vert_b.xyz;
        vec3 b = vert_c.xyz - vert_b.xyz;
        frag.normal = normalize(cross(a, b));

        gl_Position = mvp * vert_a;
        frag.position = gl_Position.xyz;
        frag.color = vec4(1.0, 0, 0, 1.0);
        EmitVertex();

        gl_Position = mvp * vert_b;
        frag.position = gl_Position.xyz;
        frag.color = vec4(1.0, 0.0, 0, 1.0);
        EmitVertex();

        gl_Position = mvp * vert_c;
        frag.position = gl_Position.xyz;
        frag.color = vec4(1, 0, 0.0, 1.0);
        EmitVertex();
        EndPrimitive();
    }
}

void marching_tetracubes(){
    float[8] corner_sample;
    mat4 mvp = projection * view * model;
    int cube_index = 0;

    // store the corner values to avoid recomputation
    for (int i = 0; i < 8; i++){
        corner_sample[i] = sample_volume(gl_in[0].gl_Position + corner[i]);
    }

    // for each tetrahedron
    for (int i = 0; i < 6; ++i){
        cube_index = 0;
        int k = 1;
        // check all 4 corners of the current tetrahedron
        for (int j = 0; j < 4; ++j){
            if (corner_sample[tetrahedrons[i][j]] < iso_value) cube_index |= k;
            k = k << 1;
        }

        // for the current tetrahedra configuration look up the edges that create a triangle
        for (int k = 0; tetrahedra_triangle_map[cube_index][k] != -1 && k < 6; k += 3){

            // the edges are indexed according to the image here: https://gyazo.com/8ccbba2864de78ed5195693652b6867b
            // the triangle table was created using this scheme
            // i.e. for configuration 1 or 0001 the edges 1,2 abd 0 create a triangle
            // the edge 1 is between vertices 0 and 1 of the current tetrahedra
            // the edge 2 is between vertices 0 and 2 of the current tetrahedra
            // the edge 0 is between vertices 0 and 3 of the current tetrahedra
            int edge_0 = tetrahedra_triangle_map[cube_index][k];
            int edge_1 = tetrahedra_triangle_map[cube_index][k + 1];
            int edge_2 = tetrahedra_triangle_map[cube_index][k + 2];

            // here the vertex indices of the current tetrahedra for the edge_0 are selected
            // the information for this is stored in tetrahedra_edge_vertex_mapping
            // the edge 0 i.e. is between the vertices 0 and 3 of the tetrahedra
            // the edge 1 i.e. is between the vertices 0 and 1 of the tetrahedra
            int edge_0_vertex_a_index = tetrahedra_edge_vertex_mapping[edge_0][0];
            int edge_0_vertex_b_index = tetrahedra_edge_vertex_mapping[edge_0][1];

            // here the actual index inside the cube is looked up
            // i.e. the vertex with index 0 in the tetrahedra with index 0 corresponds to the vertex with id 3 in the cube
            int edge_0_vertex_a_actual_index = tetrahedrons[i][edge_0_vertex_a_index];
            int edge_0_vertex_b_actual_index = tetrahedrons[i][edge_0_vertex_b_index];

            // the position of the edge vertices is then being computed
            vec4 vertex_edge_0_a = gl_in[0].gl_Position + corner[edge_0_vertex_a_actual_index];
            vec4 vertex_edge_0_b = gl_in[0].gl_Position + corner[edge_0_vertex_b_actual_index];

            // the iso-values of the vertices is the looked up
            float vertex_edge_0_a_value = corner_sample[edge_0_vertex_a_actual_index];
            float vertex_edge_0_b_value = corner_sample[edge_0_vertex_b_actual_index];

            vec4 vert_a = interpolate_vertex(iso_value, vertex_edge_0_a, vertex_edge_0_b, vertex_edge_0_a_value, vertex_edge_0_b_value);
            // here the vertex position is assumed to be just the midpoint between the vertex a and b
            vert_a = (vertex_edge_0_a + vertex_edge_0_b) / 2.0f;

            vec4 vertex_edge_1_a = gl_in[0].gl_Position + corner[tetrahedrons[i][tetrahedra_edge_vertex_mapping[edge_1][0]]];
            vec4 vertex_edge_1_b = gl_in[0].gl_Position + corner[tetrahedrons[i][tetrahedra_edge_vertex_mapping[edge_1][1]]];

            float vertex_edge_1_a_value = corner_sample[tetrahedrons[i][tetrahedra_edge_vertex_mapping[edge_1][0]]];
            float vertex_edge_1_b_value = corner_sample[tetrahedrons[i][tetrahedra_edge_vertex_mapping[edge_1][1]]];

            vec4 vert_b = interpolate_vertex(iso_value, vertex_edge_1_a, vertex_edge_1_b, vertex_edge_1_a_value, vertex_edge_1_b_value);
            vert_b = (vertex_edge_1_a + vertex_edge_1_b) / 2.0f;

            vec4 vertex_edge_2_a = gl_in[0].gl_Position + corner[tetrahedrons[i][tetrahedra_edge_vertex_mapping[edge_2][0]]];
            vec4 vertex_edge_2_b = gl_in[0].gl_Position + corner[tetrahedrons[i][tetrahedra_edge_vertex_mapping[edge_2][1]]];

            float vertex_edge_2_a_value = corner_sample[tetrahedrons[i][tetrahedra_edge_vertex_mapping[edge_2][0]]];
            float vertex_edge_2_b_value = corner_sample[tetrahedrons[i][tetrahedra_edge_vertex_mapping[edge_2][1]]];

            vec4 vert_c = interpolate_vertex(iso_value, vertex_edge_2_a, vertex_edge_2_b, vertex_edge_2_a_value, vertex_edge_2_b_value);
            vert_c = (vertex_edge_2_a + vertex_edge_2_b) / 2.0f;

            vec3 a = vert_a.xyz - vert_b.xyz;
            vec3 b = vert_c.xyz - vert_b.xyz;
            frag.normal = normalize(cross(a, b));

            gl_Position = mvp * vert_a;
            frag.position = gl_Position.xyz;

            // if the edge is not correct the vertex will be green instead of red
            if ((vertex_edge_0_a_value < iso_value && vertex_edge_0_b_value < iso_value) ||
            vertex_edge_0_a_value > iso_value && vertex_edge_0_b_value > iso_value){
                frag.color = vec4(0, 1.0, 0, 1.0);
            } else {
                frag.color = vec4(1.0, 0, 0, 1.0);
            }
            frag.color = model * vert_a;
            EmitVertex();

            gl_Position = mvp * vert_b;
            frag.position = gl_Position.xyz;

            // if the edge is not correct the vertex will be green instead of red
            if ((vertex_edge_1_a_value < iso_value && vertex_edge_1_b_value < iso_value) ||
            vertex_edge_1_a_value > iso_value && vertex_edge_1_b_value > iso_value){
                frag.color = vec4(0, 1.0, 0, 1.0);
            } else {
                frag.color = vec4(1.0, 0, 0, 1.0);
            }
            frag.color = model * vert_b;
            EmitVertex();

            gl_Position = mvp * vert_c;
            frag.position = gl_Position.xyz;

            // if the edge is not correct the vertex will be green instead of red
            if ((vertex_edge_2_a_value < iso_value && vertex_edge_2_b_value < iso_value) ||
            vertex_edge_2_a_value > iso_value && vertex_edge_2_b_value > iso_value){
                frag.color = vec4(0, 1.0, 0, 1.0);
            } else {
                frag.color = vec4(1.0, 0, 0, 1.0);
            }
            frag.color = model * vert_c;
            EmitVertex();
            EndPrimitive();
        }

    }
}

void main() {
    // scale the voxels according to the voxel size
    for (int i = 0; i < 8; ++i)
    corner[i] = voxel_size * corner[i];

    if (mode == 1)
    marching_cubes();
    else if (mode == 2)
    marching_tetracubes();
}