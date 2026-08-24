import SwiftUI

/// Minimal account detail reachable from the Settings profile card.
///
/// The card on the parent screen already shows the same avatar, username and
/// e-mail; this view intentionally only repeats those values plus a sign-out
/// affordance so the detail screen stays focused.
struct ProfileDetailView: View {
    @Environment(AuthStore.self) private var authStore

    let user: User

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0, green: 122.0/255.0, blue: 1))
                            .frame(width: 88, height: 88)
                        Text(String(user.username.prefix(1).uppercased()))
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Text(user.username)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(user.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .listRowBackground(Color(.systemBackground))
            }

            Section {
                Button(role: .destructive) {
                    Task { await authStore.logout() }
                } label: {
                    Label("action.signout", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
        }
        .navigationTitle("settings.profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ProfileDetailView(user: ProfileDetailView.previewUser)
    }
    .environment(AuthStore())
}

extension ProfileDetailView {
    static var previewUser: User {
        let json = #"{"id":1,"username":"dominik","email":"dominik@adamec.pro"}"#
        let data = Data(json.utf8)
        return try! JSONDecoder().decode(User.self, from: data)
    }
}
