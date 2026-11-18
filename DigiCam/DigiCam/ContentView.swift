import SwiftUI

/// Layout modeled on the stock iPhone Camera app from the iPhone 5c / 6s era:
/// flash + flip on top, 3:4 viewfinder, VIDEO/PHOTO selector, thumbnail + shutter + looks button.
struct ContentView: View {
    @StateObject private var cam = CameraManager()
    @State private var showLooks = false
    @State private var recSeconds = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let yellow = Color(red: 1.0, green: 0.84, blue: 0.04)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar.frame(height: 48)
                viewfinder
                Spacer(minLength: 0)
                modeSelector.frame(height: 38)
                controls.frame(height: 96).padding(.bottom, 8)
            }

            if cam.shutterFlash {
                Color.white.ignoresSafeArea().allowsHitTesting(false)
            }
            if cam.permissionDenied {
                Text("Allow camera access in\nSettings > DigiCam")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
            }
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
        .onAppear { cam.start() }
        .onReceive(timer) { _ in
            if cam.isRecording { recSeconds += 1 }
        }
        .onChange(of: cam.isRecording) { recording in
            if recording { recSeconds = 0; showLooks = false }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { cam.toggleFlash() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                    Text(cam.flashOn ? "On" : "Off").font(.system(size: 14))
                }
                .foregroundColor(cam.flashOn ? yellow : .white)
                .frame(width: 70, alignment: .leading)
            }

            Spacer()

            if cam.isRecording {
                Text(String(format: "%02d:%02d", recSeconds / 60, recSeconds % 60))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.red)
                    .cornerRadius(4)
            } else {
                Text(cam.profile.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }

            Spacer()

            Button { cam.flipCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 70, alignment: .trailing)
            }
            .disabled(cam.isRecording)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        ZStack(alignment: .bottom) {
            Color(white: 0.08)
            if let img = cam.previewImage {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.low)
                    .scaledToFill()
            }
            if showLooks { looksStrip }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipped()
    }

    private var looksStrip: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text("Dreamy")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                Slider(value: Binding(get: { cam.dream }, set: { cam.setDream($0) }),
                       in: 0...1.5)
                    .tint(yellow)
            }
            .padding(.horizontal, 16)

            HStack {
                ForEach(CameraProfile.all) { p in
                    let selected = cam.profile.id == p.id
                    Button { cam.select(p) } label: {
                        VStack(spacing: 2) {
                            Text(p.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(selected ? yellow : .white)
                            Text(p.subtitle)
                                .font(.system(size: 11))
                                .foregroundColor(Color(white: 0.75))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.55))
    }

    // MARK: - Mode selector (VIDEO / PHOTO)

    private var modeSelector: some View {
        HStack(spacing: 0) {
            modeLabel("VIDEO", .video)
            modeLabel("PHOTO", .photo)
        }
        .frame(maxWidth: .infinity)
        .offset(x: cam.mode == .photo ? -40 : 40)
        .animation(.easeInOut(duration: 0.2), value: cam.mode)
        .clipped()
    }

    private func modeLabel(_ title: String, _ m: CaptureMode) -> some View {
        Button { cam.setMode(m) } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .tracking(0.5)
                .foregroundColor(cam.mode == m ? yellow : .white)
                .frame(width: 80, height: 38)
        }
    }

    // MARK: - Thumbnail, shutter, looks

    private var controls: some View {
        HStack {
            thumbnail
            Spacer()
            shutter
            Spacer()
            Button { showLooks.toggle() } label: {
                Image(systemName: "camera.filters")
                    .font(.system(size: 26))
                    .foregroundColor(showLooks ? yellow : .white)
                    .frame(width: 48, height: 48)
            }
            .disabled(cam.isRecording)
        }
        .padding(.horizontal, 28)
    }

    private var thumbnail: some View {
        Group {
            if let t = cam.thumbnail {
                Image(uiImage: t).resizable().scaledToFill()
            } else {
                Color(white: 0.2)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.4), lineWidth: 1))
        .onTapGesture {
            if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
        }
    }

    private var shutter: some View {
        Button(action: cam.shutterTapped) {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 4).frame(width: 70, height: 70)
                if cam.mode == .video {
                    RoundedRectangle(cornerRadius: cam.isRecording ? 6 : 29)
                        .fill(Color.red)
                        .frame(width: cam.isRecording ? 28 : 58, height: cam.isRecording ? 28 : 58)
                } else {
                    Circle().fill(Color.white).frame(width: 58, height: 58)
                }
            }
            .animation(.easeOut(duration: 0.15), value: cam.isRecording)
        }
    }
}
