import AppKit
import SwiftUI

struct PresetLibraryView: View {
    @ObservedObject var controller: AppController

    /// Small enough that a narrow window shows one column, capped so a wide
    /// window does not stretch a card into a banner.
    private let columns = [GridItem(.adaptive(minimum: 132, maximum: 240), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                LazyVGrid(columns: columns, spacing: 12) {
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
            .padding(16)
        }
        .background {
            if !controller.controlPanelTransparent {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .background(WindowConfigurator(
            transparentBackground: controller.controlPanelTransparent,
            autosaveName: "KineticCanvas.PresetLibrary.Frame.v1"
        ))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Presets")
                .font(.system(size: 24, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Text("\(controller.presets.count)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.08), in: Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(controller.presets.count) presets")
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
                Color.clear
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .overlay { artworkLayer }
                    .overlay(alignment: .topTrailing) {
                        if isSelected { selectedBadge }
                    }
                    .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    Text(effectLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
            }
            .background(Color.primary.opacity(isHovered ? 0.09 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor
                            : Color.primary.opacity(isHovered ? 0.2 : 0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .task(id: preset.thumbnailFileName) {
            artwork = thumbnailURL.flatMap { NSImage(contentsOf: $0) }
        }
        .accessibilityLabel("Load preset \(preset.name)")
    }

    private var effectLabel: String {
        "\(preset.effects.count) effect\(preset.effects.count == 1 ? "" : "s")"
    }

    private var selectedBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Color.accentColor, in: Circle())
            .padding(8)
    }

    private var artworkLayer: some View {
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
        }
    }

    private var fallbackArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.17, blue: 0.24),
                         Color(red: 0.09, green: 0.10, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }
}
