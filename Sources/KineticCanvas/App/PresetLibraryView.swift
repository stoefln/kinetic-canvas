import AppKit
import SwiftUI

struct PresetLibraryView: View {
    @ObservedObject var controller: AppController

    /// Cards per row is capped at 4; extra width enlarges the cards rather than
    /// adding columns. A narrow window falls back through 3, 2, and 1, so a tall
    /// narrow window shows every preset in a single column.
    private let maxColumns = 4
    private let minimumCardWidth: CGFloat = 132
    private let cardSpacing: CGFloat = 12
    private let contentPadding: CGFloat = 16

    /// Equal-width columns so cards always fill the row. The count comes from how
    /// many minimum-width cards fit the window, clamped to `maxColumns`. The cards
    /// themselves have no minimum so an ultra-narrow window never overflows.
    private func columns(forWidth width: CGFloat) -> [GridItem] {
        let contentWidth = max(0, width - 2 * contentPadding)
        let fit = contentWidth > 0
            ? Int((contentWidth + cardSpacing) / (minimumCardWidth + cardSpacing))
            : 1
        let count = max(1, min(maxColumns, fit))
        return Array(repeating: GridItem(.flexible(minimum: 0), spacing: cardSpacing),
                     count: count)
    }

    var body: some View {
        // A root GeometryReader gives the true window width, so the column count
        // recomputes on every resize; measuring inside the scroll view can go
        // stale and leave a narrow window stuck at four cramped columns.
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    LazyVGrid(columns: columns(forWidth: proxy.size.width), spacing: cardSpacing) {
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
                .padding(contentPadding)
            }
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
                    .overlay(alignment: .topLeading) {
                        if preset.hasAudioConfiguration { audioBadge }
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
        var text = "\(preset.effects.count) effect\(preset.effects.count == 1 ? "" : "s")"
        if preset.hasAudioConfiguration {
            text += " · " + preset.audioDestinations.map(audioName).joined(separator: ", ")
        }
        return text
    }

    private func audioName(_ destination: SampleLineDestination) -> String {
        switch destination {
        case .loop: "Loop"
        case .oneShot: "One-shot"
        case .vital: "Vital"
        case .midi: "MIDI"
        }
    }

    /// Compact marker so a preset with audio stands out while scanning the grid.
    private var audioBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "waveform")
                .font(.system(size: 8, weight: .black))
            Text("\(preset.audioDestinations.count)")
                .font(.system(size: 8, weight: .black, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.55), in: Capsule())
        .padding(8)
        .help("This preset has audio: \(preset.audioDestinations.map(audioName).joined(separator: ", "))")
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
