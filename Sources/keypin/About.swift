import AppKit
import SwiftUI

struct AboutView: View {
    @ObservedObject var model: UpdateViewModel

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    .accessibilityHidden(true)
                Text(L10n.text("app.name")).font(.system(size: 17, weight: .bold))
                Text(versionLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("about-version")
                Text(L10n.text("about.description"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    SettingIcon(symbol: "arrow.down.circle", color: .accentColor)
                    Text(L10n.text("about.updates")).font(.system(size: 12.5, weight: .medium))
                    Spacer(minLength: 6)
                    Button(L10n.text(model.pendingUpdateVersion == nil ? "about.check" : "about.review")) { model.check() }
                        .controlSize(.small)
                        .disabled(!model.canCheckForUpdates)
                        .accessibilityIdentifier("check-updates")
                }
                updateStatus
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 32)
                    .accessibilityIdentifier("update-result")
                Divider().padding(.vertical, 2)
                Toggle(L10n.text("about.automatic-checks"), isOn: Binding(
                    get: { model.automaticallyChecksForUpdates }, set: model.setAutomaticallyChecksForUpdates))
                    .accessibilityIdentifier("automatic-update-checks")
                    .disabled(model.state != .ready)
                Toggle(L10n.text("about.automatic-downloads"), isOn: Binding(
                    get: { model.automaticallyDownloadsUpdates }, set: model.setAutomaticallyDownloadsUpdates))
                    .accessibilityIdentifier("automatic-update-downloads")
                    .disabled(model.state != .ready || !model.automaticallyChecksForUpdates)
                Text(L10n.text("about.automatic-help"))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(radius: 13)

            Text(L10n.format("about.requirements", model.info.minimumSystemVersion, AppBuildInfo.architecture))
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var versionLabel: String {
        if let version = model.info.version, let build = model.info.build {
            return L10n.format("about.version", version, String(build))
        }
        return L10n.text("about.local-build")
    }

    @ViewBuilder private var updateStatus: some View {
        switch model.state {
        case .unconfigured:
            Text(L10n.text("about.update.unconfigured")).foregroundStyle(.secondary)
        case .failed:
            Label(L10n.text("about.update.failed"), systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
        case .ready:
            if let version = model.pendingUpdateVersion {
                Label(L10n.format("about.update.available", version), systemImage: "arrow.down.circle")
                    .foregroundStyle(Color.accentColor)
            } else {
                Text(L10n.text("about.update.idle")).foregroundStyle(.secondary)
            }
        }
    }
}
