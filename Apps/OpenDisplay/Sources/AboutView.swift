#if os(macOS)
import AppKit
import OpenDisplayDesignSystem
import SwiftUI

/// Custom About window, replacing `orderFrontStandardAboutPanel`. The standard panel only shows
/// the icon + version; this one adds what people actually come for — the running version (selectable
/// for bug reports), and links to the project. Accessibility: semantic fonts (respect
/// the user's text-size setting), real `Link` controls (focusable, VoiceOver-labelled), and the
/// decorative icon hidden from assistive tech.
struct AboutView: View {
    private static let repo = "https://github.com/Guydada/OpenDisplay-Lenovo"

    /// A single project link shown both in this window and in Settings → About, so the two surfaces
    /// can never drift apart on titles, icons, or destinations.
    struct AboutLink: Identifiable {
        let title: String
        let systemImage: String
        let url: URL
        var id: String { title }
    }

    /// The project links AboutView offers, reused verbatim by the Settings → About card.
    static let projectLinks: [AboutLink] = [
        AboutLink(title: "OpenDisplay Lenovo on GitHub", systemImage: "globe", url: URL(string: repo)!),
        AboutLink(title: "Upstream OpenDisplay", systemImage: "arrow.triangle.branch", url: URL(string: "https://github.com/aquitaine/OpenDisplay")!),
        AboutLink(title: "Report an issue", systemImage: "ladybug", url: URL(string: "\(repo)/issues/new")!),
        AboutLink(title: "License (GPL-3.0)", systemImage: "checkmark.seal",
                  url: URL(string: "\(repo)/blob/main/LICENSE")!),
    ]

    /// The running build's marketing version ("0.5.1"), reused by the Settings → About card.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    /// The running build number, reused by the Settings → About card.
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: ODSpacing.sm) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("OpenDisplay Lenovo")
                .font(.title2.weight(.semibold))
            Text("Free, open-source display control for macOS.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Version \(Self.version) (build \(Self.build))")
                .font(.callout.monospacedDigit())
                .textSelection(.enabled)
                .accessibilityLabel("Version \(Self.version), build \(Self.build)")
                .padding(.top, 2)

            Divider().padding(.vertical, ODSpacing.xs)

            VStack(alignment: .leading, spacing: ODSpacing.sm) {
                ForEach(Self.projectLinks) { link in
                    aboutLink(link)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ODSpacing.lg)

            Text("© 2026 OpenDisplay contributors")
                .font(.footnote).foregroundStyle(.tertiary)
                .padding(.top, ODSpacing.xs)
        }
        .padding(.vertical, ODSpacing.xl)
        .padding(.horizontal, ODSpacing.xl)
        .frame(width: 300)
    }

    private func aboutLink(_ link: AboutLink) -> some View {
        Link(destination: link.url) {
            Label {
                Text(link.title).font(.callout)
            } icon: {
                Image(systemName: link.systemImage).frame(width: 18)
            }
        }
        .foregroundStyle(ODColor.accent)
        .accessibilityHint("Opens in your browser")
    }
}
#endif
