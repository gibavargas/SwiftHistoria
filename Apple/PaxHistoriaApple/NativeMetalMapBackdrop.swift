import Metal
import MetalKit
import QuartzCore
import simd
import SwiftUI

private struct NativeMetalMapUniforms {
    var viewportSize: SIMD2<Float>
    var offset: SIMD2<Float>
    var time: Float
    var zoomScale: Float
    var isAdvancing: Float
    var reduceMotion: Float
}

struct NativeMetalMapBackdrop: View {
    let zoomScale: CGFloat
    let offset: CGSize
    let isAdvancing: Bool
    let reduceMotion: Bool

    var body: some View {
        NativeMetalMapBackdropRepresentable(
            zoomScale: zoomScale,
            offset: offset,
            isAdvancing: isAdvancing,
            reduceMotion: reduceMotion
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if os(macOS)
    private typealias PlatformViewRepresentable = NSViewRepresentable
    private typealias PlatformMTKView = MTKView
#else
    private typealias PlatformViewRepresentable = UIViewRepresentable
    private typealias PlatformMTKView = MTKView
#endif

private struct NativeMetalMapBackdropRepresentable: PlatformViewRepresentable {
    let zoomScale: CGFloat
    let offset: CGSize
    let isAdvancing: Bool
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    #if os(macOS)
        func makeNSView(context: Context) -> PlatformMTKView {
            makeView(context: context)
        }

        func updateNSView(_ view: PlatformMTKView, context: Context) {
            updateView(view, coordinator: context.coordinator)
        }
    #else
        func makeUIView(context: Context) -> PlatformMTKView {
            makeView(context: context)
        }

        func updateUIView(_ view: PlatformMTKView, context: Context) {
            updateView(view, coordinator: context.coordinator)
        }
    #endif

    private func makeView(context: Context) -> PlatformMTKView {
        let view = PlatformMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = reduceMotion ? 12 : 30
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0.047, green: 0.082, blue: 0.125, alpha: 1.0)
        view.delegate = context.coordinator
        context.coordinator.configure(for: view.device, pixelFormat: view.colorPixelFormat)
        updateView(view, coordinator: context.coordinator)
        return view
    }

    private func updateView(_ view: PlatformMTKView, coordinator: Coordinator) {
        view.preferredFramesPerSecond = reduceMotion ? 12 : 30
        coordinator.zoomScale = Float(zoomScale)
        coordinator.offset = SIMD2<Float>(Float(offset.width), Float(offset.height))
        coordinator.isAdvancing = isAdvancing
        coordinator.reduceMotion = reduceMotion
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        var zoomScale: Float = 1
        var offset = SIMD2<Float>(0, 0)
        var isAdvancing = false
        var reduceMotion = false

        private var commandQueue: MTLCommandQueue?
        private var pipelineState: MTLRenderPipelineState?
        private let startTime = CACurrentMediaTime()

        func configure(for device: MTLDevice?, pixelFormat: MTLPixelFormat) {
            guard let device, commandQueue == nil else { return }
            commandQueue = device.makeCommandQueue()

            guard let library = try? device.makeLibrary(source: Self.shaderSource, options: nil),
                  let vertexFunction = library.makeFunction(name: "nativeMapBackdropVertex"),
                  let fragmentFunction = library.makeFunction(name: "nativeMapBackdropFragment")
            else {
                return
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = pixelFormat

            pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
        }

        private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct MapBackdropUniforms {
            float2 viewportSize;
            float2 offset;
            float time;
            float zoomScale;
            float isAdvancing;
            float reduceMotion;
        };

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        vertex VertexOut nativeMapBackdropVertex(uint vertexID [[vertex_id]]) {
            float2 positions[3] = {
                float2(-1.0, -1.0),
                float2(3.0, -1.0),
                float2(-1.0, 3.0)
            };

            VertexOut out;
            out.position = float4(positions[vertexID], 0.0, 1.0);
            out.uv = positions[vertexID] * 0.5 + 0.5;
            return out;
        }

        static float lineMask(float value, float spacing, float width) {
            float distanceToLine = abs(fract(value / spacing) - 0.5) * spacing;
            return 1.0 - smoothstep(width, width + 1.5, distanceToLine);
        }

        static float2 mapPointToScreen(float2 mapPoint, constant MapBackdropUniforms &u) {
            float2 base = mapPoint * (u.viewportSize / float2(1000.0, 600.0));
            float2 center = u.viewportSize * 0.5;
            return center + u.offset + (base - center) * u.zoomScale;
        }

        fragment float4 nativeMapBackdropFragment(VertexOut in [[stage_in]],
                                                  constant MapBackdropUniforms &u [[buffer(0)]]) {
            float2 pixel = in.uv * u.viewportSize;
            float2 center = u.viewportSize * 0.5;
            float2 local = center + (pixel - center - u.offset) / max(u.zoomScale, 0.001);

            float3 ocean = float3(0.047, 0.082, 0.125);
            float3 deep = float3(0.025, 0.038, 0.060);
            float vignette = smoothstep(0.95, 0.2, distance(in.uv, float2(0.5)));
            float3 color = mix(deep, ocean, vignette);

            float gridX = lineMask(local.x, u.viewportSize.x / 12.0, 0.75 / u.zoomScale);
            float gridY = lineMask(local.y, u.viewportSize.y / 8.0, 0.75 / u.zoomScale);
            float grid = max(gridX, gridY) * 0.055;
            color += float3(0.57, 0.78, 0.93) * grid;

            float2 waveCenters[6] = {
                float2(300.0, 300.0),
                float2(100.0, 250.0),
                float2(150.0, 400.0),
                float2(880.0, 220.0),
                float2(910.0, 420.0),
                float2(650.0, 450.0)
            };

            float waveOpacity = 0.0;
            for (uint i = 0; i < 6; i++) {
                float2 wave = mapPointToScreen(waveCenters[i], u);
                float drift = sin(u.time * 0.05) * 4.0;
                float2 delta = pixel - (wave + float2(drift, 0.0));
                float crest = abs(delta.y - sin(delta.x * 0.22) * 3.5);
                float inBand = 1.0 - smoothstep(0.0, 1.8, crest);
                float inWidth = 1.0 - smoothstep(10.0 / u.zoomScale, 18.0 / u.zoomScale, abs(delta.x));
                waveOpacity = max(waveOpacity, inBand * inWidth);
            }
            color += float3(0.57, 0.78, 0.93) * waveOpacity * 0.10;

            if (u.isAdvancing > 0.5) {
                float sweepX = (sin(u.time * 0.05) + 1.0) * 0.5 * u.viewportSize.x;
                float sweep = 1.0 - smoothstep(0.0, 2.0 / u.zoomScale, abs(pixel.x - sweepX));
                float trail = smoothstep(52.0 / u.zoomScale, 0.0, sweepX - pixel.x) *
                    step(0.0, sweepX - pixel.x);
                color += float3(0.31, 0.92, 1.0) * (sweep * 0.55 + trail * 0.12);

                float pulsePhase = fract(abs(u.time) / 10.0);
                float pulseRadius = (5.0 + pulsePhase * 25.0) / u.zoomScale;
                float pulseOpacity = (1.0 - pulsePhase) * 0.45;
                float2 pulseCenters[3] = {
                    mapPointToScreen(float2(230.0, 210.0), u),
                    mapPointToScreen(float2(505.0, 330.0), u),
                    mapPointToScreen(float2(760.0, 245.0), u)
                };

                for (uint i = 0; i < 3; i++) {
                    float radius = distance(pixel, pulseCenters[i]);
                    float ring = 1.0 - smoothstep(0.0, 1.75 / u.zoomScale, abs(radius - pulseRadius));
                    color += float3(0.31, 0.92, 1.0) * ring * pulseOpacity;
                }
            }

            return float4(color, 1.0);
        }
        """

        func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

        func draw(in view: MTKView) {
            guard let pipelineState,
                  let commandQueue,
                  let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
            else {
                return
            }

            var uniforms = NativeMetalMapUniforms(
                viewportSize: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                offset: offset,
                time: reduceMotion ? 0 : Float((CACurrentMediaTime() - startTime) * -20),
                zoomScale: max(1, zoomScale),
                isAdvancing: isAdvancing ? 1 : 0,
                reduceMotion: reduceMotion ? 1 : 0
            )

            encoder.setRenderPipelineState(pipelineState)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<NativeMetalMapUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
