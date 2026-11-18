import SwiftUI
import AVFoundation
import Photos
import UIKit
import AudioToolbox

enum CaptureMode: String {
    case photo = "PHOTO"
    case video = "VIDEO"
}

final class CameraManager: NSObject, ObservableObject {
    // UI state (main thread only)
    @Published var previewImage: UIImage?
    @Published var profile: CameraProfile = CameraProfile.all[0]
    @Published var mode: CaptureMode = .photo
    @Published var isRecording = false
    @Published var flashOn = false
    @Published var shutterFlash = false
    @Published var permissionDenied = false
    @Published var thumbnail: UIImage?
    @Published var dream: Double = 1.0

    // Capture objects
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private let queue = DispatchQueue(label: "digicam.capture")
    private let pipeline = FilterPipeline()

    // Queue-confined state
    private var configured = false
    private var activeProfile = CameraProfile.all[0]
    private var activeFlash = false
    private var activeDream: Float = 1.0
    private var lastRaw: CIImage?
    private var recorder: Recorder?
    private var frameCounter = 0

    // MARK: - Setup

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else {
                DispatchQueue.main.async { self.permissionDenied = true }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in
                    self.queue.async { self.configureSession() }
                }
            }
        }
    }

    private func configureSession() {
        if configured {
            if !session.isRunning { session.startRunning() }
            return
        }
        configured = true

        session.beginConfiguration()
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        setVideoInput(position: position)

        if let mic = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(input) {
            session.addInput(input)
        }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        audioOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }

        session.commitConfiguration()
        applyConnection()
        session.startRunning()
    }

    private func setVideoInput(position: AVCaptureDevice.Position) {
        if let old = videoInput { session.removeInput(old) }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        videoInput = input
    }

    private func applyConnection() {
        guard let c = videoOutput.connection(with: .video) else { return }
        if #available(iOS 17.0, *) {
            if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        } else if c.isVideoOrientationSupported {
            c.videoOrientation = .portrait
        }
        if c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = (position == .front)
        }
    }

    // MARK: - Controls

    func select(_ p: CameraProfile) {
        guard !isRecording else { return }
        profile = p
        queue.async { self.activeProfile = p }
    }

    func setDream(_ value: Double) {
        dream = value
        let v = Float(value)
        queue.async { self.activeDream = v }
    }

    func toggleFlash() {
        flashOn.toggle()
        let value = flashOn
        queue.async { self.activeFlash = value }
    }

    func setMode(_ m: CaptureMode) {
        guard !isRecording else { return }
        mode = m
    }

    func flipCamera() {
        guard !isRecording else { return }
        queue.async {
            self.position = (self.position == .back) ? .front : .back
            self.session.beginConfiguration()
            self.setVideoInput(position: self.position)
            if self.session.canSetSessionPreset(.hd1920x1080) {
                self.session.sessionPreset = .hd1920x1080
            }
            self.session.commitConfiguration()
            self.applyConnection()
        }
    }

    func shutterTapped() {
        if mode == .photo {
            capturePhoto()
        } else if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    // MARK: - Photo

    private func capturePhoto() {
        AudioServicesPlaySystemSound(1108) // camera shutter
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.05)) { self.shutterFlash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeIn(duration: 0.15)) { self.shutterFlash = false }
            }
        }

        queue.async {
            guard let raw = self.lastRaw else { return }
            let p = self.activeProfile
            let image = self.pipeline.process(raw, profile: p, width: p.photoWidth,
                                              seed: Int.random(in: 1..<100_000),
                                              flash: self.activeFlash,
                                              dream: self.activeDream)
            guard let cg = self.pipeline.context.createCGImage(image, from: image.extent),
                  let data = UIImage(cgImage: cg).jpegData(compressionQuality: p.jpegQuality) else { return }
            let thumb = UIImage(cgImage: cg)
            DispatchQueue.main.async { self.thumbnail = thumb }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            })
        }
    }

    // MARK: - Video

    private func startRecording() {
        queue.async {
            guard self.recorder == nil else { return }
            let p = self.activeProfile
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".mp4")
            guard let r = try? Recorder(url: url, width: p.liveWidth, height: p.liveHeight,
                                        bitrate: p.videoBitrate) else { return }
            self.recorder = r
            DispatchQueue.main.async { self.isRecording = true }
        }
    }

    private func stopRecording() {
        queue.async {
            guard let r = self.recorder else { return }
            self.recorder = nil
            DispatchQueue.main.async {
                self.isRecording = false
                self.thumbnail = self.previewImage
            }
            r.finish { url in
                guard let url = url else { return }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }, completionHandler: { _, _ in
                    try? FileManager.default.removeItem(at: url)
                })
            }
        }
    }
}

// MARK: - Frame delivery (runs on `queue`)

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate,
                         AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === audioOutput {
            recorder?.appendAudio(sampleBuffer)
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let raw = CIImage(cvPixelBuffer: pixelBuffer)
        lastRaw = raw
        frameCounter &+= 1

        let p = activeProfile
        let image = pipeline.process(raw, profile: p, width: p.liveWidth,
                                     seed: frameCounter & 0xFFFFF, flash: false,
                                     dream: activeDream)

        recorder?.appendVideo(image, context: pipeline.context,
                              time: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

        guard let cg = pipeline.context.createCGImage(image, from: image.extent) else { return }
        let ui = UIImage(cgImage: cg)
        DispatchQueue.main.async { self.previewImage = ui }
    }
}
