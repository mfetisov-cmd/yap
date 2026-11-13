import AppKit
import SwiftUI

/// The app icon: the recording pill as a speech bubble on a violet-to-pink squircle, drawn at 1024 px.
struct AppIconView: View {
    private let squircle = RoundedRectangle(cornerRadius: 185, style: .continuous)

    var body: some View {
        ZStack {
            squircle
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.32, blue: 0.98),
                                              Color(red: 0.62, green: 0.36, blue: 0.98),
                                              Color(red: 1.0, green: 0.45, blue: 0.64)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(squircle.fill(RadialGradient(colors: [.white.opacity(0.38), .clear],
                                                      center: .topLeading, startRadius: 0, endRadius: 720)))
                .overlay(squircle.strokeBorder(Color.white.opacity(0.22), lineWidth: 4))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 12)
            SpeechPill()
                .offset(y: -28)
        }
        .frame(width: 1024, height: 1024)
    }
}

private struct SpeechPill: View {
    private let heights: [CGFloat] = [88, 150, 214, 128, 186, 112, 64]
    private let bottom = Color(white: 0.935)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Tail()
                .fill(bottom)
                .frame(width: 124, height: 100)
                .offset(x: 96, y: 76)
            Capsule()
                .fill(LinearGradient(colors: [.white, bottom], startPoint: .top, endPoint: .bottom))
                .frame(width: 612, height: 248)
            HStack(spacing: 34) {
                ZStack {
                    Circle().fill(Palette.red.opacity(0.2)).frame(width: 124, height: 124)
                    Circle().fill(Palette.red).frame(width: 66, height: 66)
                }
                HStack(spacing: 22) {
                    ForEach(heights.indices, id: \.self) { index in
                        Capsule().fill(Palette.bars).frame(width: 30, height: heights[index])
                    }
                }
            }
            .frame(width: 612, height: 248)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 30, y: 18)
    }
}

/// The bubble's tail: from the pill's bottom edge down to a tip on the left.
private struct Tail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY),
                          control: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.minY + rect.height * 0.55))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY),
                          control: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.45))
        path.closeSubpath()
        return path
    }
}

@MainActor
enum AppIconRenderer {
    static func render(to url: URL) {
        let renderer = ImageRenderer(content: AppIconView())
        renderer.scale = 1
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
