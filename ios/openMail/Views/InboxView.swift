import Combine
import SwiftUI

/// A folder filter for the email list. System folders map to dedicated API
/// flags; custom folders map to their backend id.
enum FolderFilter: Hashable {
    case inbox
    case starred
    case sent
    case spam
    case trash
    case custom(FolderItem)

    var title: String {
        switch self {
        case .inbox: return NSLocalizedString("folder.inbox", comment: "")
        case .starred: return NSLocalizedString("folder.starred", comment: "")
        case .sent: return NSLocalizedString("folder.sent", comment: "")
        case .spam: return NSLocalizedString("folder.spam", comment: "")
        case .trash: return NSLocalizedString("folder.trash", comment: "")
        case .custom(let folder): return folder.name
        }
    }

    var icon: String {
        switch self {
        case .inbox: return "tray"
        case .starred: return "star"
        case .sent: return "paperplane"
        case .spam: return "exclamationmark.triangle"
        case .trash: return "trash"
        case .custom: return "folder"
        }
    }

    var folderParam: String? {
        switch self {
        case .sent: return "sent"
        default: return nil // nil → server defaults to inbox
        }
    }

    var isStarred: Bool? { self == .starred ? true : nil }
    var isSpam: Bool? { self == .spam ? true : nil }
    var isTrash: Bool? { self == .trash ? true : nil }

    var customFolderId: Int? {
        if case .custom(let folder) = self { return folder.id }
        return nil
    }
}

/// The main email list with a stats header, a horizontal folder picker,
/// global search and infinite scrolling.
struct InboxView: View {
    @Environment(AuthStore.self) private var authStore

    private var client: APIClient { authStore.activeClient }
    private let pageSize = 50

    @State private var emails: [EmailSummary] = []
    @State private var total = 0
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasLoadedSuccessfully = false
    @State private var initialLoadFailed = false
    @State private var refreshFeedback: RefreshFeedback?
    @State private var refreshFailureMessageKey: String?
    /// Invalidates every older folder/search/refresh request when a new one
    /// starts. URLSession cancellation alone is not sufficient here because
    /// a response may already be queued for delivery.
    @State private var requestGeneration = 0

    /// Overlay of locally starred ids – the model's `is_starred` flag cannot
    /// be mutated in place, so list rows read from this set instead.
    @State private var starredIDs: Set<Int> = []

    @State private var currentFolder: FolderFilter = .inbox
    @State private var customFolders: [FolderItem] = []
    @State private var stats: Stats?

    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?

    /// The row that was visible when the user opened a detail view. The flag
    /// keeps restoration opt-in, so the initial list appearance never jumps.
    @State private var lastVisibleEmailID: Int?
    @State private var shouldRestoreScroll = false

    /// Poslední úspěšné načtení seznamu – nutriční údaj pro podtitul navbaru
    /// („sync před X"). Obnovuje se v `loadWithSync` po každém fetchi.
    @State private var lastSyncAt: Date?
    /// Tikání pro čerstvý relativní čas v podtitulu („sync před X").
    @State private var now = Date()
    /// Rozbalený stav search pillu v glass navbaru.
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool

