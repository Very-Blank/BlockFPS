#version 410 core

layout(location = 0) in vec3 vertex_position;

uniform mat4 view;
uniform mat4 projection;
uniform mat4 model;

out vec3 vertex_color;

void main() {
    vertex_color = (normalize(vertex_position) + vec3(1.0)) / 2.0;
    gl_Position = projection * view * model * vec4(vertex_position, 1.0);
}
