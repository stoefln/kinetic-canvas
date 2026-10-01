import AVFoundation
import Foundation

final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((CameraFrame) -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "dancefx.camera.session", qos: .userInitiated)
    private let captureQueue = DispatchQueue(label: "dancefx.camera.frames", qos: .userInteractive)
    private let output = AVCaptureVideoDataOutput()

    func availableCameras() -> [CameraDescriptor] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map {
            CameraDescriptor(
                id: $0.uniqueID,
                name: $0.localizedName,
                mirrorsOutput: $0.deviceType != .external
            )
        }
    }

    func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start(cameraID: String) throws {
        try configure(cameraID: cameraID)
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func switchCamera(cameraID: String) throws {
        try configure(cameraID: cameraID)
    }

    private func configure(cameraID: String) throws {
        guard let device = AVCaptureDevice(uniqueID: cameraID) else {
            throw CameraError.deviceUnavailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1280x720
        session.inputs.forEach(session.removeInput)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        if session.outputs.isEmpty {
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 1280,
                kCVPixelBufferHeightKey as String: 720,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            output.setSampleBufferDelegate(self, queue: captureQueue)
            guard session.canAddOutput(output) else { throw CameraError.cannotAddOutput }
            session.addOutput(output)
        }

        if let connection = output.connection(with: .video) {
            connection.videoRotationAngle = 0
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        let duration = CMTime(value: 1, timescale: 30)
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(CameraFrame(
            pixelBuffer: pixelBuffer,
            timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            hostTime: CACurrentMediaTime()
        ))
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onError?("AVFoundation dropped a late camera frame.")
    }
}

enum CameraError: LocalizedError {
    case deviceUnavailable, cannotAddInput, cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: "The selected camera is no longer available."
        case .cannotAddInput: "The selected camera could not be attached to the capture session."
        case .cannotAddOutput: "The video output could not be attached to the capture session."
        }
    }
}
