import Foundation

enum DisplayMode: Int, CaseIterable, Identifiable {
    case original, alphaMatte, foreground, composite
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .original: "Original"
        case .alphaMatte: "Alpha Matte"
        case .foreground: "Foreground"
        case .composite: "Composite"
        }
    }
}

enum BackgroundChoice: Int, CaseIterable, Identifiable {
    case black, white, gray, checkerboard
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .black: "Black"
        case .white: "White"
        case .gray: "Gray"
        case .checkerboard: "Checkerboard"
        }
    }
}

enum GradientStyle: Int, CaseIterable, Identifiable, Codable {
    case neon, sunset, ice
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .neon: "Neon"
        case .sunset: "Sunset"
        case .ice: "Ice"
        }
    }
}

enum TrailBlendMode: Int, CaseIterable, Identifiable, Codable {
    case normal, additive, screen, lighten
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .normal: "Normal"
        case .additive: "Add"
        case .screen: "Screen"
        case .lighten: "Lighten"
        }
    }
}