    private var allFolders: [FolderFilter] {
        [.inbox, .starred, .sent, .spam, .trash] + customFolders.map { FolderFilter.custom($0) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.craftBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    craftNavbar
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    folderChipsRow
                        .padding(.top, 10)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                if emails.isEmpty && isLoading {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, 80)
                                } else if emails.isEmpty && hasLoadedSuccessfully {
                                    emptyState
                                } else if emails.isEmpty && initialLoadFailed {
                                    Text(LocalizedStringKey(refreshFailureMessageKey ?? "errors.generic"))
                                        .font(.craft(size: 15))
                                        .foregroundStyle(Color.craftSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, 90)
                                } else {
                                    ForEach(Array(emails.enumerated()), id: \.element.id) { index, email in
                                        row(for: email)
                                            .id(email.id)
                                            .simultaneousGesture(TapGesture().onEnded {
                                                // The tapped row is necessarily visible and
                                                // is a more reliable anchor than LazyVStack's
                                                // prefetch-driven onAppear callbacks.
                                                lastVisibleEmailID = email.id
                                                shouldRestoreScroll = true
                                            })
                                        if index == emails.count - 1 {
                                            loadMoreFooter
                                        }
                                    }
                                }

                                // Volný prostor pod posledním mailem, aby ho
                                // nepřekrýval plovoucí tab bar z MainTab.
                                Color.clear.frame(height: 100)
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 4)
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .refreshable {
                            await reload()
                        }
                        .onAppear {
                            guard shouldRestoreScroll, let id = lastVisibleEmailID,
                                  !emails.isEmpty else { return }
                            // Wait for LazyVStack to materialize the anchor. A single
                            // deferred, non-animated scroll avoids a layout feedback loop.
                            DispatchQueue.main.async {
                                guard shouldRestoreScroll, emails.contains(where: { $0.id == id }) else { return }
                                var transaction = Transaction()
                                transaction.animation = nil
                                withTransaction(transaction) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                                shouldRestoreScroll = false
                            }
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if let refreshFeedback {
                    RefreshFeedbackView(feedback: refreshFeedback) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.refreshFeedback = nil
                        }
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let refreshFailureMessageKey {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.refreshFailureMessageKey = nil
                        }
                    } label: {
                        Label(LocalizedStringKey(refreshFailureMessageKey), systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 0.75))
                            .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await loadWithSync(isRefresh: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .newEmailReceived)) { _ in
                Task { await reload() }
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in
                // Udržuje čerstvý relativní čas v podtitulu („sync před X").
                now = date
            }
            .onChange(of: currentFolder) {
                lastVisibleEmailID = nil
                shouldRestoreScroll = false
                searchTask?.cancel()
                Task { await fetch(reset: true, isRefresh: false) }
            }
            .onChange(of: searchText) { _, _ in
                lastVisibleEmailID = nil
                shouldRestoreScroll = false
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled else { return }
                    await fetch(reset: true, isRefresh: false)
                }
            }
        }
    }

    // MARK: - Craft navbar (směr C)

    /// Plovoucí glass kapsle: pozdrav + titulek + podtitul, akce hledat +
    /// napsat a funkční search pill napojený na `searchText`.
    private var craftNavbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greetingText)
                        .font(.craft(size: 13, weight: .bold))
                        .foregroundStyle(Color.craftAccent)
                        .lineLimit(1)
                    Text(navTitleText)
                        .font(.craft(size: 22, weight: .heavy))
                        .foregroundStyle(Color.craftInk)
                        .lineLimit(1)
                    Text(navSubtitleText)
                        .font(.craft(size: 12))
                        .foregroundStyle(Color.craftSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                HStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy) {
                            isSearchExpanded.toggle()
                            if isSearchExpanded {
                                isSearchFocused = true
                            } else {
                                isSearchFocused = false
                                searchText = ""
                            }
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.craftInk)
                            .frame(width: 36, height: 36)
                            .background(Color.craftPill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("action.search"))

                    NavigationLink {
                        ComposerView()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.craftInk, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("action.compose"))
                }
                .padding(.top, 2)
            }

            searchPill
        }
        .padding(14)
        .craftGlass()
    }

    /// Search pill: ve sbaleném stavu hint, po rozbalení funkční TextField
    /// svázaný s existujícím `searchText` (debounce 350 ms zůstává).
    private var searchPill: some View {
        Group {
            if isSearchExpanded {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.craftSecondary)
                    TextField(
                        LocalizedStringKey("inbox.searchHint"),
                        text: $searchText
                    )
                    .font(.craft(size: 14))
                    .foregroundStyle(Color.craftInk)
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.craftSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("action.cancel"))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                Button {
                    withAnimation(.snappy) {
                        isSearchExpanded = true
                        isSearchFocused = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.craftSecondary)
                        Text("inbox.searchHint")
                            .font(.craft(size: 14))
                            .foregroundStyle(Color.craftSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("action.search"))
            }
        }
        .background(Color.craftPill, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Titulek navbaru: ve složce Inbox „Doručená", jinde název složky.
    private var navTitleText: String {
        if currentFolder == .inbox {
            return String(localized: "inbox.heading")
        }
        return currentFolder.title
    }

    /// Podtitul: „N nepřečtených · sync před X" (sync část jen když je známá).
    private var navSubtitleText: String {
        let unread = stats?.unread ?? 0
        let unreadWord = String(localized: "inbox.unread")
        guard let sync = syncRelativeText, !sync.isEmpty else {
            return "\(unread) \(unreadWord)"
        }
        return "\(unread) \(unreadWord) · sync \(sync)"
    }

    /// Relativní čas posledního syncu („před 1 min"), locale-aware.
    private var syncRelativeText: String? {
        guard let last = lastSyncAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: last, relativeTo: now)
    }

    /// Pozdrav podle denní doby + křestní jméno z AuthStore.
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let key: String
        if hour >= 5 && hour < 10 {
            key = "inbox.greeting.morning"
        } else if hour >= 10 && hour < 18 {
            key = "inbox.greeting.afternoon"
        } else {
            key = "inbox.greeting.evening"
        }
        return String(format: NSLocalizedString(key, comment: ""), greetingName)
    }

    private var greetingName: String {
        if let first = authStore.user?.first_name?
            .trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            return first
        }
        if let full = authStore.user?.fullName, !full.isEmpty {
            return full
        }
        return authStore.user?.username ?? ""
    }

    // MARK: - Folder chips (teplé, horizontální scroll pod navbar kapslí)

    private var folderChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allFolders, id: \.self) { folder in
                    craftChip(for: folder)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
        }
    }

    private func craftChip(for folder: FolderFilter) -> some View {
        let selected = folder == currentFolder
        return Button {
            withAnimation(.snappy) { currentFolder = folder }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: folder.icon)
                    .font(.craft(size: 12, weight: .semibold))
                Text(folder.title)
                    .font(.craft(size: 13, weight: selected ? .bold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(selected ? AnyShapeStyle(Color.craftInk) : AnyShapeStyle(Color.white))
            )
            .overlay(
                Capsule()
                    .stroke(
                        selected ? Color.craftInk : Color.craftInk.opacity(0.12),
                        lineWidth: 1
                    )
            )
            .foregroundStyle(selected ? Color.white : Color.craftInk)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundStyle(Color.craftSecondary)
            Text("refresh.emptyInbox")
                .font(.craft(size: 17, weight: .semibold))
                .foregroundStyle(Color.craftSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }

    private var loadMoreFooter: some View {
        Group {
            if isLoadingMore {
                ProgressView()
                    .padding(.vertical, 20)
            } else {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        guard !isLoadingMore, emails.count < total else { return }
                        Task { await fetch(reset: false, isRefresh: false) }
                    }
            }
        }
    }

    // MARK: - Row (Craft karta: bílá, radius 20, bez stínu)

    private func row(for email: EmailSummary) -> some View {
        let sender = email.sender_name ?? email.sender_email ?? "?"
        let time = smartTimeLabel(from: email.received_at ?? email.created_at)

        return NavigationLink {
            EmailDetailView(emailID: email.id)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                // Unread tečka 8×8 – místo se zachovává i u přečtených.
                Circle()
                    .fill(Color.craftUnread)
                    .frame(width: 8, height: 8)
                    .opacity(email.isRead ? 0 : 1)

                CraftAvatar(sender: sender)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(sender)
                            .font(.craft(size: 13, weight: .bold))
                            .foregroundStyle(Color.craftInk)
                            .lineLimit(1)
                        if !time.isEmpty {
                            Text("· \(time)")
                                .font(.craft(size: 13))
                                .foregroundStyle(Color.craftInk)
                                .lineLimit(1)
                                .layoutPriority(1)
                        }
                        Spacer(minLength: 0)
                    }

                    if let subject = email.subject, !subject.isEmpty {
                        Text(subject)
                            .font(.craft(size: 14))
                            .foregroundStyle(Color.craftSubject)
                            .lineLimit(1)
                    }

                    if let preview = email.preview, !preview.isEmpty {
                        Text(preview)
                            .font(.craft(size: 13))
                            .foregroundStyle(Color.craftSecondary)
                            .lineLimit(2)
                    }
                }

                starButton(for: email)
            }
            .padding(12)
            .frame(minHeight: 68)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private func starButton(for email: EmailSummary) -> some View {
        let starred = starredIDs.contains(email.id)
        return Button {
            Task { await toggleStar(email) }
        } label: {
            Image(systemName: starred ? "star.fill" : "star")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(starred ? Color.craftAccent : Color.craftSecondary)
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(starred ? "action.unstar" : "action.star"))
    }

    // MARK: - Data

    private func loadMeta() async {
        let token = authStore.sessionToken()
        do {
            async let stats = try token.client.stats()
            async let folders = try token.client.folders()
            let (s, f) = try await (stats, folders)
            guard authStore.isCurrent(token) else { return }
            self.stats = s
            customFolders = f
        } catch APIClientError.unauthorized {
            if authStore.isCurrent(token) { await handleUnauthorized(token) }
        } catch {
            // Non-fatal – header and custom filters can stay empty.
        }
    }

    private func reload() async {
        // Pull-to-refresh must not preserve the pre-refresh scroll anchor.
        // Without this reset the subsequent onAppear handler would call
        // proxy.scrollTo(id) and pull the list back to the stale row,
        // conflicting with the native pull gesture.
        lastVisibleEmailID = nil
        shouldRestoreScroll = false
        searchTask?.cancel()
        await loadWithSync(isRefresh: true)
    }

    /// Shared sequential flow: sync with Resend first, then fetch the list.
    /// A sync failure must never block the list – it is only logged and the
    /// fetch always runs.
    private func loadWithSync(isRefresh: Bool) async {
        await loadMeta()
        do {
            _ = try await authStore.activeClient.syncEmails()
        } catch {
            #if DEBUG
            print("[Inbox] sync failed: \(String(describing: error))")
            #endif
        }
        await fetch(reset: true, isRefresh: isRefresh)
        lastSyncAt = Date()
        now = Date()
    }

    private func fetch(reset: Bool, isRefresh: Bool) async {
        let token = authStore.sessionToken()
        requestGeneration += 1
        let generation = requestGeneration
        if reset && !isRefresh {
            emails = []
            total = 0
            hasLoadedSuccessfully = false
            initialLoadFailed = false
            refreshFailureMessageKey = nil
        }
        if reset {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        defer {
            if generation == requestGeneration {
                isLoading = false
                isLoadingMore = false
            }
        }

        let oldIDs = Set(emails.map(\.id))
        let offset = reset ? 0 : emails.count
        let folder = currentFolder
        let query = searchText.trimmingCharacters(in: .whitespaces)
        do {
            let page = try await token.client.emails(
                folder: folder.folderParam,
                q: query.isEmpty ? nil : query,
                starred: folder.isStarred,
                isSpam: folder.isSpam,
                isTrash: folder.isTrash,
                customFolderId: folder.customFolderId,
                direction: folder.folderParam == "sent" ? "outbound" : "inbound",
                limit: pageSize,
                offset: offset
            )
            guard generation == requestGeneration, authStore.isCurrent(token) else { return }
            if reset {
                // During pull-to-refresh the old list stays visible. Commit
                // the decoded response as one state update after success.
                emails = page.emails
                total = page.total
                starredIDs = Set(page.emails.filter(\.isStarred).map(\.id))
                hasLoadedSuccessfully = true
                initialLoadFailed = false
                refreshFailureMessageKey = nil
                if isRefresh {
                    let newCount = page.emails.reduce(into: 0) { count, email in
                        if !oldIDs.contains(email.id) { count += 1 }
                    }
                    showRefreshFeedback(.success(newCount))
                }
            } else {
                total = page.total
                emails.append(contentsOf: page.emails)
            }
        } catch APIClientError.unauthorized {
            guard generation == requestGeneration, authStore.isCurrent(token) else { return }
            if isRefresh { refreshFailureMessageKey = "errors.unauthorized" }
            if authStore.isCurrent(token) { await handleUnauthorized(token) }
        } catch APIClientError.network(.cancelled) {
            // Cancellation is expected when the user changes folder/search.
        } catch is CancellationError {
            // Do not turn structured-concurrency cancellation into an error UI.
        } catch {
            guard generation == requestGeneration, authStore.isCurrent(token) else { return }
            if reset {
                if !isRefresh { initialLoadFailed = true }
                refreshFailureMessageKey = localizedRefreshFailure(for: error)
            }
        }
    }

    private func localizedRefreshFailure(for error: Error) -> String {
        #if DEBUG
        print("[Inbox] refresh failed: \(String(describing: error))")
        #endif
        switch error {
        case APIClientError.network:
            return "errors.network"
        case APIClientError.http:
            return "errors.serverUnavailable"
        case APIClientError.decode, APIClientError.unexpectedResponse, APIClientError.server:
            return "errors.unexpectedResponse"
        default:
            return "errors.generic"
        }
    }

    private func showRefreshFeedback(_ feedback: RefreshFeedback) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            refreshFeedback = feedback
        }
    }

    private func toggleStar(_ email: EmailSummary) async {
        let token = authStore.sessionToken()
        let newValue = !starredIDs.contains(email.id)
        do {
            _ = try await token.client.patchEmail(id: email.id, fields: ["is_starred": newValue ? 1 : 0])
            guard authStore.isCurrent(token) else { return }
            if newValue {
                starredIDs.insert(email.id)
            } else {
                starredIDs.remove(email.id)
            }
        } catch APIClientError.unauthorized {
            if authStore.isCurrent(token) { await handleUnauthorized(token) }
        } catch {
            // Keep the previous visual state on failure.
        }
    }

    private func handleUnauthorized(_ token: AuthStore.SessionToken) async {
        guard authStore.isCurrent(token) else { return }
        await authStore.logout()
    }
}

#Preview {
    InboxView()
        .environment(AuthStore())
}
