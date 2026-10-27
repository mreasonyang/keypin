import AppKit
import SwiftUI

/// Shared layout constants. The panel sizes itself to its content; only the width is fixed.
enum PanelMetrics {
    static let width: CGFloat = 320
    static let padding: CGFloat = 14
    static let rowHeight: CGFloat = 36
    static let rowSpacing: CGFloat = 2
    /// Lists taller than this scroll, leaving half a row visible as a scroll hint.
    static let visibleRows = 6
    /// Height of a titled window's title bar when the content view extends underneath it.
    static let titlebarHeight: CGFloat = 30
    /// Room for the close and minimize buttons in window mode.
    static let trafficLightInset: CGFloat = 58
}

// MARK: - State colors

extension RuntimeState {
    /// Color only reinforces the localized label and symbol; it never carries meaning alone.
    var tint: Color {
        switch self {
        case .keeping: return .green
        case .switching, .waiting: return .blue
        case .secureInput: return .indigo
        case .missingSource, .error, .conflictPaused: return .orange
        case .setup: return .accentColor
        case .paused, .stopped: return .gray
        }
    }

    var isNeutral: Bool { self == .paused || self == .stopped }
    var isTransient: Bool { self == .switching || self == .waiting }
}

// MARK: - Input source artwork

/// Preserve native artwork; only monochrome template images inherit the text color.
/// A fixed slot keeps differently proportioned input-method icons aligned.
struct SourceArtwork: View {
    let image: NSImage
    var size: CGFloat = 24

    var body: some View {
        Image(nsImage: image)
            .renderingMode(image.isTemplate ? .template : .original)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.primary)
            .frame(width: size * 22 / 24, height: size * 18 / 24)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Surfaces

/// A quiet platter on top of the window or popover material. Avoids stacking glass on glass.
struct Surface: ViewModifier {
    var radius: CGFloat = 14
    var tint: Color? = nil
    @Environment(\.accessibilityReduceTransparency) private var systemReduced
    @Environment(\.previewReduceTransparency) private var previewReduced
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let reduced = systemReduced || previewReduced
        content
            .background {
                ZStack {
                    if reduced {
                        shape.fill(Color(nsColor: .controlBackgroundColor))
                    } else {
                        shape.fill(Color.primary.opacity(scheme == .dark ? 0.06 : 0.045))
                    }
                    if let tint {
                        shape.fill(LinearGradient(colors: [tint.opacity(reduced ? 0.14 : 0.18), tint.opacity(0.03)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            }
            .overlay {
                shape.strokeBorder(contrast == .increased ? Color.primary.opacity(0.35)
                                   : (tint ?? .primary).opacity(tint == nil ? 0.06 : 0.16), lineWidth: 1)
            }
    }
}

extension View {
    func surface(radius: CGFloat = 14, tint: Color? = nil) -> some View {
        modifier(Surface(radius: radius, tint: tint))
    }
}

/// The source picker is the main glass surface; setup keeps its existing quiet list.
struct SourceListSurface: ViewModifier {
    let usesGlass: Bool
    @Environment(\.previewLegacyAppearance) private var legacyAppearance
    @Environment(\.accessibilityReduceTransparency) private var systemReduced
    @Environment(\.previewReduceTransparency) private var previewReduced
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), usesGlass && !legacyAppearance && !systemReduced && !previewReduced && contrast != .increased {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        } else {
            content.surface(radius: 13)
        }
    }
}

/// Keep the system's native button treatment on each supported macOS release.
struct SetupButtonStyle: ViewModifier {
    var prominent = false
    @Environment(\.previewLegacyAppearance) private var legacyAppearance

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !legacyAppearance {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) }
            else { content.buttonStyle(.bordered) }
        }
    }
}

extension Animation {
    static func panelTransition(duration: TimeInterval) -> Animation {
        if #available(macOS 14.0, *) { return .snappy(duration: duration) }
        return .easeInOut(duration: duration)
    }
}

extension Image {
    @ViewBuilder func statusPulse(isActive: Bool) -> some View {
        if #available(macOS 14.0, *) {
            self.symbolEffect(.pulse, options: .repeating, isActive: isActive)
        } else {
            self
        }
    }
}

// MARK: - Header

