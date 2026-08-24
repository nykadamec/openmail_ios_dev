import SwiftUI

/// Detail view for a single historic version entry shown from
/// Settings → Version History. Presents the version, build, release date and
/// the changelog bullets for that entry.
struct VersionDetailSheet: View {
    let entry: UpdateHistoryEntry

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if !entry.changelog.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(entry.changelog.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text(LocalizedStringKey(line))
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    } else {
                        Text("settings.changelogEmpty")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle(entry.version)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.version)
                .font(.title2.weight(.semibold))
                .monospacedDigit()

            Text(buildLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var buildLabel: String {
        String(format: String(localized: "settings.changelogVersion"), "\(entry.version) (\(entry.build))")
    }
}

#Preview {
    VersionDetailSheet(
        entry: UpdateHistoryEntry(version: "0.0.20", build: 20, changelog: [
            "First preview line of changes.",
            "Second preview line of changes."
        ])
    )
}
