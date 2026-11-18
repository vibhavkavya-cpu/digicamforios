import CoreImage
import UIKit

/// Turns a raw camera frame into a natural, dreamy retro-looking 3:4 image.
/// Not thread-safe: call from one queue only (the capture queue).
final class FilterPipeline {
    let context = CIContext(options: [.cacheIntermediates: false])

    private static let random = CIFilter(name: "CIRandomGenerator")!.outputImage!
    private var stampCache: [String: CIImage] = [:]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "''yy MM dd"   // -> '26 11 18
        return f
    }()

    /// `dream` scales every "dreamy" effect: 0 = clean, 1 = default, 1.5 = extra dreamy.
    func process(_ input: CIImage, profile p: CameraProfile, width: Int, seed: Int,
                 flash: Bool, dream d: Float) -> CIImage {
        let W = CGFloat(width)
        let H = CGFloat(width * 4 / 3)
        let out = CGRect(x: 0, y: 0, width: W, height: H)

        // 1. Center-crop to 3:4 and downscale
        let e = input.extent
        let aspect: CGFloat = 3.0 / 4.0
        var rect = e
        if e.width / e.height > aspect {
            let w = e.height * aspect
            rect = CGRect(x: e.midX - w / 2, y: e.minY, width: w, height: e.height)
        } else {
            let h = e.width / aspect
            rect = CGRect(x: e.minX, y: e.midY - h / 2, width: e.width, height: h)
        }
        var img = input
            .cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let scale = W / rect.width
        img = img.applyingFilter("CILanczosScaleTransform",
                                 parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0])
        img = img.cropped(to: out)

        // 2. Very light overall softness (detail stays), then a little sharpening
        let soft = p.softness * d
        if soft > 0.05 {
            img = img.clampedToExtent()
                .applyingGaussianBlur(sigma: Double(soft))
                .cropped(to: out)
        }
        if p.sharpen > 0 {
            img = img.applyingFilter("CIUnsharpMask",
                                     parameters: [kCIInputRadiusKey: 1.5, kCIInputIntensityKey: p.sharpen])
        }

        // 3. Color: gentle, slightly warm, no heavy saturation
        img = img.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: p.saturation,
            kCIInputContrastKey: p.contrast,
            kCIInputBrightnessKey: p.brightness])
        img = img.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(1 + p.warmth), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(1 + p.tint), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(1 - p.warmth), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)])

        // 4. Soft film-like tone curve: lifted blacks, gentle highlight rolloff
        let lift = CGFloat(p.blackLift * d)
        img = img.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: lift),
            "inputPoint1": CIVector(x: 0.25, y: 0.25 + lift * 0.6),
            "inputPoint2": CIVector(x: 0.5, y: 0.5 + lift * 0.25),
            "inputPoint3": CIVector(x: 0.75, y: 0.755),
            "inputPoint4": CIVector(x: 1, y: 0.98)])

        // 5. Cool tint in the shadows (adds depth, keeps skin and light warm)
        let shadowAmount = p.shadowTint * d
        if shadowAmount > 0.01 {
            img = tintShadows(img, amount: shadowAmount, out: out)
        }

        // 6. Dreamy glow: only the bright areas bleed softly, like real lens glow
        let glowAmount = p.glow * d
        if glowAmount > 0.01 {
            img = glow(img, strength: glowAmount, warmth: p.glowWarmth, out: out)
        }

        // 7. Subtle fringing (compact-lens character)
        if p.fringing > 0 {
            img = fringe(img, amount: CGFloat(p.fringing), out: out)
        }

        // 8. Flash look (photos only)
        var vignette = p.vignette
        if flash {
            img = img.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: p.flashBoost])
            vignette = min(1, vignette + 0.2)
        }

        // 9. Gentle vignette
        if vignette > 0 {
            img = img.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: vignette,
                kCIInputRadiusKey: 1.8])
        }

        // 10. Fine grain last so it sits on top of everything
        if p.grain > 0 {
            img = grain(img, amount: p.grain, chroma: p.chromaNoise, seed: seed, out: out)
        }

        // 11. Date stamp
        if p.dateStamp {
            let text = Self.dateFormatter.string(from: Date())
            if let stamp = stampImage(text: text, imageWidth: W) {
                let margin = W * 0.05
                let placed = stamp.transformed(by: CGAffineTransform(
                    translationX: W - stamp.extent.width - margin, y: margin))
                img = placed.composited(over: img).cropped(to: out)
            }
        }
        return img
    }

    // MARK: - Effects

    /// Isolates highlights, blurs them wide, warms them slightly, and screens them back on.
    private func glow(_ img: CIImage, strength: Float, warmth: Float, out: CGRect) -> CIImage {
        let s = CGFloat(strength)
        let w = CGFloat(warmth)

        let highlights = img.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0),
            "inputPoint1": CIVector(x: 0.45, y: 0),
            "inputPoint2": CIVector(x: 0.65, y: 0.25),
            "inputPoint3": CIVector(x: 0.85, y: 0.7),
            "inputPoint4": CIVector(x: 1, y: 1)])

        let blurred = highlights.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(out.width * 0.025))
            .cropped(to: out)

        let tinted = blurred.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: s * (1 + w * 0.2), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: s * (1 - w * 0.1), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: s * (1 - w * 0.35), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)])

        return tinted.applyingFilter("CIScreenBlendMode",
                                     parameters: [kCIInputBackgroundImageKey: img])
            .cropped(to: out)
    }

    private func tintShadows(_ img: CIImage, amount: Float, out: CGRect) -> CIImage {
        let teal = CIImage(color: CIColor(red: 0.45, green: 0.72, blue: 0.80)).cropped(to: out)
        let tinted = teal.applyingFilter("CISoftLightBlendMode",
                                         parameters: [kCIInputBackgroundImageKey: img])
        let a = CGFloat(amount)
        let mask = img
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
            .applyingFilter("CIColorInvert")
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: a, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: a, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: a, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
        return tinted.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: img,
            kCIInputMaskImageKey: mask]).cropped(to: out)
    }

    private func fringe(_ img: CIImage, amount: CGFloat, out: CGRect) -> CIImage {
        let base = img.clampedToExtent()
        func channel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, alpha: CGFloat) -> CIImage {
            base.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
        }
        let red = channel(1, 0, 0, alpha: 1)
            .transformed(by: CGAffineTransform(translationX: amount, y: 0))
        let green = channel(0, 1, 0, alpha: 0)
        let blue = channel(0, 0, 1, alpha: 0)
            .transformed(by: CGAffineTransform(translationX: -amount, y: 0))
        let rg = red.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: green])
        return rg.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: blue])
            .cropped(to: out)
    }

    private func grain(_ img: CIImage, amount: Float, chroma: Float, seed: Int, out: CGRect) -> CIImage {
        let dx = CGFloat((seed &* 7919) % 997)
        let dy = CGFloat((seed &* 104729) % 991)

        let gain = CGFloat(amount * 1.4)
        let bias = 0.5 - 0.5 * gain

        var noise = Self.random
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
            .cropped(to: out.insetBy(dx: -6, dy: -6))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 0.5)
            .cropped(to: out)

        noise = noise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1)])
        noise = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: chroma])

        let noisy = noise.applyingFilter("CISoftLightBlendMode",
                                         parameters: [kCIInputBackgroundImageKey: img])

        // Stronger in shadows, almost none in highlights (like a real sensor)
        let mask = img
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
            .applyingFilter("CIColorInvert")
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.6])

        return noisy.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: img,
            kCIInputMaskImageKey: mask]).cropped(to: out)
    }

    private func stampImage(text: String, imageWidth: CGFloat) -> CIImage? {
        let key = "\(text)|\(Int(imageWidth))"
        if let cached = stampCache[key] { return cached }

        let font = UIFont.monospacedSystemFont(ofSize: imageWidth * 0.045, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 1)
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            (text as NSString).draw(at: .zero, withAttributes: attrs)
        }
        guard let ci = CIImage(image: image) else { return nil }
        stampCache[key] = ci
        return ci
    }
}
