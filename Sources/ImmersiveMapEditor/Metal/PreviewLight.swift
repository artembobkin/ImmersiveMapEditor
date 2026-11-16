import Foundation
import Metal
import TileKit
import simd

/// The one light of the editor's 3D previews, of a tile and of a landmark
/// alone: a sun from one side with its shadow, over an even ambient light.
/// It is fixed, with nothing to set, and it is the editor's alone: a tile
/// carries no light, and the engine lights the models itself (the user,
/// 2026-11-16: no lighting settings in the editor, just something that
/// looks nice in its preview; before, a light map baked on the GPU with a
/// panel of modifiers).
enum PreviewLight {
    /// Toward the sun in the views' axes (X east, Y up, Z south): from the
    /// bearing the palette takes the sun from, 45° up.
    static let sun: SIMD3<Float> = {
        let bearing = Double(Palette.sunFrom) * .pi / 180, height = 45.0 * .pi / 180
        return SIMD3(Float(sin(bearing) * cos(height)), Float(sin(height)), Float(-cos(bearing) * cos(height)))
    }()
    /// How dark a surface is where it stands fully in the sun's shadow.
    static let shadowStrength: Float = 0.45
    /// The shadow map's side in texels.
    static let shadowSize = 4096

    /// The sun's look at a scene, for its shadow map: orthographic along
    /// the sun's rays over a ball of `radius` around `centre`, `room` times
    /// as wide, for the shadows the scene casts on the ground around it.
    static func sunMatrix(centre: SIMD3<Float>, radius: Float, room: Float = 2.2) -> simd_float4x4 {
        let eye = centre + sun * (radius * 2)
        let forward = -sun
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        let view = simd_float4x4(rows: [SIMD4(right.x, right.y, right.z, -simd_dot(right, eye)),
                                        SIMD4(up.x, up.y, up.z, -simd_dot(up, eye)),
                                        SIMD4(-forward.x, -forward.y, -forward.z, simd_dot(forward, eye)),
                                        SIMD4(0, 0, 0, 1)])
        let extent = radius * room, near: Float = 0.1, far = radius * 4.5
        let ortho = simd_float4x4(rows: [SIMD4(1 / extent, 0, 0, 0), SIMD4(0, 1 / extent, 0, 0),
                                         SIMD4(0, 0, -1 / (far - near), -near / (far - near)), SIMD4(0, 0, 0, 1)])
        return ortho * view
    }

    /// The shadow map both previews draw the sun's depth into.
    static func makeShadowMap(_ device: MTLDevice) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: shadowSize, height: shadowSize,
                                                         mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        return device.makeTexture(descriptor: d)
    }

    /// The sampler a shadow map is compared through.
    static func makeShadowSampler(_ device: MTLDevice) -> MTLSamplerState? {
        let d = MTLSamplerDescriptor()
        d.minFilter = .linear
        d.magFilter = .linear
        d.compareFunction = .lessEqual
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: d)
    }

    /// The light in Metal's shading language, for the shaders of both
    /// previews: how much of the sun reaches a point (`previewSunlit`, from
    /// its place in the sun's look and the shadow map) and a colour under
    /// the light (`previewLit`).
    static let shader = """
    // How much of the sun reaches a point: 1 in the open, 0 in shadow.
    // `inSun` is the point in the sun's look, `facing` its normal against
    // the sun's direction, `texel` one texel of the shadow map.
    static float previewSunlit(depth2d<float> shadow, sampler compare, float4 inSun, float facing, float texel) {
        float2 st = inSun.xy * float2(0.5, -0.5) + 0.5;
        if (st.x < 0 || st.x > 1 || st.y < 0 || st.y > 1) return 1;
        // A surface turned from the sun is in its own shadow whole.
        if (facing <= 0.02) return 0;
        float z = inSun.z - 0.0004;
        float lit = 0;
        for (int dx = -1; dx <= 1; dx++) for (int dy = -1; dy <= 1; dy++)
            lit += shadow.sample_compare(compare, st + float2(dx, dy) * texel, z);
        return lit / 9;
    }

    // A colour under the light: an even ambient light, a little more from
    // above, the sun on what faces it, and the sun's shadow, which takes
    // `strength` of the light and tints what is left cool.
    static float3 previewLit(float3 colour, float3 n, float3 sun, float sunlit, float strength) {
        float facing = max(dot(n, sun), 0.0);
        float light = 0.74 + 0.26 * facing + 0.05 * n.y;
        float3 dark = mix(float3(1), float3(0.88, 0.92, 1.0), saturate(strength * 2)) * (1 - strength);
        return colour * light * mix(float3(1), dark, 1 - sunlit);
    }

    """
}
