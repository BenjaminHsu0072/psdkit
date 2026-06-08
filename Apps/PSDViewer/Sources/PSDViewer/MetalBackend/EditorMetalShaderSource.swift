import Foundation

enum EditorMetalShaderSource {
    static let library = """
    #include <metal_stdlib>
    using namespace metal;

    struct EditorViewportUniforms {
        float2 canvasSize;
        float2 viewSize;
        float scale;
        float2 translation;
        float2 drawableSize;
    };

    struct LayerCompositeUniforms {
        float2 canvasSize;
        int blendMode;
        float layerOpacity;
        float4 frameRect;
    };

    constant int kBlendNormal = 0;
    constant int kBlendMultiply = 1;
    constant int kBlendAdd = 2;

    inline uint blendChannel(uint src, uint dst, int mode) {
        switch (mode) {
            case kBlendMultiply:
                return (src * dst + 127u) / 255u;
            case kBlendAdd:
                return min(255u, src + dst);
            default:
                return src;
        }
    }

    kernel void compositeLayerKernel(
        texture2d<float, access::read> source [[texture(0)]],
        texture2d<float, access::read_write> destination [[texture(1)]],
        constant LayerCompositeUniforms& uniforms [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        int canvasWidth = int(uniforms.canvasSize.x);
        int canvasHeight = int(uniforms.canvasSize.y);
        if (int(gid.x) >= canvasWidth || int(gid.y) >= canvasHeight) {
            return;
        }

        int frameLeft = int(uniforms.frameRect.x);
        int frameTop = int(uniforms.frameRect.y);
        int frameWidth = int(uniforms.frameRect.z);
        int frameHeight = int(uniforms.frameRect.w);

        int cx = int(gid.x);
        int cy = int(gid.y);
        if (cx < frameLeft || cy < frameTop || cx >= frameLeft + frameWidth || cy >= frameTop + frameHeight) {
            return;
        }

        int layerX = cx - frameLeft;
        int layerY = cy - frameTop;
        if (layerX < 0 || layerY < 0 || layerX >= int(source.get_width()) || layerY >= int(source.get_height())) {
            return;
        }

        float4 srcSample = source.read(uint2(layerX, layerY));
        uint srcR = uint(round(clamp(srcSample.r, 0.0, 1.0) * 255.0));
        uint srcG = uint(round(clamp(srcSample.g, 0.0, 1.0) * 255.0));
        uint srcB = uint(round(clamp(srcSample.b, 0.0, 1.0) * 255.0));
        uint srcA = uint(round(clamp(srcSample.a, 0.0, 1.0) * 255.0));

        float4 dstSample = destination.read(gid);
        uint dstR = uint(round(clamp(dstSample.r, 0.0, 1.0) * 255.0));
        uint dstG = uint(round(clamp(dstSample.g, 0.0, 1.0) * 255.0));
        uint dstB = uint(round(clamp(dstSample.b, 0.0, 1.0) * 255.0));
        uint dstA = uint(round(clamp(dstSample.a, 0.0, 1.0) * 255.0));

        uint layerOpacity = uint(round(clamp(uniforms.layerOpacity, 0.0, 1.0) * 255.0));
        uint effective = srcA * layerOpacity;
        uint inverseEffective = 65025u - effective;

        uint blendedR = blendChannel(srcR, dstR, uniforms.blendMode);
        uint blendedG = blendChannel(srcG, dstG, uniforms.blendMode);
        uint blendedB = blendChannel(srcB, dstB, uniforms.blendMode);

        uint outR = (blendedR * effective + dstR * inverseEffective + 32762u) / 65025u;
        uint outG = (blendedG * effective + dstG * inverseEffective + 32762u) / 65025u;
        uint outB = (blendedB * effective + dstB * inverseEffective + 32762u) / 65025u;
        uint outA = (srcA * layerOpacity * 255u + dstA * inverseEffective + 32762u) / 65025u;

        destination.write(float4(float(outR), float(outG), float(outB), float(outA)) / 255.0, gid);
    }

    struct EditorPreviewVertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex EditorPreviewVertexOut editorPreviewVertex(uint vertexID [[vertex_id]],
                                                      constant EditorViewportUniforms& uniforms [[buffer(0)]]) {
        float2 uvs[6] = {
            float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0),
            float2(1.0, 0.0), float2(1.0, 1.0), float2(0.0, 1.0)
        };

        float2 canvas = uniforms.canvasSize;
        float2 topLeft = uniforms.translation;
        float2 bottomRight = topLeft + canvas * uniforms.scale;

        float2 ndcMin = float2(
            (topLeft.x / uniforms.drawableSize.x) * 2.0 - 1.0,
            1.0 - (bottomRight.y / uniforms.drawableSize.y) * 2.0
        );
        float2 ndcMax = float2(
            (bottomRight.x / uniforms.drawableSize.x) * 2.0 - 1.0,
            1.0 - (topLeft.y / uniforms.drawableSize.y) * 2.0
        );

        float2 uv = uvs[vertexID];
        float2 ndc = mix(ndcMin, ndcMax, uv);

        EditorPreviewVertexOut out;
        out.position = float4(ndc, 0.0, 1.0);
        out.uv = uv;
        return out;
    }

    fragment float4 editorPreviewFragment(EditorPreviewVertexOut in [[stage_in]],
                                          texture2d<float, access::sample> composite [[texture(0)]],
                                          sampler compositeSampler [[sampler(0)]],
                                          constant float& checkerSize [[buffer(0)]]) {
        float4 color = composite.sample(compositeSampler, in.uv);
        float alpha = clamp(color.a, 0.0, 1.0);
        if (alpha >= 0.999) {
            return float4(color.rgb, 1.0);
        }

        float2 pixel = in.uv * float2(composite.get_width(), composite.get_height());
        float tile = max(checkerSize, 1.0);
        bool dark = (int(floor(pixel.x / tile)) + int(floor(pixel.y / tile))) % 2 == 0;
        float3 checker = dark ? float3(0.75, 0.75, 0.75) : float3(1.0, 1.0, 1.0);
        float3 rgb = mix(checker, color.rgb, alpha);
        return float4(rgb, 1.0);
    }

    // MARK: - E4 brush stamp (transient preview textures only)

    struct BrushDabGPU {
        float2 center;
        float radius;
        float dabAlpha;
        float strokeOpacity;
        float4 color;
        float hardness;
        int mode;
    };

    inline float radialMask(float dist, float radius, float hardness) {
        if (radius <= 0.0) return 0.0;
        float t = clamp(dist / radius, 0.0, 1.0);
        float inner = hardness;
        if (t <= inner) return 1.0;
        if (inner >= 1.0) return 0.0;
        return 1.0 - ((t - inner) / (1.0 - inner));
    }

    inline float4 brushSource(float mask, float dabAlpha, float strokeOpacity, float4 color) {
        float a = mask * dabAlpha * strokeOpacity;
        return float4(color.rgb * a, a);
    }

    inline float4 compositeSrcOver(float4 dst, float4 src) {
        return src + dst * (1.0 - src.a);
    }

    inline float4 compositeDestinationOut(float4 dst, float4 src) {
        float factor = 1.0 - src.a;
        return float4(dst.rgb * factor, dst.a * factor);
    }

    kernel void copyTextureKernel(
        texture2d<float, access::read> source [[texture(0)]],
        texture2d<float, access::write> destination [[texture(1)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= source.get_width() || gid.y >= source.get_height()) return;
        destination.write(source.read(gid), gid);
    }

    kernel void stampBrushDabsKernel(
        texture2d<float, access::read_write> target [[texture(0)]],
        constant BrushDabGPU* dabs [[buffer(0)]],
        constant uint& dabCount [[buffer(1)]],
        uint tid [[thread_position_in_grid]]
    ) {
        if (tid >= dabCount) return;

        BrushDabGPU dab = dabs[tid];
        int width = int(target.get_width());
        int height = int(target.get_height());
        int minX = max(0, int(floor(dab.center.x - dab.radius)));
        int minY = max(0, int(floor(dab.center.y - dab.radius)));
        int maxX = min(width - 1, int(ceil(dab.center.x + dab.radius)));
        int maxY = min(height - 1, int(ceil(dab.center.y + dab.radius)));

        for (int y = minY; y <= maxY; ++y) {
            for (int x = minX; x <= maxX; ++x) {
                float2 pixel = float2(float(x) + 0.5, float(y) + 0.5);
                float dist = distance(pixel, dab.center);
                float mask = radialMask(dist, dab.radius, dab.hardness);
                if (mask <= 0.0) continue;

                float4 src = brushSource(mask, dab.dabAlpha, dab.strokeOpacity, dab.color);
                uint2 coord = uint2(x, y);
                float4 dst = target.read(coord);

                float4 outColor;
                switch (dab.mode) {
                    case 0: // isolated brush
                        outColor = compositeSrcOver(dst, src);
                        break;
                    case 1: // isolated eraser
                        outColor = compositeDestinationOut(dst, float4(0.0, 0.0, 0.0, src.a));
                        break;
                    case 2: // composite brush
                        outColor = compositeSrcOver(dst, src);
                        break;
                    default: // composite eraser
                        outColor = compositeDestinationOut(dst, float4(0.0, 0.0, 0.0, src.a));
                        break;
                }
                target.write(outColor, coord);
            }
        }
    }
    """
}
