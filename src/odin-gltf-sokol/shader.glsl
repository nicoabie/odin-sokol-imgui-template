/*
    Taken from the GLTF reference viewer:

    https://github.com/KhronosGroup/glTF-Sample-Viewer/tree/master/src/shaders
 */

@header package odin_gltf_sokol
@header import sg "../sokol/gfx"
@header import "core:math/linalg"

@ctype mat4 linalg.Matrix4f32
@ctype vec4 linalg.Vector4f32
@ctype vec3 linalg.Vector3f32
@ctype vec2 linalg.Vector2f32

@vs vs
layout(binding=0) uniform vs_params {
    mat4 model;
    mat4 view_proj;
    vec3 eye_pos;
};

layout(location=0) in vec4 position;
layout(location=1) in vec3 normal;
layout(location=2) in vec2 texcoord;

out vec3 v_pos;
out vec3 v_nrm;
out vec2 v_uv;
out vec3 v_eye_pos;

void main() {
    vec4 pos = model * position;
    v_pos = pos.xyz / pos.w;
    v_nrm = (model * vec4(normal, 0.0)).xyz;
    v_uv = texcoord;
    v_eye_pos = eye_pos;
    gl_Position = view_proj * pos;
}
@end

@fs metallic_fs

in vec3 v_pos;
in vec3 v_nrm;
in vec2 v_uv;
in vec3 v_eye_pos;

out vec4 frag_color;

struct material_info_t {
    float perceptual_roughness;     // roughness value, as authored by the model creator (input to shader)
    vec3 reflectance0;              // full reflectance color (normal incidence angle)
    float alpha_roughness;          // roughness mapped to a more linear change in the roughness (proposed by [2])
    vec3 diffuse_color;             // color contribution from diffuse lighting
    vec3 reflectance90;             // reflectance color at grazing angle
    vec3 specular_color;            // color contribution from specular lighting
    float metallic;
};

layout(binding=1) uniform metallic_params {
    vec4 base_color_factor;
    vec3 emissive_factor;
    float metallic_factor;
    float roughness_factor;
};

layout(binding=2) uniform light_params {
    vec3 light_pos;
    float light_range;
    vec3 light_color;
    float light_intensity;
};

layout(binding=0) uniform texture2D base_color_tex;
layout(binding=1) uniform texture2D metallic_roughness_tex;
layout(binding=2) uniform texture2D normal_tex;
layout(binding=3) uniform texture2D occlusion_tex;
layout(binding=4) uniform texture2D emissive_tex;

layout(binding=0) uniform sampler base_color_smp;
layout(binding=1) uniform sampler metallic_roughness_smp;
layout(binding=2) uniform sampler normal_smp;
layout(binding=3) uniform sampler occlusion_smp;
layout(binding=4) uniform sampler emissive_smp;

vec3 srgb_to_linear(vec3 srgb) {
    bvec3 cutoff = lessThan(srgb, vec3(0.04045));
    vec3 higher = pow((srgb + 0.055) / 1.055, vec3(2.4));
    vec3 lower = srgb / 12.92;
    return mix(higher, lower, cutoff);
}

material_info_t get_material_info() {
    material_info_t mat;
    
    vec4 base_color_tex_color = texture(sampler2D(base_color_tex, base_color_smp), v_uv);
    vec4 base_color = base_color_factor * base_color_tex_color;
    
    float metallic = metallic_factor;
    float perceptual_roughness = roughness_factor;
    
    vec4 mr_tex_color = texture(sampler2D(metallic_roughness_tex, metallic_roughness_smp), v_uv);
    if (metallic_factor < 0.0) {
        metallic = mr_tex_color.b;
    }
    if (roughness_factor < 0.0) {
        perceptual_roughness = mr_tex_color.g;
    }
    
    mat.perceptual_roughness = perceptual_roughness;
    float alpha = base_color.a;
    
    vec3 f0 = vec3(0.04);
    f0 = mix(f0, base_color.rgb, metallic);
    
    mat.reflectance0 = f0;
    mat.alpha_roughness = perceptual_roughness * perceptual_roughness;
    mat.diffuse_color = base_color.rgb * (1.0 - metallic);
    mat.reflectance90 = f0 * 0.45;
    mat.specular_color = f0;
    mat.metallic = metallic;
    
    return mat;
}

float distribution_ggx(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    float nom = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = 3.14159265 * denom * denom;
    return nom / denom;
}

float geometry_schlick_ggx(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;
    float nom = NdotV;
    float denom = NdotV * (1.0 - k) + k;
    return nom / denom;
}

float geometry_smith(vec3 N, vec3 V, vec3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = geometry_schlick_ggx(NdotV, roughness);
    float ggx1 = geometry_schlick_ggx(NdotL, roughness);
    return ggx1 * ggx2;
}

vec3 fresnel_schlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

void main() {
    vec3 N = normalize(v_nrm);
    vec3 V = normalize(v_eye_pos - v_pos);
    
    vec3 normal_tex_color = texture(sampler2D(normal_tex, normal_smp), v_uv).rgb;
    if (length(normal_tex_color) > 0.0) {
        N = normal_tex_color * 2.0 - 1.0;
        N = normalize(N);
    }
    
    float occlusion = 1.0;
    vec3 occlusion_tex_color = texture(sampler2D(occlusion_tex, occlusion_smp), v_uv).rgb;
    if (length(occlusion_tex_color) > 0.0) {
        occlusion = occlusion_tex_color.r;
    }
    
    material_info_t mat = get_material_info();
    
    vec3 L = normalize(light_pos - v_pos);
    vec3 H = normalize(V + L);
    float distance = length(light_pos - v_pos);
    float attenuation = 1.0 / (distance * distance);
    vec3 radiance = light_color * light_intensity * attenuation;
    
    float NdotL = max(dot(N, L), 0.0);
    
    float D = distribution_ggx(N, H, mat.alpha_roughness);
    float G = geometry_smith(N, V, L, mat.alpha_roughness);
    vec3 F = fresnel_schlick(max(dot(H, V), 0.0), mat.reflectance0);
    
    vec3 numerator = D * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * NdotL + 0.0001;
    vec3 specular = numerator / denominator;
    
    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - mat.metallic;
    
    vec3 Lo = (kD * mat.diffuse_color / 3.14159265 + specular) * radiance * NdotL;
    
    vec3 emissive = vec3(0.0);
    vec3 emissive_tex_color = texture(sampler2D(emissive_tex, emissive_smp), v_uv).rgb;
    if (length(emissive_tex_color) > 0.0 || length(emissive_factor) > 0.0) {
        emissive = srgb_to_linear(emissive_tex_color).rgb * emissive_factor;
    }
    
    vec3 ambient = vec3(0.03) * mat.diffuse_color * occlusion;
    vec3 color = ambient + Lo + emissive;
    
    color = color / (color + vec3(1.0));
    color = pow(color, vec3(1.0 / 2.2));
    
    frag_color = vec4(color, 1.0);
}
@end

@program metallic vs metallic_fs
