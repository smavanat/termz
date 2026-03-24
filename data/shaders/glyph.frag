#version 330 core
in vec2 TexCoords;
out vec4 color;

uniform sampler2D text;
uniform vec4 textColor;
uniform vec4 bgColor;

void main()
{
    float alpha = texture(text, TexCoords).r;
    color = mix(bgColor, textColor, alpha);
}
