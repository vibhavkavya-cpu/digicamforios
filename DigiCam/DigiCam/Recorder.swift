import AVFoundation
import CoreImage

/// Writes filtered frames + audio to a small H.264/AAC .mp4.
/// Call all methods from the same serial queue.
final class Recorder {
    let url: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var started = false

    init(url: URL, width: Int, height: Int, bitrate: Int) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoMaxKeyFrameIntervalKey: 30,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel
        ]
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ])

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 64000
        ]
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        writer.add(videoInput)
        writer.add(audioInput)
    }

    func appendVideo(_ image: CIImage, context: CIContext, time: CMTime) {
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: time)
            started = true
        }
        guard writer.status == .writing,
              videoInput.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool else { return }

        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let pb = buffer else { return }
        context.render(image, to: pb)
        adaptor.append(pb, withPresentationTime: time)
    }

    func appendAudio(_ sample: CMSampleBuffer) {
        guard started, writer.status == .writing, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sample)
    }

    func finish(completion: @escaping (URL?) -> Void) {
        guard started else {
            writer.cancelWriting()
            completion(nil)
            return
        }
        videoInput.markAsFinished()
        audioInput.markAsFinished()
        writer.finishWriting { [url, writer] in
            completion(writer.status == .completed ? url : nil)
        }
    }
}
