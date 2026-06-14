#version 410 core

layout(location = 0) in vec3 in_vertex_position;
layout(location = 2) in vec2 in_texture_coordinate;

uniform mat4 view;
uniform mat4 projection;
uniform mat4 model;

out vec2 texture_coordinate;

void main() {
    texture_coordinate = in_texture_coordinate;
    gl_Position = projection * view * model * vec4(in_vertex_position, 1.0);
}