/// Sits in the title bar area in window mode, next to the traffic lights, so no space is wasted.
struct PanelHeader<Leading: View, Trailing: View>: View {
    let inWindow: Bool
    let title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            if inWindow { Color.clear.frame(width: PanelMetrics.trafficLightInset - PanelMetrics.padding, height: 1) }
            leading
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
        .frame(height: inWindow ? PanelMetrics.titlebarHeight : 28)
        .padding(.bottom, 10)
    }
}

// MARK: - Buttons

/// Circular toolbar-style icon button with a hover state.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        @State private var hovered = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (hovered ? 0.08 : 0))))
                .contentShape(Circle())
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovered = $0 }
        }
    }
}

/// Small text button used in footers, with a capsule hover highlight.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        @State private var hovered = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hovered ? .primary : .secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.12 : (hovered ? 0.06 : 0))))
                .contentShape(Capsule())
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovered = $0 }
        }
    }
}

/// Full-width row button for grouped lists.
struct RowButtonStyle: ButtonStyle {
    var radius: CGFloat = 9
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, radius: radius)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let radius: CGFloat
        @State private var hovered = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : (hovered && enabled ? 0.05 : 0))))
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .opacity(enabled ? 1 : 0.45)
                .onHover { hovered = $0 }
        }
    }
}

// MARK: - Building blocks

/// A colored rounded-square symbol, as used in System Settings.
struct SettingIcon: View {
    let symbol: String
    let color: Color
    private var highlight: Color {
        if #available(macOS 15.0, *) { return color.mix(with: .white, by: 0.15) }
        let native = NSColor(color)
        return Color(nsColor: native.blended(withFraction: 0.15, of: .white) ?? native)
    }
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [highlight, color], startPoint: .top, endPoint: .bottom)))
            .accessibilityHidden(true)
    }
}

/// The control shares the title line; descriptive text gets the full content width.
struct SettingRow<Trailing: View>: View {
    let symbol: String
    let color: Color
    let title: String
    var caption: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SettingIcon(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 12.5, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    trailing.fixedSize()
                }
                .frame(minHeight: 22)
                if let caption {
                    Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
    }
}

/// Divider inset to line up with row text rather than the icon.
struct InsetDivider: View {
    var leading: CGFloat = 42
    var body: some View { Divider().padding(.leading, leading).padding(.trailing, 10) }
}

/// Inline message with a severity color, an optional action and room for multi-line errors.
struct Banner: View {
    let text: String
    let symbol: String
    let tint: Color
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.system(size: 11.5))
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderless)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.11)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.18)))
    }
}

/// A rounded search field sized for the compact panel.
struct SearchField: View {
    @Binding var text: String
    var identifier: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(L10n.text("ui.search"), text: $text)
                .textFieldStyle(.plain)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("ui.clear"))
                    .accessibilityIdentifier(identifier + "-clear")
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - Source list

struct FollowSystemChoice {
    let selected: Bool
    let action: () -> Void
}

/// Shared by the main panel and onboarding. Height depends only on the total count,
/// so typing in the search field never resizes the popover.
struct SourceList: View {
    let sources: [InputChoice]
    let totalCount: Int
    let selectedID: String?
    let currentID: String
    var followSystem: FollowSystemChoice? = nil
    var sourceIcon: (String) -> NSImage = { _ in MenuBarIcon.image }
    let onSelect: (String) -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    private var scrolls: Bool { totalCount > PanelMetrics.visibleRows }
    private var scrollHeight: CGFloat {
        let rows = CGFloat(PanelMetrics.visibleRows) + 0.5
        return rows * PanelMetrics.rowHeight + rows.rounded(.down) * PanelMetrics.rowSpacing
    }

    var body: some View {
        VStack(spacing: 2) {
            if let followSystem {
                FollowSystemRow(selected: followSystem.selected, action: followSystem.action)
                Divider().padding(.horizontal, 7).padding(.vertical, 2)
            }
            Group {
                if sources.isEmpty {
                    SourceEmptyState(isCatalogEmpty: totalCount == 0)
                        .frame(height: scrolls ? scrollHeight : nil)
                } else if scrolls {
                    ScrollView { rows }
                        .scrollIndicators(.automatic)
                        .frame(height: scrollHeight)
                } else {
                    rows
                }
            }
        }
        .padding(4)
        .modifier(SourceListSurface(usesGlass: followSystem != nil))
    }

