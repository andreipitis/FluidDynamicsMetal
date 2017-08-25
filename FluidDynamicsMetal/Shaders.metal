//
//  Shaders.metal
//  FluidDynamicsMetal
//
//  Created by Andrei-Sergiu Pițiș on 02/08/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 textureCoorinates [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 textureCoorinates;
};

//Render to screen
vertex VertexOut vertexShader(constant VertexIn* vertexArray [[buffer(0)]], unsigned int vid [[vertex_id]]) {

    VertexIn vertexData = vertexArray[vid];
    VertexOut vertexDataOut;
    vertexDataOut.position = float4(vertexData.position.x, vertexData.position.y, 0.0, 1.0);
    vertexDataOut.textureCoorinates = vertexData.textureCoorinates.xy;
    return vertexDataOut;
}

fragment half4 visualizeScalar(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> tex2d [[texture(0)]]) {
    constexpr sampler sampler2d(filter::nearest);

    half4 color = half4(tex2d.sample(sampler2d, fragmentIn.textureCoorinates));

    return half4(half3(0.0, 0.06, 0.19) * abs(color.xxx), 1.0);
}

fragment half4 visualizeVector(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> tex2d [[texture(0)]]) {
    constexpr sampler sampler2d(filter::nearest);

    half4 color = half4(tex2d.sample(sampler2d, fragmentIn.textureCoorinates));

    return half4(half4(0.5) + 0.5 * color);
}

//Fluid Dynamics Render Encoder

struct BufferData {
    float2 position;
    float2 impulse;

    float2 impulseScalar;
    float2 offsets;

    float2 screenSize;
};

inline float2 bilerpFrag(sampler textureSampler, texture2d<float> texture, float2 p, float2 screenSize) {
    float4 ij; // i0, j0, i1, j1
    ij.xy = floor(p - 0.5) + 0.5;
    ij.zw = ij.xy + 1.0;

    float4 uv = ij / screenSize.xyxy;
    float2 d11 = texture.sample(textureSampler, uv.xy).xy;
    float2 d21 = texture.sample(textureSampler, uv.zy).xy;
    float2 d12 = texture.sample(textureSampler, uv.xw).xy;
    float2 d22 = texture.sample(textureSampler, uv.zw).xy;

    float2 a = p - ij.xy;

    return mix(mix(d11, d21, a.x), mix(d12, d22, a.x), a.y);
}

inline half gauss(half2 p, half r)
{
    return exp(-dot(p, p) / r);
}

fragment half2 applyForceVector(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> input [[texture(0)]], constant BufferData &bufferData [[buffer(0)]]) {
    constexpr sampler fluid_sampler(filter::nearest);

    half2 impulse = half2(bufferData.impulse);
    half2 location = half2(bufferData.position);
    half2 screenSize = half2(bufferData.screenSize);

    half2 color = half2(input.sample(fluid_sampler, fragmentIn.textureCoorinates).xy);

    half2 coords = location - half2(fragmentIn.textureCoorinates).xy * screenSize;
    half2 splat = impulse * gauss(coords, 150.0);

    half2 final = splat + color;
    return final;
}

fragment half2 applyForceScalar(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> input [[texture(0)]], constant BufferData &bufferData [[buffer(0)]]) {
    constexpr sampler fluid_sampler(filter::nearest);

    half2 impulseScalar = half2(bufferData.impulseScalar);
    half2 location = half2(bufferData.position);
    half2 screenSize = half2(bufferData.screenSize);

    half2 color = half2(input.sample(fluid_sampler, fragmentIn.textureCoorinates).xy);

    half2 coords = location - half2(fragmentIn.textureCoorinates).xy * screenSize;
    half2 splat = impulseScalar * gauss(coords, 150.0);

    half2 final = splat + color;
    return final;
}

fragment half2 advect(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> velocity [[texture(0)]], texture2d<float, access::sample> advected [[texture(1)]], constant BufferData &bufferData [[buffer(0)]]) {

    constexpr sampler fluid_sampler(filter::nearest);

    float2 screenSize = bufferData.screenSize;

    float2 uv = (fragmentIn.textureCoorinates * screenSize) - velocity.sample(fluid_sampler, fragmentIn.textureCoorinates).xy;

    half2 color = 0.998h * half2(bilerpFrag(fluid_sampler, advected, uv, screenSize));

    return color.xy;
}

fragment half2 divergence(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> velocity [[texture(0)]], constant BufferData &bufferData [[buffer(0)]]) {

    constexpr sampler fluid_sampler(filter::nearest);

    float2 uv = fragmentIn.textureCoorinates;

    float2 offsets = bufferData.offsets;

    float2 xOffset = float2(offsets.x, 0.0);
    float2 yOffset = float2(0.0, offsets.y);

    float vl = velocity.sample(fluid_sampler, uv - xOffset).x;
    float vr = velocity.sample(fluid_sampler, uv + xOffset).x;
    float vb = velocity.sample(fluid_sampler, uv - yOffset).y;
    float vt = velocity.sample(fluid_sampler, uv + yOffset).y;

    float scale = 0.5;
    float divergence = scale * (vr - vl + vt - vb);

    return half2(divergence, 0.0);
}

