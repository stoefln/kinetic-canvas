import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import MetalKit
import OSLog
import simd

final class MetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private static let logger = Logger(subsystem: "app.dancefx.DanceFX", category: "MetalRenderer")
    let device: MTLDevice
    var displayMode: DisplayMode = .composite
    var background: BackgroundChoice = .black
    var threshold: Float = 0
    var edgeSoftness: Float = 0
    var alphaGain: Float = 1
    var gradientEnabled = true
    var gradientStyle: GradientStyle = .neon
    var gradientOpacity: Float = 0.72
    var gradientAngleDegrees: Float = 83
    var clonesEnabled = true
    var cloneCount = 15
    var cloneRotationDegrees: Float = 3
    var cloneScaleStep: Float = -0.015
    var cloneTranslation = SIMD2<Float>(0.015, 0.004)
    var cloneOpacity: Float = 0.50
    var cloneDecay: Float = 0.96
    private let trailSnapshotInterval = 0.05
    var trailLifetime = 3.0
    var trailBlendMode: OverlayBlendMode = .normal
    var gradientBlendMode: OverlayBlendMode = .normal
    var videoBlendMode: OverlayBlendMode = .normal
    var liquidBlendMode: OverlayBlendMode = .normal
    var mirrorOutput = true
    var liquidEnabled = false
    var liquidStrength: Float = 0.025
    var liquidScale: Float = 5
    var liquidSpeed: Float = 1
    var videoFillEnabled = false {
        didSet {
            if videoFillEnabled != oldValue { updateVideoFillPlayback() }
        }
    }
    var videoFillSource = "" {
        didSet {
            if videoFillSource != oldValue { updateVideoFillPlayback() }
        }
    }
    var videoFillOpacity: Float = 1
    var videoFillScale: Float = 1
    var videoFillTiming: VideoFillTiming = .live
    var videoPlaybackRate: Float = 1 {
        didSet {
            if videoPlaybackRate != oldValue { activeVideoFillPlayer?.setRate(videoPlaybackRate) }
        }
    }
    var skeletonEnabled = false
    var skeletonBlendMode: OverlayBlendMode = .normal
    var skeletonOpacity: Float = 1
    var skeletonConfidence: Float = 0.35
    var linesEnabled = false
    var linesOpacity: Float = 0.65
    var linesConfidence: Float = 0.35
    var linesConnections = 3
    var linesThickness: Float = 2
    var linesBlendMode: OverlayBlendMode = .normal
    var linesGeometryOnly = true
    var lineSamplerEnabled = false {
        didSet {
            if !lineSamplerEnabled && oldValue {
                clearSampleHistory()
                sampleSourceTexture = nil
            }
        }
    }
    var sampleLines: [SampleLine] = []
    var lineMIDI: LineSamplerMIDI?
    var sampleDirection: SampleDirection = .both
    var sampleSpeed: Float = 180
    var sampleCount = 180
    var sampleThickness: Float = 3
    var sampleOpacity: Float = 0.8
    var sampleFade: Float = 1
    var sampleBlendMode: OverlayBlendMode = .normal
    var particlesEnabled = false {
        didSet { if !particlesEnabled { clearParticles() } }
    }
    var particleBlendMode: OverlayBlendMode = .normal
    var particleRate: Float = 24
    var particleLifetime: Float = 1.2
    var particleSizeScale: Float = 1
    var particleColorSource: ParticleColorSource = .liveBelow {
        didSet { if particleColorSource != oldValue { clearParticles() } }
    }
    var particleMotionSize: Float = 2.5
    var particleSpeed: Float = 1
    var particleSpreadDegrees: Float = 30
    var particleGravity: Float = 0.08
    var particleDrag: Float = 0
    var particleEndSize: Float = 0.55
    var particleShape: ParticleShape = .disc
    var particleMomentum: Float = 0.65
    var particleSpawnSource: ParticleSpawnSource = .limbs {
        didSet { particleEmissionCarry = 0 }
    }
    var particleBorderThreshold: Float = 0.5
    var clapExplosionsEnabled = false {
        didSet {
            if !clapExplosionsEnabled {
                lock.lock()
                pendingClaps.removeAll()
                handsTouching = false
                lastHandsSeenAt = 0
                lock.unlock()
                explosions.forEach { $0.stop() }
                explosions.removeAll()
            }
        }
    }
    var clapExplosionSize: Float = 0.5
    var clapExplosionOpacity: Float = 1
    var clapExplosionBlendMode: OverlayBlendMode = .screen
    var effectOrder: [EffectKind] = [.gradientOverlay, .historicalTrail]

    private let commandQueue: MTLCommandQueue
    private let basePipeline: MTLComputePipelineState
    private let trailPipeline: MTLComputePipelineState
    private let subjectPipeline: MTLComputePipelineState
    private let signalMaskPipeline: MTLComputePipelineState
    private let snapshotPipeline: MTLComputePipelineState
    private let sampleCapturePipeline: MTLComputePipelineState
    private let sampleCompositePipeline: MTLComputePipelineState
    private let sampleOccupancyPipeline: MTLComputePipelineState
    private let thumbnailPipeline: MTLComputePipelineState
    private let skeletonPipelines: [MTLRenderPipelineState]
    private let linesPipelines: [MTLRenderPipelineState]
    private let particlePipelines: [MTLRenderPipelineState]
    private let skeletonMaskPipeline: MTLRenderPipelineState
    private let particleMaskPipeline: MTLRenderPipelineState
    private let particleColorCapturePipeline: MTLComputePipelineState
    private let explosionPipelines: [MTLRenderPipelineState]
    private let ciContext: CIContext
    private var textureCache: CVMetalTextureCache!
    private weak var view: MTKView?
    private let lock = NSLock()
    private var pending: PendingFrame?
    private var pendingFrameCapture: FrameCaptureRequest?
    private var trailFrames: [TrailFrame] = []
    private var lastSnapshotTime: CFTimeInterval = 0
    private var videoFillURLs: [String: URL] = [:]
    private var videoFillPlayers: [String: VideoFillPlayer] = [:]
    private var latestPose: BodyPose?
    private var poseUpdatedAt: CFTimeInterval = 0
    private var particles: [Particle] = []
    private var particleColorTexture: MTLTexture?
    private var particleColorBuffer: MTLBuffer?
    private var pendingParticleColorCaptures: [ParticleColorCapture] = []
    private var freeParticleColorSlots: [UInt32] = []
    private var nextParticleColorSlot: UInt32 = 0
    private var lastParticleUpdate: CFTimeInterval = 0
    private var particleEmissionCarry: Float = 0
    private var randomState: UInt32 = 0xC0FFEE
    private var poseVelocities: [PoseJoint: SIMD2<Float>] = [:]
    private var particleBorderEmitters: [ParticleBorderEmitter] = []
    private var pendingClaps: [SIMD2<Float>] = []
    private var handsTouching = false
    private var lastHandsSeenAt: CFTimeInterval = 0
    private var lastClapAt: CFTimeInterval = 0
    private var explosions: [ClapExplosionPlayer] = []
    private var nextExplosionSegment = 0
    private var explosionURL: URL?
    private var signalMaskTexture: MTLTexture?
    private var snapshotPool: [SignalSnapshotTextures] = []
    private var sampleHistories: [UUID: SampleHistory] = [:]
    private var sampleHistoryIDs: Set<UUID> = []
    private var sampleSourceTexture: MTLTexture?
    private let occupancyLock = NSLock()
    private var occupancyBuffers: [MTLBuffer] = []
    private var occupancyBusy = [false, false, false]
    // Each retained row occupies a fixed amount of geometry. Deriving this from
    // recent render intervals made the entire sampled block breathe when frame
    // delivery varied during UI interaction.
    private let sampleFrameStep: Float = 1.0 / 60.0

    private static let shader = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct Params {
        uint mode;
        uint background;
        float threshold;
        float edgeSoftness;
        float alphaGain;
        float sourceAspect;
        float viewAspect;
        uint gradientEnabled;
        uint gradientStyle;
        float gradientOpacity;
        float gradientAngle;
        uint cloneEnabled;
        uint cloneCount;
        float cloneRotation;
        float cloneScaleStep;
        float2 cloneTranslation;
        float cloneOpacity;
        float cloneDecay;
        uint trailBlendMode;
        uint mirrorOutput;
        uint liquidEnabled;
        float liquidStrength;
        float liquidScale;
        float liquidSpeed;
        float time;
        uint videoFillEnabled;
        float videoFillOpacity;
        float videoAspect;
        float videoScale;
        uint gradientOrder;
        uint liquidOrder;
        uint videoOrder;
        uint linesOrder;
        uint particleOrder;
        uint historicalOrder;
        uint processingLimitOrder;
        uint particleShape;
        uint subjectVisible;
        uint linesBlendMode;
        uint gradientBlendMode;
        uint videoBlendMode;
        uint liquidBlendMode;
        uint particleBlendMode;
    };

    struct TrailLayerParams {
        float amount;
        float opacity;
    };

    struct SampleParams {
        float4 endpoints;
        float4 settings; // speed, lifetime, thickness, opacity
        float4 history;  // fade, frame interval, newest row, valid rows
        uint4 options;   // direction, blend mode
    };

    struct OccupancyLine {
        float4 endpoints;
        uint sections;
        float thickness;
        uint enabled;
        uint padding;
    };

    struct OverlayVertex {
        float2 position;
        float4 color;
        float pointSize;
        uint colorSlot;
    };

    struct OverlayOutput {
        float4 position [[position]];
        float4 color;
        float pointSize [[point_size]];
        float2 uv;
        uint colorSlot [[flat]];
    };

    struct ParticleColorCapture {
        float2 uv;
        uint slot;
    };

    struct ExplosionVertex {
        float2 position;
        float2 uv;
    };

    struct ExplosionOutput {
        float4 position [[position]];
        float2 uv;
    };

    float3 backgroundColor(uint choice, float2 uv) {
        if (choice == 1) return float3(1.0);
        if (choice == 2) return float3(0.18);
        if (choice == 3) {
            uint2 tile = uint2(uv * 24.0);
            return ((tile.x + tile.y) & 1) ? float3(0.38) : float3(0.16);
        }
        return float3(0.0);
    }

    float2 cameraUVForViewUV(float2 uv, constant Params& params) {
        float2 cameraUV = uv;
        if (params.viewAspect > params.sourceAspect) {
            float scale = params.sourceAspect / params.viewAspect;
            cameraUV.y = (uv.y - 0.5) * scale + 0.5;
        } else {
            float scale = params.viewAspect / params.sourceAspect;
            cameraUV.x = (uv.x - 0.5) * scale + 0.5;
        }
        if (params.mirrorOutput != 0) {
            cameraUV.x = 1.0 - cameraUV.x;
        }
        return cameraUV;
    }

    float2 aspectFillUV(float2 uv, float sourceAspect, float viewAspect) {
        float2 sourceUV = uv;
        if (viewAspect > sourceAspect) {
            float scale = sourceAspect / viewAspect;
            sourceUV.y = (uv.y - 0.5) * scale + 0.5;
        } else {
            float scale = viewAspect / sourceAspect;
            sourceUV.x = (uv.x - 0.5) * scale + 0.5;
        }
        return sourceUV;
    }

    bool insideUnitSquare(float2 uv) {
        return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
    }

    float2 liquidUV(float2 uv, constant Params& params, float phaseOffset) {
        if (params.liquidEnabled == 0 || params.liquidStrength <= 0.00001) return uv;
        float frequency = max(0.5, params.liquidScale);
        float phase = params.time * params.liquidSpeed + phaseOffset;
        float2 p = uv - 0.5;
        p.x *= params.viewAspect;
        float2 warp;
        warp.x = sin((p.y * frequency + phase) * 6.2831853)
               + 0.45 * sin((p.x * frequency * 0.73 - phase * 1.37) * 6.2831853);
        warp.y = cos((p.x * frequency * 0.81 + phase * 0.91) * 6.2831853)
               + 0.45 * sin((p.y * frequency * 1.19 + phase * 1.21) * 6.2831853);
        p += warp * params.liquidStrength;
        p.x /= params.viewAspect;
        return p + 0.5;
    }

    float processedAlpha(float value, constant Params& params) {
        float a = value * params.alphaGain;
        if (params.edgeSoftness > 0.0001) {
            a = smoothstep(params.threshold - params.edgeSoftness,
                           params.threshold + params.edgeSoftness, a);
        } else if (params.threshold > 0.0001) {
            a = a >= params.threshold ? 1.0 : 0.0;
        }
        return clamp(a, 0.0, 1.0);
    }

    float3 gradientColor(float2 uv, constant Params& params) {
        float2 direction = float2(cos(params.gradientAngle), sin(params.gradientAngle));
        float t = clamp(dot(uv - 0.5, direction) + 0.5, 0.0, 1.0);
        float3 c0;
        float3 c1;
        float3 c2;
        if (params.gradientStyle == 1) {
            c0 = float3(0.95, 0.03, 0.16);
            c1 = float3(1.00, 0.58, 0.04);
            c2 = float3(0.66, 0.03, 0.50);
        } else if (params.gradientStyle == 2) {
            c0 = float3(0.03, 0.20, 0.95);
            c1 = float3(0.08, 0.88, 1.00);
            c2 = float3(0.88, 1.00, 1.00);
        } else {
            c0 = float3(0.00, 0.95, 0.78);
            c1 = float3(0.42, 0.08, 1.00);
            c2 = float3(1.00, 0.02, 0.48);
        }
        return t < 0.5 ? mix(c0, c1, t * 2.0) : mix(c1, c2, (t - 0.5) * 2.0);
    }

    float3 trailBlend(float3 base, float3 layer, float opacity, uint mode);

    float3 videoFilledColor(
        float3 source,
        float2 uv,
        constant Params& params,
        texture2d<float, access::sample> videoTexture)
    {
        constexpr sampler videoSampler(address::clamp_to_edge, filter::linear);
        float2 scaledUV = (uv - 0.5) / max(0.1, params.videoScale) + 0.5;
        float2 videoUV = aspectFillUV(scaledUV, params.videoAspect, params.viewAspect);
        float3 videoColor = videoTexture.sample(videoSampler, videoUV).rgb;
        return trailBlend(source, videoColor, params.videoFillOpacity, params.videoBlendMode);
    }

    float3 effectedColor(
        float3 source,
        float2 uv,
        constant Params& params,
        texture2d<float, access::sample> videoTexture)
    {
        float3 color = source;
        bool useVideo = params.videoFillEnabled != 0;
        bool useGradient = params.gradientEnabled != 0;
        if (useVideo && useGradient && params.gradientOrder < params.videoOrder) {
            color = trailBlend(color, gradientColor(uv, params), params.gradientOpacity, params.gradientBlendMode);
            color = videoFilledColor(color, uv, params, videoTexture);
            return color;
        }
        if (useVideo) {
            color = videoFilledColor(color, uv, params, videoTexture);
        }
        if (useGradient) {
            color = trailBlend(color, gradientColor(uv, params), params.gradientOpacity, params.gradientBlendMode);
        }
        return color;
    }

    float3 effectedParticleColor(
        float2 uv,
        constant Params& params,
        texture2d<float, access::sample> videoTexture)
    {
        float3 color = float3(1.0);
        bool useVideo = params.videoFillEnabled != 0
            && params.videoOrder > params.particleOrder
            && params.videoOrder < params.processingLimitOrder;
        bool useGradient = params.gradientEnabled != 0
            && params.gradientOrder > params.particleOrder
            && params.gradientOrder < params.processingLimitOrder;
        if (useVideo && useGradient && params.gradientOrder < params.videoOrder) {
            color = trailBlend(color, gradientColor(uv, params), params.gradientOpacity, params.gradientBlendMode);
            return videoFilledColor(color, uv, params, videoTexture);
        }
        if (useVideo) color = videoFilledColor(color, uv, params, videoTexture);
        if (useGradient) {
            color = trailBlend(color, gradientColor(uv, params), params.gradientOpacity, params.gradientBlendMode);
        }
        return color;
    }

    float3 effectedLineColor(
        float2 uv,
        constant Params& params,
        texture2d<float, access::sample> videoTexture)
    {
        float3 color = float3(1.0);
        bool useVideo = params.videoFillEnabled != 0
            && params.videoOrder > params.linesOrder
            && params.videoOrder < params.processingLimitOrder;
        bool useGradient = params.gradientEnabled != 0
            && params.gradientOrder > params.linesOrder
            && params.gradientOrder < params.processingLimitOrder;
        if (useVideo && useGradient && params.gradientOrder < params.videoOrder) {
            color = trailBlend(color, gradientColor(uv, params), params.gradientOpacity, params.gradientBlendMode);
            return videoFilledColor(color, uv, params, videoTexture);
        }
        if (useVideo) color = videoFilledColor(color, uv, params, videoTexture);
        if (useGradient) {
            color = trailBlend(color, gradientColor(uv, params), params.gradientOpacity, params.gradientBlendMode);
        }
        return color;
    }

    float3 effectedTrailColor(
        float3 source,
        float2 uv,
        constant Params& params,
        texture2d<float, access::sample> videoTexture)
    {
        float3 color = source;
        bool useVideo = params.videoFillEnabled != 0 && params.videoOrder > params.historicalOrder;
        bool useGradient = params.gradientEnabled != 0 && params.gradientOrder > params.historicalOrder;
        if (useVideo && useGradient && params.gradientOrder < params.videoOrder) {
            color = trailBlend(color, gradientColor(uv, params), params.gradientOpacity, params.gradientBlendMode);
            return videoFilledColor(color, uv, params, videoTexture);
        }
        if (useVideo) color = videoFilledColor(color, uv, params, videoTexture);
        if (useGradient) {
            color = trailBlend(color, gradientColor(uv, params), params.gradientOpacity, params.gradientBlendMode);
        }
        return color;
    }

    float3 trailBlend(float3 base, float3 layer, float opacity, uint mode) {
        float amount = clamp(opacity, 0.0, 1.0);
        if (mode == 1) return clamp(base + layer * amount, 0.0, 1.0);
        if (mode == 2) return 1.0 - (1.0 - base) * (1.0 - layer * amount);
        if (mode == 3) return mix(base, max(base, layer), amount);
        if (mode == 4) return mix(base, base * layer, amount);
        if (mode == 5) return max(float3(0.0), base - layer * amount);
        return mix(base, layer, amount);
    }

    kernel void basePass(
        texture2d<float, access::sample> source [[texture(0)]],
        texture2d<float, access::sample> alphaTexture [[texture(1)]],
        texture2d<float, access::write> output [[texture(2)]],
        constant Params& params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 outSize = float2(output.get_width(), output.get_height());
        float2 uv = (float2(gid) + 0.5) / outSize;

        float2 cameraUV = cameraUVForViewUV(uv, params);

        float4 camera = source.sample(s, cameraUV);
        if (params.mode == 0) {
            output.write(float4(camera.rgb, 1.0), gid);
            return;
        }

        float a = processedAlpha(alphaTexture.sample(s, cameraUV).r, params);
        if (params.mode == 1) {
            output.write(float4(float3(a), 1.0), gid);
            return;
        }

        output.write(float4(backgroundColor(params.background, uv), 1.0), gid);
    }

    kernel void trailPass(
        texture2d<float, access::sample> source [[texture(0)]],
        texture2d<float, access::sample> alphaTexture [[texture(1)]],
        texture2d<float, access::read_write> output [[texture(2)]],
        texture2d<float, access::sample> videoTexture [[texture(3)]],
        constant Params& params [[buffer(0)]],
        constant TrailLayerParams& layer [[buffer(1)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        if (params.mode < 2 || params.cloneEnabled == 0) return;
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
        float scale = clamp(1.0 + params.cloneScaleStep * layer.amount, 0.35, 2.5);
        float angle = -params.cloneRotation * layer.amount;
        float2 p = uv - 0.5 - params.cloneTranslation * layer.amount;
        p.x *= params.viewAspect;
        float cosine = cos(angle);
        float sine = sin(angle);
        float2 transformed = float2(
            cosine * p.x - sine * p.y,
            sine * p.x + cosine * p.y
        ) / scale;
        transformed.x /= params.viewAspect;
        float2 trailViewUV = transformed + 0.5;
        float2 distortedTrailUV = liquidUV(trailViewUV, params, layer.amount * 0.17);
        float2 trailCameraUV = cameraUVForViewUV(distortedTrailUV, params);
        if (!insideUnitSquare(trailCameraUV)) return;

        float a = processedAlpha(alphaTexture.sample(s, trailCameraUV).r, params) * layer.opacity;
        float3 trailSource = source.sample(s, trailCameraUV).rgb;
        if (params.liquidEnabled != 0) {
            float2 originalUV = cameraUVForViewUV(trailViewUV, params);
            float3 original = source.sample(s, originalUV).rgb;
            trailSource = trailBlend(original, trailSource, 1.0, params.liquidBlendMode);
        }
        float3 trailColor = effectedColor(trailSource, distortedTrailUV, params, videoTexture);
        float3 base = output.read(gid).rgb;
        output.write(float4(trailBlend(base, trailColor, a, params.trailBlendMode), 1.0), gid);
    }

    kernel void signalTrailPass(
        texture2d<float, access::sample> source [[texture(0)]],
        texture2d<float, access::sample> alphaTexture [[texture(1)]],
        texture2d<float, access::read_write> output [[texture(2)]],
        texture2d<float, access::sample> videoTexture [[texture(3)]],
        constant Params& params [[buffer(0)]],
        constant TrailLayerParams& layer [[buffer(1)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
        float scale = clamp(1.0 + params.cloneScaleStep * layer.amount, 0.35, 2.5);
        float angle = -params.cloneRotation * layer.amount;
        float2 p = uv - 0.5 - params.cloneTranslation * layer.amount;
        p.x *= params.viewAspect;
        float cosine = cos(angle);
        float sine = sin(angle);
        float2 transformed = float2(
            cosine * p.x - sine * p.y,
            sine * p.x + cosine * p.y
        ) / scale;
        transformed.x /= params.viewAspect;
        float2 sampleUV = transformed + 0.5;
        if (params.liquidEnabled != 0 && params.liquidOrder > params.historicalOrder) {
            sampleUV = liquidUV(sampleUV, params, layer.amount * 0.17);
        }
        if (!insideUnitSquare(sampleUV)) return;
        float a = alphaTexture.sample(s, sampleUV).r * layer.opacity;
        float3 color = source.sample(s, sampleUV).rgb;
        color = effectedTrailColor(color, sampleUV, params, videoTexture);
        float3 base = output.read(gid).rgb;
        output.write(float4(trailBlend(base, color, a, params.trailBlendMode), 1.0), gid);
    }

    kernel void signalMaskPass(
        texture2d<float, access::sample> alphaTexture [[texture(0)]],
        texture2d<float, access::write> output [[texture(1)]],
        constant Params& params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
        float2 effectedUV = params.liquidEnabled != 0 && params.liquidOrder < params.historicalOrder
            ? liquidUV(uv, params, 0.0) : uv;
        float2 cameraUV = cameraUVForViewUV(effectedUV, params);
        float a = params.subjectVisible != 0 && insideUnitSquare(cameraUV)
            ? processedAlpha(alphaTexture.sample(s, cameraUV).r, params) : 0.0;
        output.write(float4(a), gid);
    }

    kernel void snapshotPass(
        texture2d<float, access::read> source [[texture(0)]],
        texture2d<float, access::read> sourceMask [[texture(1)]],
        texture2d<float, access::write> colorOutput [[texture(2)]],
        texture2d<float, access::write> maskOutput [[texture(3)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= colorOutput.get_width() || gid.y >= colorOutput.get_height()) return;
        uint2 origin = gid * 2;
        uint2 sourceLimit = uint2(source.get_width() - 1, source.get_height() - 1);
        float strongestMask = -1.0;
        float4 strongestColor = float4(0.0);
        // Trail textures are half-sized. Selecting the strongest source sample
        // preserves one-pixel pose geometry that linear downsampling can erase.
        for (uint y = 0; y < 2; ++y) {
            for (uint x = 0; x < 2; ++x) {
                uint2 sourcePosition = min(origin + uint2(x, y), sourceLimit);
                float candidateMask = sourceMask.read(sourcePosition).r;
                if (candidateMask > strongestMask) {
                    strongestMask = candidateMask;
                    strongestColor = source.read(sourcePosition);
                }
            }
        }
        colorOutput.write(strongestColor, gid);
        maskOutput.write(float4(max(0.0, strongestMask)), gid);
    }

    kernel void subjectPass(
        texture2d<float, access::sample> source [[texture(0)]],
        texture2d<float, access::sample> alphaTexture [[texture(1)]],
        texture2d<float, access::read_write> output [[texture(2)]],
        texture2d<float, access::sample> videoTexture [[texture(3)]],
        constant Params& params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        if (params.mode < 2 || params.subjectVisible == 0) return;
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
        float2 distortedUV = liquidUV(uv, params, 0.0);
        float2 cameraUV = cameraUVForViewUV(distortedUV, params);
        if (!insideUnitSquare(cameraUV)) return;
        float a = processedAlpha(alphaTexture.sample(s, cameraUV).r, params);
        float3 subject = source.sample(s, cameraUV).rgb;
        if (params.liquidEnabled != 0) {
            float2 originalUV = cameraUVForViewUV(uv, params);
            float3 original = source.sample(s, originalUV).rgb;
            subject = trailBlend(original, subject, 1.0, params.liquidBlendMode);
        }
        subject = effectedColor(subject, distortedUV, params, videoTexture);
        float3 base = output.read(gid).rgb;
        output.write(float4(mix(base, subject, a), 1.0), gid);
    }

    vertex OverlayOutput overlayVertex(
        const device OverlayVertex* vertices [[buffer(0)]],
        uint vertexID [[vertex_id]])
    {
        OverlayOutput out;
        out.position = float4(vertices[vertexID].position, 0.0, 1.0);
        out.color = vertices[vertexID].color;
        out.pointSize = vertices[vertexID].pointSize;
        out.colorSlot = vertices[vertexID].colorSlot;
        out.uv = float2((vertices[vertexID].position.x + 1.0) * 0.5,
                        (1.0 - vertices[vertexID].position.y) * 0.5);
        return out;
    }

    fragment float4 skeletonFragment(OverlayOutput in [[stage_in]], constant uint& blendMode [[buffer(1)]]) {
        float3 color = (blendMode == 2 || blendMode == 4) ? in.color.rgb * in.color.a : in.color.rgb;
        return float4(color, in.color.a);
    }

    fragment float4 skeletonMaskFragment(OverlayOutput in [[stage_in]]) {
        return float4(1.0);
    }

    fragment float4 linesFragment(
        OverlayOutput in [[stage_in]],
        constant Params& params [[buffer(0)]],
        texture2d<float, access::sample> videoTexture [[texture(0)]])
    {
        float3 color = effectedLineColor(in.uv, params, videoTexture);
        // Screen blending uses premultiplied source color so opacity affects
        // both terms of 1 - (1 - source) * (1 - destination).
        if (params.linesBlendMode == 2 || params.linesBlendMode == 4) color *= in.color.a;
        return float4(color, in.color.a);
    }

    float particleShapeAlpha(float2 pointCoord, uint shape) {
        float2 p = pointCoord - 0.5;
        float radial = length(p) * 2.0;
        if (shape == 1) {
            float outer = 1.0 - smoothstep(0.82, 1.0, radial);
            float inner = smoothstep(0.38, 0.56, radial);
            return outer * inner;
        }
        if (shape == 2) {
            float boxDistance = max(abs(p.x), abs(p.y)) * 2.0;
            return 1.0 - smoothstep(0.82, 1.0, boxDistance);
        }
        if (shape == 3) {
            float diamondDistance = (abs(p.x) + abs(p.y)) * 2.0;
            return 1.0 - smoothstep(0.82, 1.0, diamondDistance);
        }
        if (shape == 4) {
            float horizontal = (1.0 - smoothstep(0.06, 0.18, abs(p.y)))
                * (1.0 - smoothstep(0.65, 1.0, abs(p.x) * 2.0));
            float vertical = (1.0 - smoothstep(0.06, 0.18, abs(p.x)))
                * (1.0 - smoothstep(0.65, 1.0, abs(p.y) * 2.0));
            return max(horizontal, vertical);
        }
        return 1.0 - smoothstep(0.55, 1.0, radial);
    }

    fragment float4 particleMaskFragment(
        OverlayOutput in [[stage_in]],
        constant Params& params [[buffer(0)]],
        float2 pointCoord [[point_coord]])
    {
        return float4(particleShapeAlpha(pointCoord, params.particleShape));
    }

    fragment float4 particleFragment(
        OverlayOutput in [[stage_in]],
        constant Params& params [[buffer(0)]],
        device const float4* capturedColors [[buffer(1)]],
        texture2d<float, access::sample> videoTexture [[texture(0)]],
        constant uint& colorSource [[buffer(2)]],
        float2 pointCoord [[point_coord]])
    {
        float edge = particleShapeAlpha(pointCoord, params.particleShape);
        float alpha = in.color.a * edge;
        float3 color = colorSource == 1
            ? capturedColors[in.colorSlot].rgb
            : effectedParticleColor(in.uv, params, videoTexture);
        if (params.particleBlendMode == 2 || params.particleBlendMode == 4) color *= alpha;
        return float4(color, alpha);
    }

    kernel void captureParticleColors(
        texture2d<float, access::sample> below [[texture(0)]],
        device const ParticleColorCapture* captures [[buffer(0)]],
        device float4* colors [[buffer(1)]],
        constant uint& count [[buffer(2)]],
        uint index [[thread_position_in_grid]])
    {
        if (index >= count) return;
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        colors[captures[index].slot] = below.sample(s, captures[index].uv);
    }

    vertex ExplosionOutput explosionVertex(
        const device ExplosionVertex* vertices [[buffer(0)]],
        uint vertexID [[vertex_id]])
    {
        ExplosionOutput out;
        out.position = float4(vertices[vertexID].position, 0.0, 1.0);
        out.uv = vertices[vertexID].uv;
        return out;
    }

    fragment float4 explosionFragment(
        ExplosionOutput in [[stage_in]],
        texture2d<float, access::sample> clip [[texture(0)]],
        constant float& opacity [[buffer(0)]],
        constant uint& blendMode [[buffer(1)]])
    {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float4 sampleColor = clip.sample(s, in.uv);
        float brightness = max(sampleColor.r, max(sampleColor.g, sampleColor.b));
        float2 centered = (in.uv - 0.5) * 2.0;
        float edge = 1.0 - smoothstep(0.78, 1.0, length(centered));
        float alpha = sampleColor.a * smoothstep(0.015, 0.12, brightness) * edge * opacity;
        float3 color = (blendMode == 2 || blendMode == 4) ? sampleColor.rgb * alpha : sampleColor.rgb;
        return float4(color, alpha);
    }

    kernel void sampleOccupancyPass(
        texture2d<float, access::sample> source [[texture(0)]],
        constant OccupancyLine* lines [[buffer(0)]],
        device ushort* bits [[buffer(1)]],
        uint id [[thread_position_in_grid]])
    {
        if (id >= 16) return;
        OccupancyLine line = lines[id];
        if (line.enabled == 0 || line.sections == 0) { bits[id] = 0; return; }
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 size = float2(source.get_width(), source.get_height());
        float2 a = line.endpoints.xy * size;
        float2 b = line.endpoints.zw * size;
        float2 axis = b - a;
        float2 normal = float2(axis.y, -axis.x) / max(length(axis), 1.0);
        ushort mask = 0;
        for (uint section = 0; section < line.sections; section++) {
            uint hits = 0;
            for (uint along = 0; along < 7; along++) {
                float t = (float(section) + (float(along) + 0.5) / 7.0) / float(line.sections);
                float2 center = mix(a, b, t);
                for (int across = -1; across <= 1; across++) {
                    float2 uv = (center + normal * line.thickness * float(across) * 0.4) / size;
                    float3 color = source.sample(s, uv).rgb;
                    if (dot(color, float3(0.2126, 0.7152, 0.0722)) > 0.065) hits++;
                }
            }
            if (hits >= 4) mask |= ushort(1u << section);
        }
        bits[id] = mask;
    }

    kernel void sampleCapturePass(
        texture2d<float, access::sample> source [[texture(0)]],
        texture2d<float, access::write> history [[texture(1)]],
        constant SampleParams& params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= history.get_width() || gid.y > 0) return;
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 size = float2(source.get_width(), source.get_height());
        float2 a = params.endpoints.xy * size;
        float2 b = params.endpoints.zw * size;
        float2 tangent = normalize(b - a);
        float2 normal = float2(tangent.y, -tangent.x);
        float2 center = mix(a, b, (float(gid.x) + 0.5) / float(history.get_width()));
        float3 color = float3(0.0);
        for (int i = -2; i <= 2; i++) {
            float2 uv = (center + normal * params.settings.z * float(i) * 0.25) / size;
            color += source.sample(s, uv).rgb * 0.2;
        }
        history.write(float4(color, 1.0), uint2(gid.x, uint(params.history.z)));
    }

    kernel void sampleCompositePass(
        texture2d<float, access::sample> history [[texture(0)]],
        texture2d<float, access::read_write> output [[texture(1)]],
        constant SampleParams& params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        float2 size = float2(output.get_width(), output.get_height());
        float2 a = params.endpoints.xy * size;
        float2 b = params.endpoints.zw * size;
        float2 axis = b - a;
        float len = length(axis);
        if (len < 2.0) return;
        float2 tangent = axis / len;
        float2 normal = float2(tangent.y, -tangent.x);
        float2 relative = float2(gid) + 0.5 - a;
        float along = dot(relative, tangent) / len;
        if (along < 0.0 || along > 1.0) return;
        float signedDistance = dot(relative, normal);
        if (params.options.x == 1 && signedDistance < 0.0) return;
        if (params.options.x == 2 && signedDistance > 0.0) return;
        float distance = abs(signedDistance);
        float age = distance / max(params.settings.x, 1.0);
        float frames = age / max(params.history.y, 0.001);
        float retainedSamples = min(params.history.w, max(params.settings.y, 1.0));
        if (frames >= retainedSamples) return;
        uint newest = uint(params.history.z);
        uint offset = uint(floor(frames));
        uint row = (newest + history.get_height() - offset % history.get_height()) % history.get_height();
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float3 color = history.sample(s, float2(along, (float(row) + 0.5) / float(history.get_height()))).rgb;
        float progress = clamp(frames / max(retainedSamples - 1.0, 1.0), 0.0, 1.0);
        float fade = params.history.x <= 0.001 ? 1.0 : pow(1.0 - progress, params.history.x);
        float opacity = params.settings.w * fade;
        float3 base = output.read(gid).rgb;
        output.write(float4(trailBlend(base, color, opacity, params.options.y), 1.0), gid);
    }

    kernel void thumbnailPass(
        texture2d<float, access::sample> source [[texture(0)]],
        device uchar4* pixels [[buffer(0)]],
        constant uint2& outputSize [[buffer(1)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= outputSize.x || gid.y >= outputSize.y) return;
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 uv = (float2(gid) + 0.5) / float2(outputSize);
        float3 color = saturate(source.sample(s, uv).rgb) * 255.0;
        pixels[gid.y * outputSize.x + gid.x] = uchar4(
            uchar(color.b + 0.5), uchar(color.g + 0.5), uchar(color.r + 0.5), 255);
    }
    """#

    override init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            fatalError("DanceFX requires a Metal-capable Mac.")
        }
        self.device = device
        self.commandQueue = commandQueue
        self.ciContext = CIContext(mtlDevice: device)
        do {
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            guard let base = library.makeFunction(name: "basePass"),
                  let trail = library.makeFunction(name: "signalTrailPass"),
                  let subject = library.makeFunction(name: "subjectPass"),
                  let signalMask = library.makeFunction(name: "signalMaskPass"),
                  let snapshot = library.makeFunction(name: "snapshotPass"),
                  let sampleCapture = library.makeFunction(name: "sampleCapturePass"),
                  let sampleOccupancy = library.makeFunction(name: "sampleOccupancyPass"),
                  let sampleComposite = library.makeFunction(name: "sampleCompositePass"),
                  let captureParticleColors = library.makeFunction(name: "captureParticleColors"),
                  let thumbnail = library.makeFunction(name: "thumbnailPass") else {
                fatalError("One or more Metal effects functions are missing.")
            }
            self.basePipeline = try device.makeComputePipelineState(function: base)
            self.trailPipeline = try device.makeComputePipelineState(function: trail)
            self.subjectPipeline = try device.makeComputePipelineState(function: subject)
            self.signalMaskPipeline = try device.makeComputePipelineState(function: signalMask)
            self.snapshotPipeline = try device.makeComputePipelineState(function: snapshot)
            self.sampleCapturePipeline = try device.makeComputePipelineState(function: sampleCapture)
            self.sampleOccupancyPipeline = try device.makeComputePipelineState(function: sampleOccupancy)
            self.sampleCompositePipeline = try device.makeComputePipelineState(function: sampleComposite)
            self.particleColorCapturePipeline = try device.makeComputePipelineState(function: captureParticleColors)
            self.thumbnailPipeline = try device.makeComputePipelineState(function: thumbnail)

            guard let overlayVertex = library.makeFunction(name: "overlayVertex"),
                  let skeletonFragment = library.makeFunction(name: "skeletonFragment"),
                  let linesFragment = library.makeFunction(name: "linesFragment"),
                  let particleFragment = library.makeFunction(name: "particleFragment"),
                  let skeletonMaskFragment = library.makeFunction(name: "skeletonMaskFragment"),
                  let particleMaskFragment = library.makeFunction(name: "particleMaskFragment") else {
                fatalError("One or more pose overlay functions are missing.")
            }
            let blendConfigurations: [(MTLRenderPipelineColorAttachmentDescriptor?) -> Void] = [
                Self.configureAlphaBlending,
                Self.configureAddBlending,
                Self.configureScreenBlending,
                Self.configureLightenBlending,
                Self.configureMultiplyBlending,
                Self.configureSubtractBlending
            ]
            func makeOverlayPipeline(
                fragment: MTLFunction,
                configure: (MTLRenderPipelineColorAttachmentDescriptor?) -> Void
            ) throws -> MTLRenderPipelineState {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = overlayVertex
                descriptor.fragmentFunction = fragment
                descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                configure(descriptor.colorAttachments[0])
                return try device.makeRenderPipelineState(descriptor: descriptor)
            }
            self.skeletonPipelines = try blendConfigurations.map {
                try makeOverlayPipeline(fragment: skeletonFragment, configure: $0)
            }
            self.linesPipelines = try blendConfigurations.map {
                try makeOverlayPipeline(fragment: linesFragment, configure: $0)
            }
            self.particlePipelines = try blendConfigurations.map {
                try makeOverlayPipeline(fragment: particleFragment, configure: $0)
            }

            let skeletonMaskDescriptor = MTLRenderPipelineDescriptor()
            skeletonMaskDescriptor.vertexFunction = overlayVertex
            skeletonMaskDescriptor.fragmentFunction = skeletonMaskFragment
            skeletonMaskDescriptor.colorAttachments[0].pixelFormat = .r8Unorm
            Self.configureMaskBlending(skeletonMaskDescriptor.colorAttachments[0])
            self.skeletonMaskPipeline = try device.makeRenderPipelineState(descriptor: skeletonMaskDescriptor)

            let particleMaskDescriptor = MTLRenderPipelineDescriptor()
            particleMaskDescriptor.vertexFunction = overlayVertex
            particleMaskDescriptor.fragmentFunction = particleMaskFragment
            particleMaskDescriptor.colorAttachments[0].pixelFormat = .r8Unorm
            Self.configureMaskBlending(particleMaskDescriptor.colorAttachments[0])
            self.particleMaskPipeline = try device.makeRenderPipelineState(descriptor: particleMaskDescriptor)

            guard let explosionVertex = library.makeFunction(name: "explosionVertex"),
                  let explosionFragment = library.makeFunction(name: "explosionFragment") else {
                fatalError("Explosion shader functions are missing.")
            }
            self.explosionPipelines = try blendConfigurations.map { configure in
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = explosionVertex
                descriptor.fragmentFunction = explosionFragment
                descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                configure(descriptor.colorAttachments[0])
                return try device.makeRenderPipelineState(descriptor: descriptor)
            }
        } catch {
            fatalError("Metal shader compilation failed: \(error)")
        }
        super.init()
        occupancyBuffers = (0..<3).compactMap { _ in
            device.makeBuffer(length: 16 * MemoryLayout<UInt16>.stride, options: .storageModeShared)
        }
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    private static func configureAlphaBlending(_ attachment: MTLRenderPipelineColorAttachmentDescriptor?) {
        attachment?.isBlendingEnabled = true
        attachment?.sourceRGBBlendFactor = .sourceAlpha
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    private static func configureMaskBlending(_ attachment: MTLRenderPipelineColorAttachmentDescriptor?) {
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .max
        attachment?.alphaBlendOperation = .max
        attachment?.sourceRGBBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationAlphaBlendFactor = .one
    }

    private static func configureAddBlending(_ attachment: MTLRenderPipelineColorAttachmentDescriptor?) {
        attachment?.isBlendingEnabled = true
        attachment?.sourceRGBBlendFactor = .sourceAlpha
        attachment?.destinationRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationAlphaBlendFactor = .one
    }

    private static func configureScreenBlending(_ attachment: MTLRenderPipelineColorAttachmentDescriptor?) {
        attachment?.isBlendingEnabled = true
        attachment?.sourceRGBBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .oneMinusSourceColor
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    private static func configureLightenBlending(_ attachment: MTLRenderPipelineColorAttachmentDescriptor?) {
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .max
        attachment?.alphaBlendOperation = .max
        attachment?.sourceRGBBlendFactor = .sourceAlpha
        attachment?.destinationRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationAlphaBlendFactor = .one
    }

    private static func configureMultiplyBlending(_ attachment: MTLRenderPipelineColorAttachmentDescriptor?) {
        attachment?.isBlendingEnabled = true
        attachment?.sourceRGBBlendFactor = .destinationColor
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    private static func configureSubtractBlending(_ attachment: MTLRenderPipelineColorAttachmentDescriptor?) {
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .reverseSubtract
        attachment?.sourceRGBBlendFactor = .sourceAlpha
        attachment?.destinationRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    func attach(view: MTKView) {
        self.view = view
    }

    func configureVideoFill(url: URL, id: String) {
        videoFillURLs[id] = url
        if id.caseInsensitiveCompare("explosions-2min.m4v") == .orderedSame {
            explosionURL = url
        }
        if id == videoFillSource { updateVideoFillPlayback() }
    }

    private var activeVideoFillPlayer: VideoFillPlayer? {
        videoFillPlayers[videoFillSource]
    }

    private func updateVideoFillPlayback() {
        if videoFillEnabled,
           videoFillPlayers[videoFillSource] == nil,
           let url = videoFillURLs[videoFillSource] {
            videoFillPlayers[videoFillSource] = VideoFillPlayer(url: url)
        }
        for (id, player) in videoFillPlayers {
            player.setActive(videoFillEnabled && id == videoFillSource, rate: videoPlaybackRate)
        }
    }

    func updatePose(_ pose: BodyPose?) {
        lock.lock()
        let now = CACurrentMediaTime()
        if clapExplosionsEnabled, let pose, pose.handCenters.count == 2 {
            lastHandsSeenAt = now
            let first = pose.handCenters[0]
            let second = pose.handCenters[1]
            let separation = simd_length(SIMD2(
                (first.x - second.x) * pose.sourceAspect,
                first.y - second.y
            ))
            if separation < 0.12, !handsTouching, now - lastClapAt > 0.3 {
                pendingClaps.append((first + second) * 0.5)
                handsTouching = true
                lastClapAt = now
            } else if separation > 0.18 {
                handsTouching = false
            }
        } else if now - lastHandsSeenAt > 0.35 {
            handsTouching = false
        }
        if let pose, let previous = latestPose, poseUpdatedAt > 0 {
            let delta = Float(max(0.001, now - poseUpdatedAt))
            var nextVelocities: [PoseJoint: SIMD2<Float>] = [:]
            for (joint, point) in pose.points {
                guard let previousPoint = previous.points[joint] else { continue }
                let measured = (point.position - previousPoint.position) / delta
                nextVelocities[joint] = (poseVelocities[joint] ?? measured) * 0.45 + measured * 0.55
            }
            poseVelocities = nextVelocities
        } else {
            poseVelocities.removeAll(keepingCapacity: true)
        }
        latestPose = pose
        poseUpdatedAt = now
        lock.unlock()
    }

    func clearPose() {
        lock.lock()
        latestPose = nil
        poseUpdatedAt = 0
        poseVelocities.removeAll(keepingCapacity: true)
        pendingClaps.removeAll()
        handsTouching = false
        lastHandsSeenAt = 0
        lock.unlock()
        particles.removeAll(keepingCapacity: true)
        lastParticleUpdate = 0
        particleEmissionCarry = 0
    }

    func submit(result: MattingResult, completion: @escaping (Double) -> Void) {
        let submittedAt = CACurrentMediaTime()
        let borderEmitters = particlesEnabled && particleSpawnSource == .shapeBorder
            ? sampleParticleBorder(from: result.alpha, threshold: particleBorderThreshold)
            : []
        lock.lock()
        pending = PendingFrame(result: result, submittedAt: submittedAt, completion: completion)
        particleBorderEmitters = borderEmitters
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.view?.setNeedsDisplay(self?.view?.bounds ?? .zero) }
    }

    func captureNextFrame(id: UUID, completion: @escaping (Data?) -> Void) {
        lock.lock()
        pendingFrameCapture = FrameCaptureRequest(id: id, completion: completion)
        lock.unlock()
    }

    func cancelFrameCapture(id: UUID) {
        lock.lock()
        if pendingFrameCapture?.id == id { pendingFrameCapture = nil }
        lock.unlock()
    }

    func clearTrailHistory() {
        lock.lock()
        snapshotPool.append(contentsOf: trailFrames.map {
            SignalSnapshotTextures(color: $0.color, alpha: $0.alpha)
        })
        if snapshotPool.count > 17 { snapshotPool.removeFirst(snapshotPool.count - 17) }
        trailFrames.removeAll(keepingCapacity: true)
        lastSnapshotTime = 0
        lock.unlock()
    }

    func clearSampleHistory() {
        sampleHistories.removeAll()
        sampleHistoryIDs.removeAll()
    }

    func draw(in view: MTKView) {
        lock.lock()
        let frame = pending
        pending = nil
        let now = CACurrentMediaTime()
        let expiredCount = trailFrames.prefix {
            now - $0.capturedAt > trailLifetime
        }.count
        if expiredCount > 0 {
            snapshotPool.append(contentsOf: trailFrames.prefix(expiredCount).map {
                SignalSnapshotTextures(color: $0.color, alpha: $0.alpha)
            })
            trailFrames.removeFirst(expiredCount)
        }
        if snapshotPool.count > 17 { snapshotPool.removeFirst(snapshotPool.count - 17) }
        // Only build the trail layer list when the trail actually composites;
        // otherwise this filter + array allocation ran every frame for nothing.
        let history: [TrailFrame]
        if clonesEnabled && displayMode.rawValue >= DisplayMode.foreground.rawValue {
            let availableHistory = trailFrames.filter { $0.capturedAt < (frame?.submittedAt ?? 0) - 0.001 }
            history = Array(availableHistory.suffix(max(0, min(cloneCount, 16))))
        } else {
            history = []
        }
        let shouldCaptureSignal = clonesEnabled
            && displayMode.rawValue >= DisplayMode.foreground.rawValue
            && (lastSnapshotTime == 0 || now - lastSnapshotTime >= trailSnapshotInterval)
        if shouldCaptureSignal { lastSnapshotTime = now }
        let pose = now - poseUpdatedAt <= 0.6 ? latestPose : nil
        let currentPoseVelocities = poseVelocities
        let currentParticleBorderEmitters = particleBorderEmitters
        lock.unlock()

        // Model outputs arrive in fresh IOSurfaces. Without explicitly flushing
        // the Core Video texture cache, it can retain a wrapper for every frame
        // indefinitely (thousands of multi-megabyte surfaces within minutes).
        // Active Metal command buffers retain the textures they still need, so
        // evicting unused cache entries here is safe and bounds resident memory.
        CVMetalTextureCacheFlush(textureCache, 0)
        guard let frame,
              let drawable = view.currentDrawable,
              let sourceTexture = makeTexture(from: frame.result.source, format: .bgra8Unorm),
              let alphaTexture = makeAlphaTexture(from: frame.result.alpha),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        lock.lock()
        let claps = pendingClaps
        pendingClaps.removeAll(keepingCapacity: true)
        lock.unlock()

        if clapExplosionsEnabled, let explosionURL, !ExplosionSegment.clips.isEmpty {
            for contact in claps {
                if explosions.count >= 8 {
                    explosions.removeFirst().stop()
                }
                let segment = ExplosionSegment.clips[nextExplosionSegment % ExplosionSegment.clips.count]
                nextExplosionSegment += 1
                guard segment.startSeconds >= 0, segment.durationSeconds > 0 else { continue }
                explosions.append(ClapExplosionPlayer(url: explosionURL, segment: segment, position: contact))
            }
        }
        explosions.removeAll { explosion in
            guard let startedAt = explosion.startedAt else { return false }
            if now - startedAt >= explosion.duration {
                explosion.stop()
                return true
            }
            return false
        }

        let start = CACurrentMediaTime()
        let foregroundTexture = frame.result.foreground.flatMap { makeTexture(from: $0, format: .bgra8Unorm) }
        let colorTexture = displayMode == .original ? sourceTexture : (foregroundTexture ?? sourceTexture)
        let videoTexture = videoFillEnabled
            ? activeVideoFillPlayer?.currentPixelBuffer(hostTime: now).flatMap { makeTexture(from: $0, format: .bgra8Unorm) }
            : nil
        let params = ShaderParams(
            mode: UInt32(displayMode.rawValue),
            background: UInt32(background.rawValue),
            threshold: threshold,
            edgeSoftness: edgeSoftness,
            alphaGain: alphaGain,
            sourceAspect: Float(colorTexture.width) / Float(colorTexture.height),
            viewAspect: Float(drawable.texture.width) / Float(drawable.texture.height),
            gradientEnabled: gradientEnabled ? 1 : 0,
            gradientStyle: UInt32(gradientStyle.rawValue),
            gradientOpacity: gradientOpacity,
            gradientAngle: gradientAngleDegrees * .pi / 180,
            cloneEnabled: clonesEnabled ? 1 : 0,
            cloneCount: UInt32(clamping: cloneCount),
            cloneRotation: cloneRotationDegrees * .pi / 180,
            cloneScaleStep: cloneScaleStep,
            cloneTranslation: cloneTranslation,
            cloneOpacity: cloneOpacity,
            cloneDecay: cloneDecay,
            trailBlendMode: UInt32(trailBlendMode.rawValue),
            mirrorOutput: mirrorOutput ? 1 : 0,
            liquidEnabled: liquidEnabled ? 1 : 0,
            liquidStrength: liquidStrength,
            liquidScale: liquidScale,
            liquidSpeed: liquidSpeed,
            time: Float(now.truncatingRemainder(dividingBy: 1_000)),
            videoFillEnabled: videoTexture == nil ? 0 : 1,
            videoFillOpacity: videoFillOpacity,
            videoAspect: videoTexture.map { Float($0.width) / Float($0.height) } ?? 1,
            videoScale: videoFillScale,
            gradientOrder: effectOrderValue(.gradientOverlay),
            liquidOrder: effectOrderValue(.liquidDistortion),
            videoOrder: effectOrderValue(.liveVideoFill),
            linesOrder: effectOrderValue(.lines),
            particleOrder: effectOrderValue(.particles),
            historicalOrder: effectOrderValue(.historicalTrail),
            processingLimitOrder: UInt32.max,
            particleShape: particleShape.rawValue,
            subjectVisible: linesEnabled && linesGeometryOnly ? 0 : 1,
            linesBlendMode: linesBlendMode.rawValue,
            gradientBlendMode: gradientBlendMode.rawValue,
            videoBlendMode: videoBlendMode.rawValue,
            liquidBlendMode: liquidBlendMode.rawValue,
            particleBlendMode: particleBlendMode.rawValue
        )

        encodePass(
            pipeline: basePipeline,
            source: colorTexture,
            alpha: alphaTexture,
            output: drawable.texture,
            video: nil,
            params: params,
            commandBuffer: commandBuffer
        )

        let skeletonVertices = skeletonEnabled
            ? makeSkeletonVertices(pose: pose, viewAspect: params.viewAspect)
            : []
        let linesVertices = linesEnabled
            ? makeLinesVertices(
                pose: pose,
                viewSize: SIMD2(Float(drawable.texture.width), Float(drawable.texture.height))
            )
            : []
        let particleVertices = particlesEnabled
            ? updateParticles(
                pose: pose,
                poseVelocities: currentPoseVelocities,
                borderEmitters: currentParticleBorderEmitters,
                sourceAspect: Float(CVPixelBufferGetWidth(frame.result.alpha))
                    / Float(CVPixelBufferGetHeight(frame.result.alpha)),
                viewAspect: params.viewAspect,
                now: now,
                processingLimitOrder: UInt32.max
            )
            : []
        // Rebuild the upstream (pre-trail) particle list only when liquid
        // distortion treats it differently; otherwise it is identical to the
        // full list and can be reused without a second pass over every particle.
        let upstreamParticleVertices: [OverlayVertex]
        if particlesEnabled,
           liquidAffectsParticles(before: params.historicalOrder)
            != liquidAffectsParticles(before: UInt32.max) {
            upstreamParticleVertices = makeParticleVertices(
                viewAspect: params.viewAspect,
                now: now,
                processingLimitOrder: params.historicalOrder
            )
        } else {
            upstreamParticleVertices = particleVertices
        }

        if shouldCaptureSignal, let mask = signalMask(width: drawable.texture.width, height: drawable.texture.height) {
            var upstreamParams = params
            upstreamParams.processingLimitOrder = params.historicalOrder
            if params.gradientOrder > params.historicalOrder { upstreamParams.gradientEnabled = 0 }
            if params.videoOrder > params.historicalOrder { upstreamParams.videoFillEnabled = 0 }
            if params.liquidOrder > params.historicalOrder { upstreamParams.liquidEnabled = 0 }

            encodePass(
                pipeline: subjectPipeline,
                source: colorTexture,
                alpha: alphaTexture,
                output: drawable.texture,
                video: videoTexture ?? colorTexture,
                params: upstreamParams,
                commandBuffer: commandBuffer
            )
            encodeSignalMask(
                alpha: alphaTexture,
                output: mask,
                params: upstreamParams,
                commandBuffer: commandBuffer
            )
            encodePoseOverlays(
                skeletonVertices: params.historicalOrder > effectOrderValue(.skeleton) ? skeletonVertices : [],
                linesVertices: params.historicalOrder > params.linesOrder ? linesVertices : [],
                particleVertices: params.historicalOrder > params.particleOrder ? upstreamParticleVertices : [],
                output: drawable.texture,
                mask: mask,
                params: upstreamParams,
                video: videoTexture ?? colorTexture,
                commandBuffer: commandBuffer
            )
            captureSignalSnapshot(
                source: drawable.texture,
                mask: mask,
                capturedAt: now,
                commandBuffer: commandBuffer
            )
        }

        if displayMode.rawValue >= DisplayMode.foreground.rawValue && clonesEnabled {
            for (index, snapshot) in history.enumerated() {
                let amount = Float(history.count - index)
                let ageFade = Float(max(0, 1 - (now - snapshot.capturedAt) / trailLifetime))
                var layer = TrailLayerParams(
                    amount: amount,
                    opacity: cloneOpacity * pow(cloneDecay, amount - 1) * ageFade
                )
                encodePass(
                    pipeline: trailPipeline,
                    source: snapshot.color,
                    alpha: snapshot.alpha,
                    output: drawable.texture,
                    video: videoTexture ?? snapshot.color,
                    params: params,
                    trailLayer: &layer,
                    commandBuffer: commandBuffer
                )
            }
        }

        if displayMode.rawValue >= DisplayMode.foreground.rawValue {
            encodePass(
                pipeline: subjectPipeline,
                source: colorTexture,
                alpha: alphaTexture,
                output: drawable.texture,
                video: videoTexture ?? colorTexture,
                params: params,
                commandBuffer: commandBuffer
            )
        }

        if displayMode.rawValue >= DisplayMode.foreground.rawValue,
           !skeletonVertices.isEmpty || !linesVertices.isEmpty || !particleVertices.isEmpty {
            encodePoseOverlays(
                skeletonVertices: skeletonVertices,
                linesVertices: linesVertices,
                particleVertices: particleVertices,
                output: drawable.texture,
                mask: nil,
                params: params,
                video: videoTexture ?? colorTexture,
                commandBuffer: commandBuffer
            )
        }

        if displayMode.rawValue >= DisplayMode.foreground.rawValue && lineSamplerEnabled {
            encodeLineSampler(output: drawable.texture, commandBuffer: commandBuffer)
        }

        if clapExplosionsEnabled {
            encodeClapExplosions(
                output: drawable.texture,
                sourceAspect: params.sourceAspect,
                viewAspect: params.viewAspect,
                now: now,
                commandBuffer: commandBuffer
            )
        }

        lock.lock()
        let frameCapture = pendingFrameCapture
        pendingFrameCapture = nil
        lock.unlock()
        if let frameCapture {
            if let imageBuffer = encodeThumbnailCapture(
                source: drawable.texture, commandBuffer: commandBuffer
            ) {
                commandBuffer.addCompletedHandler { [imageBuffer] completed in
                    guard completed.status == .completed else {
                        frameCapture.completion(nil)
                        return
                    }
                    frameCapture.completion(Self.jpegData(from: imageBuffer))
                }
            } else {
                frameCapture.completion(nil)
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { commandBuffer in
            if commandBuffer.status == .error {
                let detail = commandBuffer.error?.localizedDescription ?? "Unknown Metal error"
                Self.logger.error("Metal command failed: \(detail, privacy: .public)")
            }
            frame.completion((CACurrentMediaTime() - start) * 1_000)
        }
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func encodeThumbnailCapture(
        source: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> ThumbnailBuffer? {
        let scale = min(1, 640.0 / Double(source.width), 360.0 / Double(source.height))
        let width = max(1, Int((Double(source.width) * scale).rounded()))
        let height = max(1, Int((Double(source.height) * scale).rounded()))
        let bytesPerRow = width * 4
        guard let buffer = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        var size = SIMD2<UInt32>(UInt32(width), UInt32(height))
        encoder.setComputePipelineState(thumbnailPipeline)
        encoder.setTexture(source, index: 0)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.setBytes(&size, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 1)
        let threadWidth = thumbnailPipeline.threadExecutionWidth
        let threadHeight = max(1, thumbnailPipeline.maxTotalThreadsPerThreadgroup / threadWidth)
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1)
        )
        encoder.endEncoding()
        return ThumbnailBuffer(buffer: buffer, width: width, height: height, bytesPerRow: bytesPerRow)
    }

    private static func jpegData(from thumbnail: ThumbnailBuffer) -> Data? {
        let bytes = Data(bytes: thumbnail.buffer.contents(), count: thumbnail.bytesPerRow * thumbnail.height)
        guard let provider = CGDataProvider(data: bytes as CFData),
              let image = CGImage(
                width: thumbnail.width,
                height: thumbnail.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: thumbnail.bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.union(
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(
            using: .jpeg, properties: [.compressionFactor: 0.82]
        )
    }

    private func encodeLineSampler(output: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let lines = Array(sampleLines.prefix(16)).filter {
            hypot($0.ax - $0.bx, $0.ay - $0.by) > 0.005
        }
        let ids = Set(lines.map(\.id))
        if ids != sampleHistoryIDs {
            sampleHistories = sampleHistories.filter { ids.contains($0.key) }
            sampleHistoryIDs = ids
        }
        guard !lines.isEmpty else { return }

        if sampleSourceTexture?.width != output.width || sampleSourceTexture?.height != output.height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: output.width, height: output.height, mipmapped: false
            )
            descriptor.storageMode = .private
            descriptor.usage = [.shaderRead]
            sampleSourceTexture = device.makeTexture(descriptor: descriptor)
        }
        guard let source = sampleSourceTexture,
              let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: output, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: .init(x: 0, y: 0, z: 0),
                  sourceSize: .init(width: output.width, height: output.height, depth: 1),
                  to: source, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: .init(x: 0, y: 0, z: 0))
        blit.endEncoding()

        encodeSampleOccupancy(lines: lines, source: source, commandBuffer: commandBuffer)

        // Capture all lines before compositing any of them, so they sample the same live input.
        var captures: [(MTLTexture, SampleParams)] = []
        for line in lines {
            if sampleHistories[line.id].map({ !$0.line.sameGeometry(as: line) }) ?? true {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: 512, height: 512, mipmapped: false
                )
                descriptor.storageMode = .private
                descriptor.usage = [.shaderRead, .shaderWrite]
                guard let texture = device.makeTexture(descriptor: descriptor) else { continue }
                sampleHistories[line.id] = SampleHistory(line: line, texture: texture, newestRow: -1, count: 0)
            }
            guard var state = sampleHistories[line.id] else { continue }
            state.newestRow = (state.newestRow + 1) % state.texture.height
            state.count = min(state.count + 1, state.texture.height)
            sampleHistories[line.id] = state
            let direction: UInt32 = switch sampleDirection {
            case .both: 0
            case .left: 1
            case .right: 2
            }
            let params = SampleParams(
                endpoints: SIMD4(Float(line.ax), Float(line.ay), Float(line.bx), Float(line.by)),
                settings: SIMD4(sampleSpeed, Float(sampleCount), sampleThickness, sampleOpacity),
                history: SIMD4(sampleFade, sampleFrameStep, Float(state.newestRow), Float(state.count)),
                options: SIMD4(direction, sampleBlendMode.rawValue, 0, 0)
            )
            if let encoder = commandBuffer.makeComputeCommandEncoder() {
                var params = params
                encoder.setComputePipelineState(sampleCapturePipeline)
                encoder.setTexture(source, index: 0)
                encoder.setTexture(state.texture, index: 1)
                encoder.setBytes(&params, length: MemoryLayout<SampleParams>.stride, index: 0)
                encoder.dispatchThreads(MTLSize(width: state.texture.width, height: 1, depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: sampleCapturePipeline.threadExecutionWidth,
                                                                      height: 1, depth: 1))
                encoder.endEncoding()
                captures.append((state.texture, params))
            }
        }
        for (history, value) in captures {
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { continue }
            var params = value
            encoder.setComputePipelineState(sampleCompositePipeline)
            encoder.setTexture(history, index: 0)
            encoder.setTexture(output, index: 1)
            encoder.setBytes(&params, length: MemoryLayout<SampleParams>.stride, index: 0)
            dispatch(pipeline: sampleCompositePipeline, output: output, encoder: encoder)
            encoder.endEncoding()
        }
    }

    private func encodeSampleOccupancy(lines: [SampleLine], source: MTLTexture,
                                       commandBuffer: MTLCommandBuffer) {
        guard lines.contains(where: \.midiEnabled), let lineMIDI else { return }
        occupancyLock.lock()
        let slot = occupancyBusy.indices.first(where: { !occupancyBusy[$0] && $0 < occupancyBuffers.count })
        if let slot { occupancyBusy[slot] = true }
        occupancyLock.unlock()
        guard let slot else { return }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            occupancyLock.lock()
            occupancyBusy[slot] = false
            occupancyLock.unlock()
            return
        }
        var parameters = [OccupancyLine](repeating: OccupancyLine(), count: 16)
        for (index, line) in lines.enumerated() {
            parameters[index] = OccupancyLine(
                endpoints: SIMD4(Float(line.ax), Float(line.ay), Float(line.bx), Float(line.by)),
                sections: UInt32(line.scale.offsets.count), thickness: sampleThickness,
                enabled: line.midiEnabled ? 1 : 0, padding: 0)
        }
        let ids = lines.map(\.id)
        let buffer = occupancyBuffers[slot]
        encoder.setComputePipelineState(sampleOccupancyPipeline)
        encoder.setTexture(source, index: 0)
        encoder.setBytes(parameters, length: parameters.count * MemoryLayout<OccupancyLine>.stride, index: 0)
        encoder.setBuffer(buffer, offset: 0, index: 1)
        encoder.dispatchThreads(MTLSize(width: 16, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.addCompletedHandler { [weak self] completed in
            if completed.status == .completed {
                let values = buffer.contents().bindMemory(to: UInt16.self, capacity: 16)
                lineMIDI.updateOccupancy(Dictionary(uniqueKeysWithValues:
                    ids.enumerated().map { ($0.element, values[$0.offset]) }))
            }
            self?.occupancyLock.lock()
            self?.occupancyBusy[slot] = false
            self?.occupancyLock.unlock()
        }
    }

    private func encodePass(
        pipeline: MTLComputePipelineState,
        source: MTLTexture,
        alpha: MTLTexture,
        output: MTLTexture,
        video: MTLTexture?,
        params: ShaderParams,
        trailLayer: UnsafeMutablePointer<TrailLayerParams>? = nil,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        var params = params
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(alpha, index: 1)
        encoder.setTexture(output, index: 2)
        encoder.setTexture(video, index: 3)
        encoder.setBytes(&params, length: MemoryLayout<ShaderParams>.stride, index: 0)
        if let trailLayer {
            encoder.setBytes(trailLayer, length: MemoryLayout<TrailLayerParams>.stride, index: 1)
        }
        let width = pipeline.threadExecutionWidth
        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
        encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
        )
        encoder.endEncoding()
    }

    private func signalMask(width: Int, height: Int) -> MTLTexture? {
        if let signalMaskTexture,
           signalMaskTexture.width == width,
           signalMaskTexture.height == height {
            return signalMaskTexture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        signalMaskTexture = device.makeTexture(descriptor: descriptor)
        return signalMaskTexture
    }

    private func encodeSignalMask(
        alpha: MTLTexture,
        output: MTLTexture,
        params: ShaderParams,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        var params = params
        encoder.setComputePipelineState(signalMaskPipeline)
        encoder.setTexture(alpha, index: 0)
        encoder.setTexture(output, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<ShaderParams>.stride, index: 0)
        dispatch(pipeline: signalMaskPipeline, output: output, encoder: encoder)
        encoder.endEncoding()
    }

    private func captureSignalSnapshot(
        source: MTLTexture,
        mask: MTLTexture,
        capturedAt: CFTimeInterval,
        commandBuffer: MTLCommandBuffer
    ) {
        let width = max(1, source.width / 2)
        let height = max(1, source.height / 2)
        guard let textures = acquireSnapshotTextures(width: width, height: height),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(snapshotPipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(mask, index: 1)
        encoder.setTexture(textures.color, index: 2)
        encoder.setTexture(textures.alpha, index: 3)
        dispatch(pipeline: snapshotPipeline, output: textures.color, encoder: encoder)
        encoder.endEncoding()

        lock.lock()
        trailFrames.append(TrailFrame(
            color: textures.color,
            alpha: textures.alpha,
            video: nil,
            capturedAt: capturedAt
        ))
        lock.unlock()
    }

    private func acquireSnapshotTextures(width: Int, height: Int) -> SignalSnapshotTextures? {
        lock.lock()
        if trailFrames.count >= 17 {
            let recycled = trailFrames.removeFirst()
            lock.unlock()
            if recycled.color.width == width, recycled.color.height == height {
                return SignalSnapshotTextures(color: recycled.color, alpha: recycled.alpha)
            }
        } else if let index = snapshotPool.firstIndex(where: {
            $0.color.width == width && $0.color.height == height
        }) {
            let recycled = snapshotPool.remove(at: index)
            lock.unlock()
            return recycled
        } else {
            lock.unlock()
        }

        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        colorDescriptor.storageMode = .private
        colorDescriptor.usage = [.shaderRead, .shaderWrite]
        let alphaDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        alphaDescriptor.storageMode = .private
        alphaDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let color = device.makeTexture(descriptor: colorDescriptor),
              let alpha = device.makeTexture(descriptor: alphaDescriptor) else { return nil }
        return SignalSnapshotTextures(color: color, alpha: alpha)
    }

    private func dispatch(
        pipeline: MTLComputePipelineState,
        output: MTLTexture,
        encoder: MTLComputeCommandEncoder
    ) {
        let width = pipeline.threadExecutionWidth
        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
        encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
        )
    }

    private func encodePoseOverlays(
        skeletonVertices: [OverlayVertex],
        linesVertices: [OverlayVertex],
        particleVertices: [OverlayVertex],
        output: MTLTexture,
        mask: MTLTexture?,
        params: ShaderParams,
        video: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        guard !skeletonVertices.isEmpty || !linesVertices.isEmpty || !particleVertices.isEmpty else { return }

        if !particleVertices.isEmpty {
            if particleColorBuffer == nil {
                particleColorBuffer = device.makeBuffer(
                    length: 2_000 * MemoryLayout<SIMD4<Float>>.stride,
                    options: .storageModePrivate
                )
            }
            if particleColorSource == .atSpawn && !pendingParticleColorCaptures.isEmpty {
                _ = prepareParticleColorSource(output: output, commandBuffer: commandBuffer)
            }
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        if !skeletonVertices.isEmpty {
            encoder.setRenderPipelineState(skeletonPipelines[Int(skeletonBlendMode.rawValue)])
            var blendMode = skeletonBlendMode.rawValue
            encoder.setFragmentBytes(&blendMode, length: MemoryLayout<UInt32>.stride, index: 1)
            if let buffer = device.makeBuffer(
                bytes: skeletonVertices,
                length: skeletonVertices.count * MemoryLayout<OverlayVertex>.stride
            ) {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: skeletonVertices.count)
            }
        }
        if !linesVertices.isEmpty {
            encoder.setRenderPipelineState(linesPipelines[Int(linesBlendMode.rawValue)])
            var params = params
            encoder.setFragmentBytes(&params, length: MemoryLayout<ShaderParams>.stride, index: 0)
            encoder.setFragmentTexture(video, index: 0)
            if let buffer = device.makeBuffer(
                bytes: linesVertices,
                length: linesVertices.count * MemoryLayout<OverlayVertex>.stride
            ) {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: linesVertices.count)
            }
        }
        if !particleVertices.isEmpty, let particleColorBuffer {
            encoder.setRenderPipelineState(particlePipelines[Int(particleBlendMode.rawValue)])
            var params = params
            var colorSource: UInt32 = particleColorSource == .atSpawn ? 1 : 0
            encoder.setFragmentBytes(&params, length: MemoryLayout<ShaderParams>.stride, index: 0)
            encoder.setFragmentBuffer(particleColorBuffer, offset: 0, index: 1)
            encoder.setFragmentBytes(&colorSource, length: MemoryLayout<UInt32>.stride, index: 2)
            encoder.setFragmentTexture(video, index: 0)
            if let buffer = device.makeBuffer(
                bytes: particleVertices,
                length: particleVertices.count * MemoryLayout<OverlayVertex>.stride
            ) {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleVertices.count)
            }
        }
        encoder.endEncoding()

        guard let mask else { return }
        let maskPass = MTLRenderPassDescriptor()
        maskPass.colorAttachments[0].texture = mask
        maskPass.colorAttachments[0].loadAction = .load
        maskPass.colorAttachments[0].storeAction = .store
        guard let maskEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: maskPass) else { return }
        if !skeletonVertices.isEmpty,
           let buffer = device.makeBuffer(
               bytes: skeletonVertices,
               length: skeletonVertices.count * MemoryLayout<OverlayVertex>.stride
           ) {
            maskEncoder.setRenderPipelineState(skeletonMaskPipeline)
            maskEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
            maskEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: skeletonVertices.count)
        }
        if !linesVertices.isEmpty,
           let buffer = device.makeBuffer(
               bytes: linesVertices,
               length: linesVertices.count * MemoryLayout<OverlayVertex>.stride
           ) {
            maskEncoder.setRenderPipelineState(skeletonMaskPipeline)
            maskEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
            maskEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: linesVertices.count)
        }
        if !particleVertices.isEmpty,
           let buffer = device.makeBuffer(
               bytes: particleVertices,
               length: particleVertices.count * MemoryLayout<OverlayVertex>.stride
           ) {
            maskEncoder.setRenderPipelineState(particleMaskPipeline)
            var params = params
            maskEncoder.setFragmentBytes(&params, length: MemoryLayout<ShaderParams>.stride, index: 0)
            maskEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
            maskEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleVertices.count)
        }
        maskEncoder.endEncoding()
    }

    private func prepareParticleColorSource(
        output: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        if particleColorTexture?.width != output.width || particleColorTexture?.height != output.height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: output.width, height: output.height, mipmapped: false
            )
            descriptor.storageMode = .private
            descriptor.usage = .shaderRead
            particleColorTexture = device.makeTexture(descriptor: descriptor)
        }
        guard let texture = particleColorTexture,
              let particleColorBuffer,
              let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: output, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: .init(x: 0, y: 0, z: 0),
                  sourceSize: .init(width: output.width, height: output.height, depth: 1),
                  to: texture, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: .init(x: 0, y: 0, z: 0))
        blit.endEncoding()

        if !pendingParticleColorCaptures.isEmpty {
            let captures = pendingParticleColorCaptures
            guard let buffer = device.makeBuffer(
                bytes: captures,
                length: captures.count * MemoryLayout<ParticleColorCapture>.stride,
                options: .storageModeShared
            ), let encoder = commandBuffer.makeComputeCommandEncoder() else { return texture }
            var count = UInt32(captures.count)
            encoder.setComputePipelineState(particleColorCapturePipeline)
            encoder.setTexture(texture, index: 0)
            encoder.setBuffer(buffer, offset: 0, index: 0)
            encoder.setBuffer(particleColorBuffer, offset: 0, index: 1)
            encoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 2)
            encoder.dispatchThreads(
                MTLSize(width: captures.count, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: particleColorCapturePipeline.threadExecutionWidth,
                                              height: 1, depth: 1)
            )
            encoder.endEncoding()
            pendingParticleColorCaptures.removeAll(keepingCapacity: true)
        }
        return texture
    }

    private func encodeClapExplosions(
        output: MTLTexture,
        sourceAspect: Float,
        viewAspect: Float,
        now: CFTimeInterval,
        commandBuffer: MTLCommandBuffer
    ) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(explosionPipelines[Int(clapExplosionBlendMode.rawValue)])
        var blendMode = clapExplosionBlendMode.rawValue
        encoder.setFragmentBytes(&blendMode, length: MemoryLayout<UInt32>.stride, index: 1)
        for explosion in explosions {
            guard let startedAt = explosion.startedAt,
                  let pixelBuffer = explosion.pixelBuffer(hostTime: now),
                  let texture = makeTexture(from: pixelBuffer, format: .bgra8Unorm) else { continue }
            let center = viewPosition(explosion.position, sourceAspect: sourceAspect, viewAspect: viewAspect)
            let halfHeight = max(0.01, clapExplosionSize) * 0.5
            let halfWidth = halfHeight * Float(texture.width) / Float(texture.height) / viewAspect
            let x0 = (center.x - halfWidth) * 2 - 1
            let x1 = (center.x + halfWidth) * 2 - 1
            let y0 = 1 - (center.y - halfHeight) * 2
            let y1 = 1 - (center.y + halfHeight) * 2
            let vertices: [ExplosionVertex] = [
                .init(position: SIMD2(x0, y0), uv: SIMD2(0, 0)),
                .init(position: SIMD2(x1, y0), uv: SIMD2(1, 0)),
                .init(position: SIMD2(x0, y1), uv: SIMD2(0, 1)),
                .init(position: SIMD2(x1, y0), uv: SIMD2(1, 0)),
                .init(position: SIMD2(x1, y1), uv: SIMD2(1, 1)),
                .init(position: SIMD2(x0, y1), uv: SIMD2(0, 1))
            ]
            var opacity = clapExplosionOpacity * Float(min(1, max(0, (explosion.duration - (now - startedAt)) / 0.35)))
            encoder.setFragmentBytes(&opacity, length: MemoryLayout<Float>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            if let buffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<ExplosionVertex>.stride) {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            }
        }
        encoder.endEncoding()
    }

    private func makeSkeletonVertices(pose: BodyPose?, viewAspect: Float) -> [OverlayVertex] {
        guard let pose else { return [] }
        let bones: [(PoseJoint, PoseJoint)] = [
            (.leftEar, .leftEye), (.leftEye, .nose), (.nose, .rightEye), (.rightEye, .rightEar),
            (.nose, .neck),
            (.neck, .leftShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
            (.neck, .rightShoulder), (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
            (.neck, .root), (.root, .leftHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
            (.root, .rightHip), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
        ]
        let color = SIMD4<Float>(1, 1, 1, skeletonOpacity)
        var vertices: [OverlayVertex] = []
        vertices.reserveCapacity(bones.count * 2)
        for (startJoint, endJoint) in bones {
            guard let start = viewPosition(startJoint, in: pose, viewAspect: viewAspect),
                  let end = viewPosition(endJoint, in: pose, viewAspect: viewAspect) else { continue }
            vertices.append(OverlayVertex(position: clipPosition(start), color: color, pointSize: 1))
            vertices.append(OverlayVertex(position: clipPosition(end), color: color, pointSize: 1))
        }
        return vertices
    }

    private func makeLinesVertices(pose: BodyPose?, viewSize: SIMD2<Float>) -> [OverlayVertex] {
        guard let pose else { return [] }
        let viewAspect = viewSize.x / max(1, viewSize.y)
        let positions = PoseJoint.allCases.compactMap { joint -> SIMD2<Float>? in
            guard let point = pose.points[joint], point.confidence >= linesConfidence else { return nil }
            return viewPosition(point.position, sourceAspect: pose.sourceAspect, viewAspect: viewAspect)
        }
        guard positions.count > 1 else { return [] }

        let neighborCount = min(max(1, linesConnections), positions.count - 1)
        let color = SIMD4<Float>(1, 1, 1, linesOpacity)
        var edges = Set<UInt64>()
        var vertices: [OverlayVertex] = []
        vertices.reserveCapacity(positions.count * neighborCount * 6)

        func appendQuad(from start: SIMD2<Float>, to end: SIMD2<Float>) {
            let pixelDelta = (end - start) * viewSize
            let length = simd_length(pixelDelta)
            guard length > 0.01 else { return }
            let normal = SIMD2(-pixelDelta.y, pixelDelta.x) / length
            let offset = normal * (max(1, linesThickness) * 0.5) / viewSize
            let startA = clipPosition(start + offset)
            let startB = clipPosition(start - offset)
            let endA = clipPosition(end + offset)
            let endB = clipPosition(end - offset)
            vertices.append(OverlayVertex(position: startA, color: color, pointSize: 1))
            vertices.append(OverlayVertex(position: startB, color: color, pointSize: 1))
            vertices.append(OverlayVertex(position: endA, color: color, pointSize: 1))
            vertices.append(OverlayVertex(position: endA, color: color, pointSize: 1))
            vertices.append(OverlayVertex(position: startB, color: color, pointSize: 1))
            vertices.append(OverlayVertex(position: endB, color: color, pointSize: 1))
        }

        for startIndex in positions.indices {
            let start = positions[startIndex]
            let nearest = positions.indices
                .filter { $0 != startIndex }
                .map { endIndex -> (index: Int, distance: Float) in
                    let delta = positions[endIndex] - start
                    let physicalDelta = SIMD2(delta.x * viewAspect, delta.y)
                    return (endIndex, simd_length_squared(physicalDelta))
                }
                .sorted { $0.distance < $1.distance }
                .prefix(neighborCount)

            for neighbor in nearest {
                let lower = min(startIndex, neighbor.index)
                let upper = max(startIndex, neighbor.index)
                let edge = (UInt64(lower) << 32) | UInt64(upper)
                guard edges.insert(edge).inserted else { continue }
                appendQuad(from: start, to: positions[neighbor.index])
            }
        }
        return vertices
    }

    private func updateParticles(
        pose: BodyPose?,
        poseVelocities: [PoseJoint: SIMD2<Float>],
        borderEmitters: [ParticleBorderEmitter],
        sourceAspect: Float,
        viewAspect: Float,
        now: CFTimeInterval,
        processingLimitOrder: UInt32
    ) -> [OverlayVertex] {
        guard particleSizeScale > 0 else {
            clearParticles()
            return []
        }
        let delta = lastParticleUpdate == 0 ? 1.0 / 30.0 : min(0.08, max(0, now - lastParticleUpdate))
        lastParticleUpdate = now
        let dt = Float(delta)

        for index in particles.indices {
            particles[index].age += dt
            particles[index].velocity.y += particleGravity * dt
            particles[index].velocity *= max(0, 1 - particleDrag * dt)
            particles[index].position += particles[index].velocity * dt
        }
        var expiredSlots: [UInt32] = []
        particles.removeAll { particle in
            if particle.age >= particle.lifetime {
                expiredSlots.append(particle.colorSlot)
                return true
            }
            return false
        }
        freeParticleColorSlots.append(contentsOf: expiredSlots)

        if particleSpawnSource == .limbs, let pose {
            let emitters = particleEmitters(
                pose: pose,
                poseVelocities: poseVelocities,
                viewAspect: viewAspect
            )
            particleEmissionCarry += max(0, particleRate) * dt
            let emissionCount = Int(particleEmissionCarry)
            particleEmissionCarry -= Float(emissionCount)
            if emissionCount > 0 {
                for (position, parent, movementSpeed, emitterVelocity) in emitters {
                    for _ in 0..<emissionCount {
                        var outward = position - parent
                        var physical = SIMD2<Float>(outward.x * viewAspect, outward.y)
                        let length = max(0.0001, simd_length(physical))
                        physical /= length
                        outward = SIMD2(physical.x / viewAspect, physical.y)
                        let spreadRadians = max(0, particleSpreadDegrees) * .pi / 180
                        let angle = randomSigned() * spreadRadians * 0.5
                        let cosine = cos(angle)
                        let sine = sin(angle)
                        physical = SIMD2(
                            physical.x * cosine - physical.y * sine,
                            physical.x * sine + physical.y * cosine
                        )
                        outward = SIMD2(physical.x / viewAspect, physical.y)
                        let speed = (0.08 + randomUnit() * 0.16) * max(0, particleSpeed)
                        let movementScale = 1 + min(3.5, movementSpeed * max(0, particleMotionSize))
                        appendParticle(
                            at: position,
                            outward: outward,
                            emitterVelocity: emitterVelocity,
                            speed: speed,
                            movementScale: movementScale
                        )
                    }
                }
            }
        } else if particleSpawnSource == .shapeBorder, !borderEmitters.isEmpty {
            particleEmissionCarry += max(0, particleRate) * dt
            let emissionCount = Int(particleEmissionCarry)
            particleEmissionCarry -= Float(emissionCount)
            for _ in 0..<emissionCount {
                let index = min(borderEmitters.count - 1, Int(randomUnit() * Float(borderEmitters.count)))
                let emitter = viewBorderEmitter(
                    borderEmitters[index],
                    sourceAspect: sourceAspect,
                    viewAspect: viewAspect
                )
                var physical = SIMD2(emitter.normal.x * viewAspect, emitter.normal.y)
                let angle = randomSigned() * max(0, particleSpreadDegrees) * .pi / 360
                physical = SIMD2(
                    physical.x * cos(angle) - physical.y * sin(angle),
                    physical.x * sin(angle) + physical.y * cos(angle)
                )
                let outward = SIMD2(physical.x / viewAspect, physical.y)
                let speed = (0.08 + randomUnit() * 0.16) * max(0, particleSpeed)
                appendParticle(
                    at: emitter.position,
                    outward: outward,
                    emitterVelocity: .zero,
                    speed: speed,
                    movementScale: 1
                )
            }
        }
        if particles.count > 2_000 {
            let removedCount = particles.count - 2_000
            freeParticleColorSlots.append(contentsOf: particles.prefix(removedCount).map(\.colorSlot))
            particles.removeFirst(removedCount)
        }

        return makeParticleVertices(
            viewAspect: viewAspect,
            now: now,
            processingLimitOrder: processingLimitOrder
        )
    }

    private func appendParticle(
        at position: SIMD2<Float>,
        outward: SIMD2<Float>,
        emitterVelocity: SIMD2<Float>,
        speed: Float,
        movementScale: Float
    ) {
        guard particles.count < 2_000 else { return }
        let slot: UInt32
        if let reusedSlot = freeParticleColorSlots.popLast() {
            slot = reusedSlot
        } else {
            guard nextParticleColorSlot < 2_000 else { return }
            slot = nextParticleColorSlot
            nextParticleColorSlot += 1
        }
        particles.append(Particle(
            position: position,
            velocity: outward * speed + emitterVelocity * max(0, particleMomentum),
            age: 0,
            lifetime: max(0.1, particleLifetime) * (0.75 + randomUnit() * 0.5),
            sizeFactor: movementScale * (0.65 + randomUnit() * 0.7),
            colorSlot: slot
        ))
        if particleColorSource == .atSpawn {
            pendingParticleColorCaptures.append(ParticleColorCapture(uv: position, slot: slot))
        }
    }

    private func clearParticles() {
        particles.removeAll(keepingCapacity: true)
        pendingParticleColorCaptures.removeAll(keepingCapacity: true)
        freeParticleColorSlots.removeAll(keepingCapacity: true)
        nextParticleColorSlot = 0
        particleEmissionCarry = 0
    }

    private func makeParticleVertices(
        viewAspect: Float,
        now: CFTimeInterval,
        processingLimitOrder: UInt32
    ) -> [OverlayVertex] {
        guard particleSizeScale > 0 else { return [] }
        return particles.map { particle in
            let fade = max(0, 1 - particle.age / particle.lifetime)
            let displayPosition = liquidAffectsParticles(before: processingLimitOrder)
                ? liquidDistortedPosition(particle.position, viewAspect: viewAspect, now: now)
                : particle.position
            return OverlayVertex(
                position: clipPosition(displayPosition),
                color: SIMD4<Float>(1, 1, 1, fade),
                pointSize: 6 * particleSizeScale * particle.sizeFactor
                    * (max(0, particleEndSize) + (1 - max(0, particleEndSize)) * fade),
                colorSlot: particle.colorSlot
            )
        }
    }

    private func particleEmitters(
        pose: BodyPose,
        poseVelocities: [PoseJoint: SIMD2<Float>],
        viewAspect: Float
    ) -> [(position: SIMD2<Float>, parent: SIMD2<Float>, movementSpeed: Float, velocity: SIMD2<Float>)] {
        var pairs: [(PoseJoint, PoseJoint)] = [
            (.leftAnkle, .leftKnee), (.rightAnkle, .rightKnee)
        ]
        let leftTips: [PoseJoint] = [.leftThumbTip, .leftIndexTip, .leftMiddleTip, .leftRingTip, .leftLittleTip]
        let rightTips: [PoseJoint] = [.rightThumbTip, .rightIndexTip, .rightMiddleTip, .rightRingTip, .rightLittleTip]
        let visibleLeftTips = leftTips.filter { pose.points[$0]?.confidence ?? 0 >= skeletonConfidence }
        let visibleRightTips = rightTips.filter { pose.points[$0]?.confidence ?? 0 >= skeletonConfidence }
        pairs += visibleLeftTips.isEmpty
            ? [(.leftWrist, .leftElbow)]
            : visibleLeftTips.map { ($0, .leftWrist) }
        pairs += visibleRightTips.isEmpty
            ? [(.rightWrist, .rightElbow)]
            : visibleRightTips.map { ($0, .rightWrist) }
        var emitters = pairs.compactMap {
            endpoint, parent -> (SIMD2<Float>, SIMD2<Float>, Float, SIMD2<Float>)? in
            guard let end = viewPosition(endpoint, in: pose, viewAspect: viewAspect),
                  let parent = viewPosition(parent, in: pose, viewAspect: viewAspect) else { return nil }
            return (
                end,
                parent,
                movementSpeed(of: endpoint, pose: pose, velocities: poseVelocities),
                viewVelocity(of: endpoint, pose: pose, velocities: poseVelocities, viewAspect: viewAspect)
            )
        }
        if let nose = pose.points[.nose],
           let leftEye = pose.points[.leftEye], let rightEye = pose.points[.rightEye],
           nose.confidence >= skeletonConfidence,
           leftEye.confidence >= skeletonConfidence, rightEye.confidence >= skeletonConfidence {
            let eyeCenter = (leftEye.position + rightEye.position) * 0.5
            let thirdEyeVision = eyeCenter + (eyeCenter - nose.position) * 0.30
            let thirdEye = viewPosition(thirdEyeVision, sourceAspect: pose.sourceAspect, viewAspect: viewAspect)
            let headParent = viewPosition(nose.position, sourceAspect: pose.sourceAspect, viewAspect: viewAspect)
            emitters.append((
                thirdEye,
                headParent,
                max(
                    movementSpeed(of: .leftEye, pose: pose, velocities: poseVelocities),
                    movementSpeed(of: .rightEye, pose: pose, velocities: poseVelocities)
                ),
                (
                    viewVelocity(of: .leftEye, pose: pose, velocities: poseVelocities, viewAspect: viewAspect)
                    + viewVelocity(of: .rightEye, pose: pose, velocities: poseVelocities, viewAspect: viewAspect)
                ) * 0.5
            ))
        }
        return emitters
    }

    private func movementSpeed(
        of joint: PoseJoint,
        pose: BodyPose,
        velocities: [PoseJoint: SIMD2<Float>]
    ) -> Float {
        guard let velocity = velocities[joint] else { return 0 }
        return simd_length(SIMD2(velocity.x * pose.sourceAspect, velocity.y))
    }

    private func viewVelocity(
        of joint: PoseJoint,
        pose: BodyPose,
        velocities: [PoseJoint: SIMD2<Float>],
        viewAspect: Float
    ) -> SIMD2<Float> {
        guard let sourceVelocity = velocities[joint] else { return .zero }
        var velocity = SIMD2(sourceVelocity.x, -sourceVelocity.y)
        if mirrorOutput { velocity.x = -velocity.x }
        if viewAspect > pose.sourceAspect {
            velocity.y /= pose.sourceAspect / viewAspect
        } else {
            velocity.x /= viewAspect / pose.sourceAspect
        }

        // Pose detections can occasionally jump. Clamp inherited velocity in
        // aspect-correct space so one bad frame cannot fling particles offscreen.
        var physical = SIMD2(velocity.x * viewAspect, velocity.y)
        let speed = simd_length(physical)
        if speed > 2.0 { physical *= 2.0 / speed }
        return SIMD2(physical.x / viewAspect, physical.y)
    }

    private func sampleParticleBorder(
        from buffer: CVPixelBuffer,
        threshold: Float
    ) -> [ParticleBorderEmitter] {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess,
              let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let cutoff = min(1, max(0, threshold))

        func alpha(_ x: Int, _ y: Int) -> Float {
            let clampedX = min(width - 1, max(0, x))
            let clampedY = min(height - 1, max(0, y))
            let row = baseAddress.advanced(by: clampedY * bytesPerRow)
            switch format {
            case kCVPixelFormatType_OneComponent8:
                return Float(row.assumingMemoryBound(to: UInt8.self)[clampedX]) / 255
            case kCVPixelFormatType_OneComponent16Half:
                let bits = row.assumingMemoryBound(to: UInt16.self)[clampedX]
                return Float(Float16(bitPattern: bits))
            case kCVPixelFormatType_OneComponent32Float:
                return row.assumingMemoryBound(to: Float.self)[clampedX]
            default:
                return 0
            }
        }

        guard format == kCVPixelFormatType_OneComponent8
                || format == kCVPixelFormatType_OneComponent16Half
                || format == kCVPixelFormatType_OneComponent32Float else { return [] }

        // About 160×90 samples even for the quality model: inexpensive enough
        // to run after inference while still resolving hands and separated people.
        let step = max(1, min(width / 160, height / 90))
        var emitters: [ParticleBorderEmitter] = []
        emitters.reserveCapacity(1_024)
        for y in stride(from: step / 2, to: height, by: step) {
            for x in stride(from: step / 2, to: width, by: step) {
                guard alpha(x, y) >= cutoff else { continue }
                let left = alpha(x - step, y)
                let right = alpha(x + step, y)
                let up = alpha(x, y - step)
                let down = alpha(x, y + step)
                guard min(left, right, up, down) < cutoff else { continue }

                var normal = SIMD2<Float>(left - right, up - down)
                let length = simd_length(normal)
                guard length > 0.001 else { continue }
                normal /= length
                emitters.append(ParticleBorderEmitter(
                    sourcePosition: SIMD2(
                        (Float(x) + 0.5) / Float(width),
                        (Float(y) + 0.5) / Float(height)
                    ),
                    sourceNormal: normal
                ))
            }
        }
        return emitters
    }

    private func viewBorderEmitter(
        _ emitter: ParticleBorderEmitter,
        sourceAspect: Float,
        viewAspect: Float
    ) -> (position: SIMD2<Float>, normal: SIMD2<Float>) {
        let position = viewPositionFromCamera(
            emitter.sourcePosition,
            sourceAspect: sourceAspect,
            viewAspect: viewAspect
        )
        var normal = emitter.sourceNormal
        if mirrorOutput { normal.x = -normal.x }
        if viewAspect > sourceAspect {
            normal.y /= sourceAspect / viewAspect
        } else {
            normal.x /= viewAspect / sourceAspect
        }
        var physical = SIMD2(normal.x * viewAspect, normal.y)
        physical /= max(0.0001, simd_length(physical))
        return (position, SIMD2(physical.x / viewAspect, physical.y))
    }

    private func liquidAffectsParticles(before processingLimitOrder: UInt32) -> Bool {
        guard let liquid = effectOrder.firstIndex(of: .liquidDistortion),
              let particles = effectOrder.firstIndex(of: .particles) else { return false }
        return liquid > particles && UInt32(liquid) < processingLimitOrder && liquidEnabled
    }

    private func liquidDistortedPosition(
        _ position: SIMD2<Float>,
        viewAspect: Float,
        now: CFTimeInterval
    ) -> SIMD2<Float> {
        let frequency = max(0.5, liquidScale)
        let phase = Float(now.truncatingRemainder(dividingBy: 1_000)) * liquidSpeed
        var p = position - 0.5
        p.x *= viewAspect
        let tau = Float.pi * 2
        let warpX = sin((p.y * frequency + phase) * tau)
            + 0.45 * sin((p.x * frequency * 0.73 - phase * 1.37) * tau)
        let warpY = cos((p.x * frequency * 0.81 + phase * 0.91) * tau)
            + 0.45 * sin((p.y * frequency * 1.19 + phase * 1.21) * tau)
        p += SIMD2(warpX, warpY) * liquidStrength
        p.x /= viewAspect
        return p + 0.5
    }

    private func viewPosition(_ joint: PoseJoint, in pose: BodyPose, viewAspect: Float) -> SIMD2<Float>? {
        guard let point = pose.points[joint], point.confidence >= skeletonConfidence else { return nil }
        return viewPosition(point.position, sourceAspect: pose.sourceAspect, viewAspect: viewAspect)
    }

    private func viewPosition(
        _ visionPosition: SIMD2<Float>,
        sourceAspect: Float,
        viewAspect: Float
    ) -> SIMD2<Float> {
        viewPositionFromCamera(
            SIMD2(visionPosition.x, 1 - visionPosition.y),
            sourceAspect: sourceAspect,
            viewAspect: viewAspect
        )
    }

    private func viewPositionFromCamera(
        _ cameraPosition: SIMD2<Float>,
        sourceAspect: Float,
        viewAspect: Float
    ) -> SIMD2<Float> {
        var camera = cameraPosition
        if mirrorOutput { camera.x = 1 - camera.x }
        if viewAspect > sourceAspect {
            let scale = sourceAspect / viewAspect
            return SIMD2(camera.x, (camera.y - 0.5) / scale + 0.5)
        }
        let scale = viewAspect / sourceAspect
        return SIMD2((camera.x - 0.5) / scale + 0.5, camera.y)
    }

    private func clipPosition(_ viewPosition: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(viewPosition.x * 2 - 1, 1 - viewPosition.y * 2)
    }

    private func randomUnit() -> Float {
        randomState = 1_664_525 &* randomState &+ 1_013_904_223
        return Float(randomState & 0x00FF_FFFF) / Float(0x0100_0000)
    }

    private func randomSigned() -> Float {
        randomUnit() * 2 - 1
    }

    private func effectOrderValue(_ effect: EffectKind) -> UInt32 {
        effectOrder.firstIndex(of: effect).map { UInt32($0) } ?? UInt32.max
    }

    private func makeTrailSnapshot(from result: MattingResult, capturedAt: CFTimeInterval) -> TrailFrame? {
        let colorBuffer = result.foreground ?? result.source
        guard let sourceColor = makeTexture(from: colorBuffer, format: .bgra8Unorm),
              let sourceAlpha = makeAlphaTexture(from: result.alpha) else { return nil }

        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: sourceColor.width,
            height: sourceColor.height,
            mipmapped: false
        )
        colorDescriptor.storageMode = .private
        colorDescriptor.usage = .shaderRead

        let alphaDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: sourceAlpha.width,
            height: sourceAlpha.height,
            mipmapped: false
        )
        alphaDescriptor.storageMode = .private
        alphaDescriptor.usage = .shaderRead

        let videoSource: MTLTexture?
        if videoFillEnabled, videoFillTiming == .historical {
            videoSource = activeVideoFillPlayer?
                .currentPixelBuffer(hostTime: capturedAt)
                .flatMap { makeTexture(from: $0, format: .bgra8Unorm) }
        } else {
            videoSource = nil
        }

        let video: MTLTexture?
        if let videoSource {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: videoSource.width,
                height: videoSource.height,
                mipmapped: false
            )
            descriptor.storageMode = .private
            descriptor.usage = .shaderRead
            video = device.makeTexture(descriptor: descriptor)
        } else {
            video = nil
        }

        guard let color = device.makeTexture(descriptor: colorDescriptor),
              let alpha = device.makeTexture(descriptor: alphaDescriptor),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }

        blit.copy(
            from: sourceColor,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: sourceColor.width, height: sourceColor.height, depth: 1),
            to: color,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        blit.copy(
            from: sourceAlpha,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: sourceAlpha.width, height: sourceAlpha.height, depth: 1),
            to: alpha,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        if let videoSource, let video {
            blit.copy(
                from: videoSource,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: .init(x: 0, y: 0, z: 0),
                sourceSize: .init(width: videoSource.width, height: videoSource.height, depth: 1),
                to: video,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: .init(x: 0, y: 0, z: 0)
            )
        }
        blit.endEncoding()
        commandBuffer.commit()
        return TrailFrame(color: color, alpha: alpha, video: video, capturedAt: capturedAt)
    }

    private func makeTexture(from buffer: CVPixelBuffer, format: MTLPixelFormat) -> MTLTexture? {
        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, buffer, nil, format,
            CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &cvTexture
        )
        guard result == kCVReturnSuccess, let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }

    private func makeAlphaTexture(from buffer: CVPixelBuffer) -> MTLTexture? {
        if let texture = makeTexture(from: buffer, format: .r8Unorm) { return texture }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        ciContext.render(
            CIImage(cvPixelBuffer: buffer),
            to: texture,
            commandBuffer: nil,
            bounds: CGRect(x: 0, y: 0, width: descriptor.width, height: descriptor.height),
            colorSpace: CGColorSpaceCreateDeviceGray()
        )
        return texture
    }
}

private struct PendingFrame {
    let result: MattingResult
    let submittedAt: CFTimeInterval
    let completion: (Double) -> Void
}

private struct TrailFrame {
    let color: MTLTexture
    let alpha: MTLTexture
    let video: MTLTexture?
    let capturedAt: CFTimeInterval
}

private struct SignalSnapshotTextures {
    let color: MTLTexture
    let alpha: MTLTexture
}

private struct SampleHistory {
    var line: SampleLine
    var texture: MTLTexture
    var newestRow: Int
    var count: Int
}

private struct SampleParams {
    var endpoints: SIMD4<Float>
    var settings: SIMD4<Float>
    var history: SIMD4<Float>
    var options: SIMD4<UInt32>
}

private struct OccupancyLine {
    var endpoints = SIMD4<Float>(repeating: 0)
    var sections: UInt32 = 0
    var thickness: Float = 0
    var enabled: UInt32 = 0
    var padding: UInt32 = 0
}

private struct TrailLayerParams {
    var amount: Float
    var opacity: Float
}

private struct OverlayVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
    var pointSize: Float
    var colorSlot: UInt32 = 0
}

private struct ParticleColorCapture {
    var uv: SIMD2<Float>
    var slot: UInt32
}

private struct ExplosionVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
}

private struct Particle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var age: Float
    var lifetime: Float
    var sizeFactor: Float
    var colorSlot: UInt32
}

private struct FrameCaptureRequest {
    let id: UUID
    let completion: (Data?) -> Void
}

private struct ThumbnailBuffer {
    let buffer: MTLBuffer
    let width: Int
    let height: Int
    let bytesPerRow: Int
}

private struct ParticleBorderEmitter {
    var sourcePosition: SIMD2<Float>
    var sourceNormal: SIMD2<Float>
}

private struct ShaderParams {
    var mode: UInt32
    var background: UInt32
    var threshold: Float
    var edgeSoftness: Float
    var alphaGain: Float
    var sourceAspect: Float
    var viewAspect: Float
    var gradientEnabled: UInt32
    var gradientStyle: UInt32
    var gradientOpacity: Float
    var gradientAngle: Float
    var cloneEnabled: UInt32
    var cloneCount: UInt32
    var cloneRotation: Float
    var cloneScaleStep: Float
    var cloneTranslation: SIMD2<Float>
    var cloneOpacity: Float
    var cloneDecay: Float
    var trailBlendMode: UInt32
    var mirrorOutput: UInt32
    var liquidEnabled: UInt32
    var liquidStrength: Float
    var liquidScale: Float
    var liquidSpeed: Float
    var time: Float
    var videoFillEnabled: UInt32
    var videoFillOpacity: Float
    var videoAspect: Float
    var videoScale: Float
    var gradientOrder: UInt32
    var liquidOrder: UInt32
    var videoOrder: UInt32
    var linesOrder: UInt32
    var particleOrder: UInt32
    var historicalOrder: UInt32
    var processingLimitOrder: UInt32
    var particleShape: UInt32
    var subjectVisible: UInt32
    var linesBlendMode: UInt32
    var gradientBlendMode: UInt32
    var videoBlendMode: UInt32
    var liquidBlendMode: UInt32
    var particleBlendMode: UInt32
}
