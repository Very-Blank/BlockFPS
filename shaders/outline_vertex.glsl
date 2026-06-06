#version 410 core

layout(location = 0) in vec3 vertex_position;
layout(location = 1) in vec3 vertex_normal;

uniform vec3 scale;
uniform mat4 view;
uniform mat4 projection;
uniform mat4 model;

void main() {
    float thickness = 0.1;
    gl_Position = projection * view * model * vec4(vertex_position * (vec3(1 + thickness / scale.x, 1 + thickness / scale.y, 1 + thickness / scale.z)), 1.0);
}
