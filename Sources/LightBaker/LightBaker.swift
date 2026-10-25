import Foundation
import Metal

/// The light map's bake, on the GPU with Metal ray tracing: the tile seen
/// from straight above, every surface white, lit by the sky, light bouncing
/// between surfaces.
///
/// In: every triangle's corners, x y z (Z up), nine floats a triangle, in
/// local metres. Out: size x size floats, row 0 on the north, each the light
/// leaving the topmost surface over that texel (a white diffuse surface: the
/// light reaching it). The sky is even all round, a little brighter toward
/// the zenith, no sun: the engine casts the sun's shadows.
public enum LightBaker {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    static let shader = """
    #include <metal_stdlib>
    #include <metal_raytracing>
    using namespace metal;
    using namespace raytracing;

    struct Params {
        float x0, y0, x1, y1;
        uint size, samples, bounces, row0, seed;
        float top;
    };

    // The sky: brightness by the height of the direction, as the bake's world
    // had it (a map range of Z from -0.1..1 to 0.55..1.15, clamped).
    static float sky(float3 d) {
        return mix(0.55, 1.15, clamp((d.z + 0.1) / 1.1, 0.0, 1.0));
    }

    static uint hash(uint x) {
        x ^= x >> 16; x *= 0x7feb352d; x ^= x >> 15; x *= 0x846ca68b; x ^= x >> 16;
        return x;
    }

    static float rnd(thread uint& s) {
        s = hash(s);
        return float(s) / 4294967296.0;
    }

    static float3 cosine(float3 n, thread uint& s) {
        float a = 2 * M_PI_F * rnd(s), r = sqrt(rnd(s));
        float3 t = abs(n.z) < 0.9 ? normalize(cross(n, float3(0, 0, 1))) : normalize(cross(n, float3(1, 0, 0)));
        float3 b = cross(n, t);
        return normalize(t * (r * cos(a)) + b * (r * sin(a)) + n * sqrt(max(0.0, 1 - r * r)));
    }

    kernel void bake(uint2 gid [[thread_position_in_grid]],
                     constant Params& p [[buffer(0)]],
                     primitive_acceleration_structure accel [[buffer(1)]],
                     const device packed_float3* v [[buffer(2)]],
                     device float* out [[buffer(3)]]) {
        uint row = gid.y + p.row0;
        if (gid.x >= p.size || row >= p.size) return;
        float w = (p.x1 - p.x0) / p.size, h = (p.y1 - p.y0) / p.size;
        intersector<triangle_data> hit;
        hit.assume_geometry_type(geometry_type::triangle);
        hit.force_opacity(forced_opacity::opaque);
        uint s = hash(gid.x * 9781 + row * 6271 + p.seed * 26699);
        float total = 0;
        for (uint k = 0; k < p.samples; k++) {
            // A camera ray straight down, through a random point of the texel.
            ray r;
            r.origin = float3(p.x0 + (gid.x + rnd(s)) * w, p.y1 - (row + rnd(s)) * h, p.top);
            r.direction = float3(0, 0, -1);
            r.min_distance = 0;
            r.max_distance = 1e7;
            // White and diffuse: every bounce passes all of its light on, so a
            // path brings the sky it ends in.
            float light = 0;
            for (uint b = 0; b <= p.bounces + 1; b++) {
                auto i = hit.intersect(r, accel);
                if (i.type == intersection_type::none) {
                    light = sky(r.direction);
                    break;
                }
                if (b == p.bounces + 1) break;
                uint t = i.primitive_id * 3;
                float3 a = float3(v[t]), e1 = float3(v[t + 1]) - a, e2 = float3(v[t + 2]) - a;
                float3 n = normalize(cross(e1, e2));
                // Both sides of a face are white: it faces the ray that met it.
                if (dot(n, r.direction) > 0) n = -n;
                float3 at = r.origin + r.direction * i.distance;
                r.origin = at + n * 0.01;
                r.direction = cosine(n, s);
                r.min_distance = 0.001;
            }
            total += light;
        }
        out[row * p.size + gid.x] = total / p.samples;
    }
    """

    struct Params {
        var x0, y0, x1, y1: Float
        var size, samples, bounces, row0, seed: UInt32
        var top: Float
    }

    /// `progress` hears the fraction of rows done after each band.
    public static func bake(triangles: [Float], bounds: (Double, Double, Double, Double), size: Int,
                            samples: Int = 256, bounces: Int = 3, progress: (Double) -> Void = { _ in }) throws -> [Float] {
        func fail(_ s: String) -> Failure { Failure(description: "light bake: \(s)") }
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsRaytracing, let queue = device.makeCommandQueue()
        else { throw fail("no Metal device with ray tracing") }
        let count = triangles.count / 9
        guard count > 0 else { throw fail("no triangles") }
        let vertices = triangles.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)!
        }
        var top: Float = 0
        for i in stride(from: 2, to: triangles.count, by: 3) { top = max(top, triangles[i]) }

        // The acceleration structure over every triangle.
        let geometry = MTLAccelerationStructureTriangleGeometryDescriptor()
        geometry.vertexBuffer = vertices
        geometry.vertexStride = 12
        geometry.vertexFormat = .float3
        geometry.triangleCount = count
        geometry.opaque = true
        let descriptor = MTLPrimitiveAccelerationStructureDescriptor()
        descriptor.geometryDescriptors = [geometry]
        let sizes = device.accelerationStructureSizes(descriptor: descriptor)
        guard let accel = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
              let scratch = device.makeBuffer(length: sizes.buildScratchBufferSize, options: .storageModePrivate),
              let build = queue.makeCommandBuffer(), let enc = build.makeAccelerationStructureCommandEncoder()
        else { throw fail("cannot build the acceleration structure") }
        enc.build(accelerationStructure: accel, descriptor: descriptor, scratchBuffer: scratch, scratchBufferOffset: 0)
        enc.endEncoding()
        build.commit()
        build.waitUntilCompleted()

        let library = try device.makeLibrary(source: shader, options: nil)
        let pipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "bake")!)
        guard let out = device.makeBuffer(length: size * size * 4, options: .storageModeShared) else { throw fail("no memory") }

        // In bands of rows, so no one command runs long enough for the system
        // to stop it.
        let (x0, y0, x1, y1) = bounds
        let band = max(1, min(size, 64 * 1024 * 128 / max(1, samples * size)))
        var row = 0
        while row < size {
            guard let cmd = queue.makeCommandBuffer(), let c = cmd.makeComputeCommandEncoder() else { throw fail("no command buffer") }
            var p = Params(x0: Float(x0), y0: Float(y0), x1: Float(x1), y1: Float(y1), size: UInt32(size),
                           samples: UInt32(samples), bounces: UInt32(bounces), row0: UInt32(row), seed: 7, top: top + 10)
            c.setComputePipelineState(pipeline)
            c.setBytes(&p, length: MemoryLayout<Params>.stride, index: 0)
            c.setAccelerationStructure(accel, bufferIndex: 1)
            c.useResource(accel, usage: .read)
            c.setBuffer(vertices, offset: 0, index: 2)
            c.setBuffer(out, offset: 0, index: 3)
            let rows = min(band, size - row)
            c.dispatchThreads(MTLSize(width: size, height: rows, depth: 1),
                              threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            c.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            if let e = cmd.error { throw fail("\(e)") }
            row += rows
            progress(Double(row) / Double(size))
        }
        let floats = out.contents().bindMemory(to: Float.self, capacity: size * size)
        return Array(UnsafeBufferPointer(start: floats, count: size * size))
    }
}
