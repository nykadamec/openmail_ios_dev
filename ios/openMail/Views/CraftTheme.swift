import SwiftUI

// MARK: - Inbox Craft tokens (směr C z Pen, frame „C - Inbox craft")
//
// Teplý craft styl: pozadí #FFF8F0, mléčné glass kapsle, oranžový akcent
// #FF6B35, inkoust #111111. Inter není v bundlu aplikace, proto
// `Font.craft` mapuje váhy/specifikaci na systémový font se stejnou
// metrikou (velikost/váha dle specu).

extension Color {
    /// Teplé pozadí celé Inbox Craft obrazovky (#FFF8F0).
    static let craftBackground = Color(red: 1.0, green: 0.973, blue: 0.941)
    /// Primární text (#111111).
    static let craftInk = Color(red: 0.067, green: 0.067, blue: 0.067)
    /// Oranžový akcent – pozdrav, aktivní tab (#FF6B35).
    static let craftAccent = Color(red: 1.0, green: 0.42, blue: 0.208)
    /// Modrá tečka nepřečtených (#007AFF).
    static let craftUnread = Color(red: 0.0, green: 0.478, blue: 1.0)
    /// Sekundární text (#8E8E93).
    static let craftSecondary = Color(red: 0.557, green: 0.557, blue: 0.576)
    /// Výplň search pillu a neaktivních kruhových akcí (#F2F2F7).
    static let craftPill = Color(red: 0.949, green: 0.949, blue: 0.969)
    /// Předmět mailu (#555555).
    static let craftSubject = Color(red: 0.333, green: 0.333, blue: 0.333)
    /// Teplý stín glass kapslí (#7A4A21).
    static let craftWarmShadow = Color(red: 0.479, green: 0.29, blue: 0.129)
    /// Mléčná výplň glass kapslí (#FFFFFFD9, tj. bílá 85 %).
    static let craftGlassFill = Color.white.opacity(0.85)
}

extension Font {
    /// Inter není v bundlu, proto systémový font se stejnou velikostí/váhou.
    /// Volající předává přesně hodnoty ze specu (13/700, 22/800, …).
    static func craft(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Glass kapsle

/// Mléčná glass kapsle: bílá 85 % + ultraThinMaterial + bílý stroke + teplý stín.
struct CraftGlass: ViewModifier {
    var cornerRadius: CGFloat = 22
    var shadowOpacity: Double = 0.15
    var shadowRadius: CGFloat = 16
    var shadowY: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(Color.craftGlassFill, in: RoundedRectangle(cornerRadius: cornerRadius))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.white, lineWidth: 1))
            .shadow(
                color: Color.craftWarmShadow.opacity(shadowOpacity),
                radius: shadowRadius, y: shadowY
            )
    }
}

extension View {
    func craftGlass(
        cornerRadius: CGFloat = 22,
        shadowOpacity: Double = 0.15,
        shadowRadius: CGFloat = 16,
        shadowY: CGFloat = 8
    ) -> some View {
        modifier(CraftGlass(
            cornerRadius: cornerRadius,
            shadowOpacity: shadowOpacity,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        ))
    }
}

// MARK: - Avatar s iniciálami

/// Kruh 44 s iniciálami (až 2 písmena). Barva se hashuje z odesílatele
/// do craft palety FF6B35 / 007AFF / 34C759 / AF52DE / 111111.
struct CraftAvatar: View {
    let sender: String

    private static let palette: [Color] = [
        Color(red: 1.0, green: 0.42, blue: 0.208), // FF6B35
        Color(red: 0.0, green: 0.478, blue: 1.0), // 007AFF
        Color(red: 0.204, green: 0.78, blue: 0.349), // 34C759
        Color(red: 0.686, green: 0.322, blue: 0.871), // AF52DE
        Color(red: 0.067, green: 0.067, blue: 0.067), // 111111
    ]

    private var initials: String {
        let words = sender
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        if !words.isEmpty { return words }
        let trimmed = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private var colour: Color {
        let sum = sender.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.palette[sum % Self.palette.count]
    }

    var body: some View {
        Circle()
            .fill(colour)
            .frame(width: 44, height: 44)
            .overlay(
                Text(initials)
                    .font(.craft(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Floating tab bar

/// Minimalistická centrovaná glass pilulka 232×68, radius 22.
/// Taby přepínají skutečné view v `MainTab` přes `selection`;
/// prostřední „Napsat" vybírá tab s Composerem.
struct CraftTabBar: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            tabItem(
                tag: 0,
                titleKey: "craft.tab.inbox",
                systemImage: "tray.full",
                circleSize: 32
            )
            .frame(width: 64)

            tabItem(
                tag: 1,
                titleKey: "craft.tab.compose",
                systemImage: "square.and.pencil",
                circleSize: 38,
                alwaysDark: true
            )
            .frame(width: 72)

            tabItem(
                tag: 2,
                titleKey: "craft.tab.profile",
                systemImage: "person.crop.circle",
                circleSize: 32
            )
            .frame(width: 64)
        }
        .padding(.vertical, 6)
        .frame(width: 232, height: 68)
        .craftGlass(
            cornerRadius: 22,
            shadowOpacity: 0.26,
            shadowRadius: 6.5,
            shadowY: 0
        )
        .accessibilityElement(children: .contain)
    }

    private func tabItem(
        tag: Int,
        titleKey: String,
        systemImage: String,
        circleSize: CGFloat,
        alwaysDark: Bool = false
    ) -> some View {
        let active = selection == tag
        return Button {
            withAnimation(.snappy) { selection = tag }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(
                            alwaysDark
                                ? Color.craftInk
                                : (active ? Color.craftAccent : Color.clear)
                        )
                        .frame(width: circleSize, height: circleSize)
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            alwaysDark || active ? Color.white : Color.craftSecondary
                        )
                }
                Text(LocalizedStringKey(titleKey))
                    .font(.craft(size: 10, weight: active ? .bold : .regular))
                    .foregroundStyle(active ? Color.craftAccent : Color.craftSecondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
