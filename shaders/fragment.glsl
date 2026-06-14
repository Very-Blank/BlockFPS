#version 410 core

uniform sampler2D texture_image;

in vec2 texture_coordinate;
out vec4 fragment_color;

void main() {
    fragment_color = texture(texture_image, texture_coordinate);
}
