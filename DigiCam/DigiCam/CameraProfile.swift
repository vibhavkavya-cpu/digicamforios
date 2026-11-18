import Foundation
import CoreGraphics

/// One "camera". Add a new instance to `all` to add a new look.
/// All images are portrait 3:4.
struct CameraProfile: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String

    // Output size (width in px; height = width * 4/3)
    let photoWidth: Int        // max 1080 (source is a 1080p stream)
    let liveWidth: Int         // preview + video width
    let videoBitrate: Int      // bits per second
    let jpegQuality: CGFloat

    // Color and tone
    let saturation: Float      // 1 = normal
    let contrast: Float        // 1 = normal
    let brightness: Float      // 0 = normal
    let warmth: Float          // + warm, - cool
    let tint: Float            // + green, - magenta
    let blackLift: Float       // gently faded blacks, 0...0.08

    // Dreamy bits (all scaled by the in-app "Dreamy" slider)
    let softness: Float        // tiny overall softness in px (keeps detail)
    let glow: Float            // soft glow around bright areas (0...1)
    let glowWarmth: Float      // 0 = neutral glow, 1 = warm orange halation
    let shadowTint: Float      // cool teal tint in the shadows (0...0.5)

    // Sensor character
    let sharpen: Float         // light sharpening so it doesn't look blurry
    let fringing: Float        // purple/green edge fringe in px
    let vignette: Float        // 0...1, kept gentle
    let grain: Float           // fine film-like grain strength
    let chromaNoise: Float     // 0 = mono grain, 1 = very colorful
    let flashBoost: Float      // EV added when Flash look is on
    let dateStamp: Bool        // orange date stamp

    var photoHeight: Int { photoWidth * 4 / 3 }
    var liveHeight: Int { liveWidth * 4 / 3 }
}

extension CameraProfile {
    static let all: [CameraProfile] = [
        // Old iPhone 5s: warm, soft light, fine grain
        CameraProfile(
            id: "pocket13", name: "POCKET '13", subtitle: "5s vibes",
            photoWidth: 960, liveWidth: 480, videoBitrate: 1_500_000, jpegQuality: 0.65,
            saturation: 0.98, contrast: 1.02, brightness: 0.02, warmth: 0.04, tint: 0,
            blackLift: 0.04,
            softness: 0.35, glow: 0.35, glowWarmth: 0.6, shadowTint: 0.25,
            sharpen: 0.25, fringing: 0, vignette: 0.25, grain: 0.5, chromaNoise: 0.25,
            flashBoost: 0.2, dateStamp: false),

        // iPhone 5c: a little more color
        CameraProfile(
            id: "pop13", name: "POP '13", subtitle: "5c vibes",
            photoWidth: 960, liveWidth: 480, videoBitrate: 1_500_000, jpegQuality: 0.65,
            saturation: 1.1, contrast: 1.04, brightness: 0.02, warmth: 0.05, tint: 0,
            blackLift: 0.03,
            softness: 0.35, glow: 0.35, glowWarmth: 0.5, shadowTint: 0.2,
            sharpen: 0.25, fringing: 0, vignette: 0.25, grain: 0.5, chromaNoise: 0.25,
            flashBoost: 0.2, dateStamp: false),

        // iPhone 6s: clean and airy
        CameraProfile(
            id: "clear15", name: "CLEAR '15", subtitle: "6s vibes",
            photoWidth: 1080, liveWidth: 720, videoBitrate: 3_000_000, jpegQuality: 0.72,
            saturation: 1.0, contrast: 1.03, brightness: 0.01, warmth: 0.0, tint: 0,
            blackLift: 0.02,
            softness: 0.25, glow: 0.2, glowWarmth: 0.3, shadowTint: 0.15,
            sharpen: 0.4, fringing: 0, vignette: 0.15, grain: 0.3, chromaNoise: 0.2,
            flashBoost: 0.2, dateStamp: false),

        // Compact CCD: dreamy glow, tiny fringe, date stamp
        CameraProfile(
            id: "ccd06", name: "CCD '06", subtitle: "compact cam",
            photoWidth: 768, liveWidth: 480, videoBitrate: 1_200_000, jpegQuality: 0.6,
            saturation: 1.15, contrast: 1.08, brightness: 0.02, warmth: 0.01, tint: -0.01,
            blackLift: 0.05,
            softness: 0.5, glow: 0.5, glowWarmth: 0.4, shadowTint: 0.3,
            sharpen: 0.35, fringing: 0.6, vignette: 0.45, grain: 0.55, chromaNoise: 0.4,
            flashBoost: 0.5, dateStamp: true),
    ]
}