fragment half2 jacobi(VertexOut fragmentIn [[stage_in]], texture2d<half, access::sample> x [[texture(0)]], texture2d<half, access::sample> b [[texture(1)]], constant BufferData &bufferData [[buffer(0)]]) {

    constexpr sampler fluid_sampler(filter::nearest);

    float2 uv = fragmentIn.textureCoorinates;

    float2 offsets = bufferData.offsets;

    float2 xOffset = float2(offsets.x, 0.0);
    float2 yOffset = float2(0.0, offsets.y);

    half xl = x.sample(fluid_sampler, uv - xOffset).x;
    half xr = x.sample(fluid_sampler, uv + xOffset).x;
    half xb = x.sample(fluid_sampler, uv - yOffset).x;
    half xt = x.sample(fluid_sampler, uv + yOffset).x;

    half bc = b.sample(fluid_sampler, uv).x;

    half alpha = -1;
    half beta = 4;

    half result = (xl + xr + xb + xt + alpha * bc) / beta;

    return half2(result, 0.0);
}

fragment half2 vorticity(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> velocity [[texture(0)]], constant BufferData &bufferData [[buffer(0)]]) {

    constexpr sampler fluid_sampler(filter::nearest);

    float2 uv = fragmentIn.textureCoorinates;

    float2 offsets = bufferData.offsets;

    float2 xOffset = float2(offsets.x, 0.0);
    float2 yOffset = float2(0.0, offsets.y);

    float vl = velocity.sample(fluid_sampler, uv - xOffset).y;
    float vr = velocity.sample(fluid_sampler, uv + xOffset).y;
    float vb = velocity.sample(fluid_sampler, uv - yOffset).x;
    float vt = velocity.sample(fluid_sampler, uv + yOffset).x;

    float scale = 0.5;

    return half2(scale * ((vr - vl) - (vt - vb)), 0.0);
}

fragment half2 vorticityConfinement(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> velocity [[texture(0)]], texture2d<float, access::sample> vorticity [[texture(1)]], constant BufferData &bufferData [[buffer(0)]]) {

    constexpr sampler fluid_sampler(filter::nearest);

    float2 screenSize = bufferData.screenSize;

    float2 uv = fragmentIn.textureCoorinates;

    float2 offsets = bufferData.offsets;

    float2 xOffset = float2(offsets.x, 0.0);
    float2 yOffset = float2(0.0, offsets.y);

    float vl = vorticity.sample(fluid_sampler, uv - xOffset).x;
    float vr = vorticity.sample(fluid_sampler, uv + xOffset).x;
    float vb = vorticity.sample(fluid_sampler, uv - yOffset).x;
    float vt = vorticity.sample(fluid_sampler, uv + yOffset).x;
    float vc = vorticity.sample(fluid_sampler, uv).x;

    float scale = 0.5;

    float timestep = 1.0;
    float epsilon = 2.4414e-4;
    float2 curl = float2(0.4, 0.4);


    float2 force = scale * float2(abs(vt) - abs(vb), abs(vr) - abs(vl));
    float lengthSquared = max(epsilon, dot(force, force));
    force *= rsqrt(lengthSquared) * curl * vc;
    force.y *= -1.0;

    float2 velc = velocity.sample(fluid_sampler, uv).xy;
    float2 result = velc + (timestep * force);

    //Boundary
    float2 gridValue = uv * screenSize;
    if(gridValue.x <= 1 || gridValue.y <= 1 || gridValue.x >= screenSize.x - 1 || gridValue.y >= screenSize.y - 1) {
        result = float2(0.0);

//        float2 texCoord = gridValue;
//        if(gridValue.x <= 1) {
//            texCoord.x = gridValue.x + 1;
//        }
//
//        if(gridValue.y <= 1) {
//            texCoord.y = gridValue.y + 1;
//        }
//
//        if(gridValue.x >= screenSize.x - 1) {
//            texCoord.x = gridValue.x - 1;
//        }
//
//        if(gridValue.y >= screenSize.y - 1) {
//            texCoord.y = gridValue.y - 1;
//        }
//
//        result = -velocity.sample(fluid_sampler, texCoord / screenSize).xy;
    }

    return half2(result.x, result.y);
}

