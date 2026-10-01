import AppKit
import SwiftUI

struct PresetLibraryView: View {
    @ObservedObject var controller: AppController

    private let columns = [GridItem(.adaptive(minimum: 225, maximum: 330), spacing: 20)]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.16),
                         Color(red: 0.035, green: 0.045, blue: 0.075)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(controller.presets) { preset in
                            PresetCard(
                                preset: preset,
                                thumbnailURL: controller.thumbnailURL(for: preset),
                                isSelected: controller.selectedPresetID == preset.id
                            ) {
                                controller.selectPreset(id: preset.id)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(32)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "square.grid.2x2.fill")
                    .foregroundStyle(Color(red: 0.48, green: 0.77, blue: 1))
                Text("DANCEFX  /  PRESET LIBRARY")
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.58))
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))

            HStack(alignment: .firstTextBaseline) {
                Text("Your looks")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(controller.presets.count) PRESETS")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(Color.white.opacity(0.62))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }

            Text("Select a look to load it into the control panel. New previews appear here when you save a preset.")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.54))
        }
    }
}

private struct PresetCard: View {
    let preset: EffectPreset
    let thumbnailURL: URL?
    let isSelected: Bool
    let select: () -> Void

    @State private var artwork: NSImage?
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    if let artwork {
                        GeometryReader { geometry in
                            Image(nsImage: artwork)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        }
                    } else {
                        fallbackArtwork
                    }

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.32)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
                .frame(height: 174)
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(red: 0.04, green: 0.09, blue: 0.14))
                            .frame(width: 27, height: 27)
                            .background(Color(red: 0.48, green: 0.77, blue: 1), in: Circle())
                            .padding(12)
                    }
                }
                .clipped()

                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(preset.effects.count) EFFECT\(preset.effects.count == 1 ? "" : "S")")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(isHovered ? 0.9 : 0.42))
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 14)
            }
            .background(Color.white.opacity(isHovered ? 0.105 : 0.065))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color(red: 0.48, green: 0.77, blue: 1)
                            : Color.white.opacity(isHovered ? 0.25 : 0.11),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .shadow(color: .black.opacity(isHovered ? 0.32 : 0.16), radius: 18, y: 9)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .task(id: preset.thumbnailFileName) {
            artwork = thumbnailURL.flatMap { NSImage(contentsOf: $0) }
        }
        .accessibilityLabel("Load preset \(preset.name)")
    }

    private var fallbackArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.19, green: 0.19, blue: 0.34),
                         Color(red: 0.11, green: 0.30, blue: 0.39),
                         Color(red: 0.12, green: 0.12, blue: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(red: 0.43, green: 0.75, blue: 1).opacity(0.18))
                .frame(width: 170, height: 170)
                .blur(radius: 34)
                .offset(x: 54, y: -35)
            Image(systemName: "sparkles")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .overlay(alignment: .bottomLeading) {
            Text("NO PREVIEW")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(15)
        }
    }
}
