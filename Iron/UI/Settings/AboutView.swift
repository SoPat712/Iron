//
//  AboutView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 04.03.20.
//  Copyright © 2020 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section {
                appSummary
            }

            Section("Iron") {
                aboutLinkRow(
                    AboutLink(
                        title: "Source code",
                        subtitle: "View the project on GitHub",
                        systemImage: "chevron.left.forwardslash.chevron.right",
                        url: URL(string: "https://github.com/karimknaebel/Iron")!
                    )
                )
                aboutLinkRow(
                    AboutLink(
                        title: "Website",
                        subtitle: "Product information and support",
                        systemImage: "globe",
                        url: URL(string: "https://ka.codes")!
                    )
                )
            }

            Section("Privacy") {
                aboutLinkRow(
                    AboutLink(
                        title: "Privacy policy",
                        subtitle: "How Iron handles your information",
                        systemImage: "hand.raised.fill",
                        url: URL(string: "https://iron.ka.codes/privacy.html")!
                    )
                )
                privacySummary
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(IronTheme.background)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: IronTheme.floatingWorkoutBottomClearance - 36)
        }
        .ironDestinationScreen(title: "About Iron")
        .ironScreen()
    }

    private var appSummary: some View {
        HStack(spacing: 16) {
            Image("AppIconRounded")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Iron")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(IronTheme.primaryText)
                Text("Private strength training")
                    .font(.subheadline)
                    .foregroundColor(IronTheme.secondaryText)
                Text("Version \(versionString)")
                    .font(.caption)
                    .foregroundColor(IronTheme.tertiaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func aboutLinkRow(_ row: AboutLink) -> some View {
        Link(destination: row.url) {
            HStack(spacing: 12) {
                Image(systemName: row.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.body)
                        .foregroundColor(IronTheme.primaryText)
                    Text(row.subtitle)
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(IronTheme.tertiaryText)
            }
        }
        .accessibilityHint("Opens in your browser")
    }

    private var privacySummary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.title3.weight(.semibold))
                .foregroundColor(IronTheme.accent)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text("Private by design")
                    .font(.body)
                    .foregroundColor(IronTheme.primaryText)
                Text("Iron has no social feed or public profile. Your workout and body data remain under your control.")
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        #if DEBUG
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return "\(version ?? "?") (\(build ?? "?"))"
        #else
        return version ?? "?"
        #endif
    }
}

private struct AboutLink: Identifiable {
    let title: String
    let subtitle: String
    let systemImage: String
    let url: URL

    var id: String { title }
}

#if DEBUG
struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AboutView().mockEnvironment(weightUnit: .metric)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