fragment half2 gradient(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> p [[texture(0)]], texture2d<float, access::sample> w [[texture(1)]], constant BufferData &bufferData [[buffer(0)]]) {

    constexpr sampler fluid_sampler(filter::nearest);

    float2 screenSize = bufferData.screenSize;

    float2 uv = fragmentIn.textureCoorinates;

    float2 offsets = bufferData.offsets;

    float2 xOffset = float2(offsets.x, 0.0);
    float2 yOffset = float2(0.0, offsets.y);

    float pl = p.sample(fluid_sampler, uv - xOffset).x;
    float pr = p.sample(fluid_sampler, uv + xOffset).x;
    float pb = p.sample(fluid_sampler, uv - yOffset).x;
    float pt = p.sample(fluid_sampler, uv + yOffset).x;

    float scale = 0.5;

    float2 gradient = scale * float2(pr - pl, pt - pb);

    float2 wc = w.sample(fluid_sampler, uv).xy;

    float2 result = wc - gradient;

    //Boundary
    float2 gridValue = uv * screenSize;

    if(gridValue.x <= 1 || gridValue.y <= 1 || gridValue.x >= screenSize.x - 1 || gridValue.y >= screenSize.y - 1) {
        result = float2(0.0);
//        float2 texCoord = gridValue;
//        if(gridValue.x <= 1) {
//            texCoord.x = gridValue.x + 1;
//        }
//
//        if(gridValue.y <= 1) {
//            texCoord.y = gridValue.y + 1;
//        }
//
//        if(gridValue.x >= screenSize.x - 1) {
//            texCoord.x = gridValue.x - 1;
//        }
//
//        if(gridValue.y >= screenSize.y - 1) {
//            texCoord.y = gridValue.y - 1;
//        }
//
//        result = -w.sample(fluid_sampler, texCoord / screenSize).xy;
    }
    return half2(result.x, result.y);
}



















////////////////////////////////////////////////////////////////////////////////////////////////////////
//Fluid Dynamics Compute Encoder------------------------------------------------------------------------
////////////////////////////////////////////////////////////////////////////////////////////////////////
//Compute Fluid

struct ComputeBufferData {
    float2 position;
    float2 impulse;

    float2 impulseScalar;

    float2 screenSize;
};

inline float SqDistPointSegment(float2 a, float2 b, float2 c)
{
    float2 ab = b - a;
    float2 ac = c - a;
    float2 bc = c - b;
    float e = dot(ac, ab);
    // handle if c is projected to the outside of the ab
    if (e <= 0.0f)
        return dot(ac, ac);

    float f = dot(ab, ab);
    if (e >= f)
        return dot(bc, bc);

    // handle if c is projected onto the ab
    return dot(ac, ac) - e * e / f;
}

inline float2 bilerp(sampler textureSampler, texture2d<float> texture, float2 p) {
    float4 ij; // i0, j0, i1, j1
    ij.xy = floor(p - 0.5) + 0.5;
    ij.zw = ceil(p + 1.5);//ij.xy + 3.0;

    float4 uv = ij;// / gridSize.xyxy;
    float2 d11 = texture.sample(textureSampler, uv.xy).xy;
    float2 d21 = texture.sample(textureSampler, uv.zy).xy;
    float2 d12 = texture.sample(textureSampler, uv.xw).xy;
    float2 d22 = texture.sample(textureSampler, uv.zw).xy;

    float2 a = p - ij.xy;

    return mix(mix(d11, d21, a.x), mix(d12, d22, a.x), a.y);
}

kernel void visualize(texture2d<float, access::sample> velocity [[texture(0)]], texture2d<float, access::sample> advected [[texture(1)]], texture2d<float, access::write> output [[texture(2)]], uint2 gid [[thread_position_in_grid]], constant ComputeBufferData &bufferData [[buffer(0)]]) {
    float2 gidf = static_cast<float2>(gid);

    constexpr sampler fluid_sampler(coord::pixel, filter::nearest, address::clamp_to_edge);
    //    constexpr sampler normalized_sampler(filter::nearest, address::clamp_to_edge);

    if (gid.x > output.get_width() - 1 || gid.y > output.get_height() - 1) {
        return;
    }

    //Advection

    float2 uv = floor(gidf - 0.5 * 0.5 * velocity.sample(fluid_sampler, gidf).xy);

    float2 color = 0.998 * bilerp(fluid_sampler, advected, uv);

    //External Forces
    float2 impulse = bufferData.impulse;

    float2 location = bufferData.position;
    float dist = sqrt(SqDistPointSegment(location, location, gidf));
    float2 pos = impulse * (1.0f - smoothstep(5.0f, 15.0f, dist));

    //Combination
    float3 value = float3(pos + color, 0.0);


    //Boundary
    float boundaryVal = 0;
    if(gid.x <= boundaryVal || gid.y <= boundaryVal || gid.x >= bufferData.screenSize.x - boundaryVal || gid.y >= bufferData.screenSize.y - boundaryVal) {
        value = float3(0.0);
    }

    output.write(float4(value.x, value.y, value.z, 1.0), gid);
}