    private var rows: some View {
        LazyVStack(spacing: PanelMetrics.rowSpacing) {
            ForEach(sources) { source in
                SourceRow(source: source, icon: sourceIcon(source.id), selected: source.id == selectedID, current: source.id == currentID,
                          increasedContrast: contrast == .increased) { onSelect(source.id) }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct FollowSystemRow: View {
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.text("ui.follow-system"))
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    Text(L10n.text("ui.follow-system-caption"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(selected ? 1 : 0).frame(width: 14)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: PanelMetrics.rowHeight, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(contrast == .increased ? 0.22 : 0.12))
                }
            }
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(L10n.text("ui.follow-system"))
        .accessibilityValue(L10n.text("ui.follow-system-caption"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("follow-system")
    }
}

struct SourceEmptyState: View {
    let isCatalogEmpty: Bool
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: isCatalogEmpty ? "keyboard.badge.ellipsis" : "magnifyingglass")
                .font(.system(size: 20, weight: .light)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(L10n.text(isCatalogEmpty ? "panel.empty" : "ui.no-results"))
                .font(.system(size: 12, weight: .medium))
            Text(L10n.text(isCatalogEmpty ? "ui.add-source" : "ui.try-search"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16).padding(.horizontal, 12)
    }
}

struct SourceRow: View {
    let source: InputChoice
    let icon: NSImage
    let selected: Bool
    let current: Bool
    let increasedContrast: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SourceArtwork(image: icon)
                Text(source.name)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if current { CurrentTag() }
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: PanelMetrics.rowHeight, maxHeight: PanelMetrics.rowHeight, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(increasedContrast ? 0.22 : 0.12))
                }
            }
        }
        .buttonStyle(RowButtonStyle())
        .help(source.name)
        .accessibilityLabel(source.name)
        .accessibilityValue([selected ? L10n.text("ui.target") : nil, current ? L10n.text("ui.current-badge") : nil]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("source-" + source.id)
    }
}

/// Marks the input source the system is using right now.
struct CurrentTag: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.green).frame(width: 5, height: 5)
            Text(L10n.text("ui.current-badge"))
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .accessibilityHidden(true)
    }
}

// MARK: - Window background

/// Observe the actual hosting screen, including a popover opened on another display.
/// Updating a size value preserves the panel's navigation and search state.
struct PanelScreenHeight: NSViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScreenView {
        let view = ScreenView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ScreenView, context: Context) { view.onChange = onChange }

    final class ScreenView: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            guard let window else { return }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
                self?.publishHeight()
            })
            observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.publishHeight()
            })
            publishHeight()
        }

        private func publishHeight() {
            guard let screen = window?.screen else { return }
            let height = max(120, screen.visibleFrame.height - 40)
            // Hosting attachment can occur during a SwiftUI update; publish on the next main turn.
            DispatchQueue.main.async { [weak self, weak screen] in
                guard let self, let screen, self.window?.screen === screen else { return }
                self.onChange?(height)
            }
        }

        private func removeObservers() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }

        deinit { removeObservers() }
    }
}

struct WindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Debug previews can force the reduced-transparency path without changing system settings.
private struct PreviewReduceTransparency: EnvironmentKey { static let defaultValue = false }
private struct PreviewLegacyAppearance: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var previewLegacyAppearance: Bool {
        get { self[PreviewLegacyAppearance.self] }
        set { self[PreviewLegacyAppearance.self] = newValue }
    }
    var previewReduceTransparency: Bool {
        get { self[PreviewReduceTransparency.self] }
        set { self[PreviewReduceTransparency.self] = newValue }
    }
}

/// Opens Keyboard settings; previews never leave the sandboxed demo.
func openKeyboardSettings(isPreview: Bool) {
    guard !isPreview, let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
    NSWorkspace.shared.open(url)
}

/// Keyboard shortcuts for an accessory app, which has no main menu to provide them.
struct HiddenShortcut: View {
    let key: KeyEquivalent
    var modifiers: EventModifiers = .command
    let action: () -> Void
    var body: some View {
        Button("", action: action)
            .keyboardShortcut(key, modifiers: modifiers)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }
}
