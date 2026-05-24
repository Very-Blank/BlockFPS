#version 410 core

uniform vec3 debug_color;

out vec4 fragment_color;

void main() {
    fragment_color = vec4(debug_color, 1.0);
}
