import AppKit
import SwiftUI

// Renders the install-window background for BioLab.dmg (640×400 points).
// Usage: swift dmg-background.swift <output.png> [scale]

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "bg.png"
let scale = CommandLine.arguments.count > 2 ? (Double(CommandLine.arguments[2]) ?? 1) : 1

private let indigo = Color(red: 0x3E / 255, green: 0x63 / 255, blue: 0xDD / 255)
private let ink = Color(red: 0x1C / 255, green: 0x20 / 255, blue: 0x30 / 255)
private let subtle = Color(red: 0x56 / 255, green: 0x5D / 255, blue: 0x75 / 255)

private struct Background: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0xFB / 255, green: 0xFB / 255, blue: 0xFD / 255),
                    Color(red: 0xEB / 255, green: 0xEF / 255, blue: 0xFB / 255),
                ],
                startPoint: .top, endPoint: .bottom)

            VStack(spacing: 7) {
                Text("Install BioLab")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(ink)
                Text("Drag the app onto the Applications folder")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(subtle)
            }
            .position(x: 320, y: 74)

            // Arrow from the app (left) toward Applications (right), on the
            // icon row that Finder lays out at y ≈ 200.
            Image(systemName: "arrow.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(indigo)
                .position(x: 320, y: 196)
        }
        .frame(width: 640, height: 400)
    }
}

@MainActor
func render() {
    let renderer = ImageRenderer(content: Background())
    renderer.scale = CGFloat(scale)
    guard let image = renderer.nsImage,
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write(Data("background render failed\n".utf8))
        exit(1)
    }
    do {
        try png.write(to: URL(fileURLWithPath: out))
        print("background → \(out)")
    } catch {
        FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
        exit(1)
    }
}

MainActor.assumeIsolated { render() }
