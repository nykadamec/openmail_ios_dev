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

    private let client = APIClient.shared
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

    private var allFolders: [FolderFilter] {
        [.inbox, .starred, .sent, .spam, .trash] + customFolders.map { FolderFilter.custom($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        statsHeader

                        Color.clear.frame(height: 8)

                        if emails.isEmpty && isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                        } else if emails.isEmpty && hasLoadedSuccessfully {
                            emptyState
                        } else if emails.isEmpty && initialLoadFailed {
                            Text(LocalizedStringKey(refreshFailureMessageKey ?? "errors.generic"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
                    }
                    .padding(.bottom, 24)
                }
                .background(Color(.systemBackground))
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
            .navigationTitle(Text(currentFolder.title))
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "action.search")
            .refreshable {
                await reload()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ComposerView()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .accessibilityLabel("action.compose")
                    }
                }
            }
            .task {
                await loadMeta()
            await fetch(reset: true, isRefresh: false)
            }
            .onChange(of: currentFolder) {
                lastVisibleEmailID = nil
                shouldRestoreScroll = false
                searchTask?.cancel()
                Task { await fetch(reset: true, isRefresh: false) }
            }
            .onChange(of: searchText) {
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

    // MARK: - Sections

    private var statsHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(stats?.unread ?? 0)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("inbox.unread")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Folder picker pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(allFolders, id: \.self) { folder in
                        chip(for: folder)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 300)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func chip(for folder: FolderFilter) -> some View {
        let selected = folder == currentFolder
        return Button {
            withAnimation(.snappy) { currentFolder = folder }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: folder.icon)
                    .font(.caption)
                Text(folder.title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemBackground)))
            )
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundStyle(Color(.tertiaryLabel))
            Text("refresh.emptyInbox")
                .font(.headline)
                .foregroundStyle(.secondary)
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

    // MARK: - Row

    private func row(for email: EmailSummary) -> some View {
        let sender = email.sender_name ?? email.sender_email ?? "?"

        return NavigationLink {
            EmailDetailView(emailID: email.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Unread dot
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 9, height: 9)
                    .padding(.top, 19)
                    .opacity(email.isRead ? 0 : 1)

                AvatarView(name: sender)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(sender)
                            .font(.subheadline.weight(email.isRead ? .regular : .semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(smartTimeLabel(from: email.received_at ?? email.created_at))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let subject = email.subject, !subject.isEmpty {
                        Text(subject)
                            .font(.callout.weight(email.isRead ? .regular : .semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }

                    if let preview = email.preview, !preview.isEmpty {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                starButton(for: email)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func starButton(for email: EmailSummary) -> some View {
        let starred = starredIDs.contains(email.id)
        return Button {
            Task { await toggleStar(email) }
        } label: {
            Image(systemName: starred ? "star.fill" : "star")
                .font(.system(size: 17))
                .foregroundStyle(starred ? Color.yellow : Color(.tertiaryLabel))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(starred ? "action.unstar" : "action.star")
    }

    // MARK: - Data

    private func loadMeta() async {
        do {
            async let stats = try client.stats()
            async let folders = try client.folders()
            let (s, f) = try await (stats, folders)
            self.stats = s
            customFolders = f
        } catch APIClientError.unauthorized {
            await handleUnauthorized()
        } catch {
            // Non-fatal – header and custom filters can stay empty.
        }
    }

    private func reload() async {
        await loadMeta()
        await fetch(reset: true, isRefresh: true)
    }

    private func fetch(reset: Bool, isRefresh: Bool) async {
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
            let page = try await client.emails(
                folder: folder.folderParam,
                q: query.isEmpty ? nil : query,
                starred: folder.isStarred,
                isSpam: folder.isSpam,
                isTrash: folder.isTrash,
                customFolderId: folder.customFolderId,
                limit: pageSize,
                offset: offset
            )
            guard generation == requestGeneration else { return }
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
            guard generation == requestGeneration else { return }
            if isRefresh { refreshFailureMessageKey = "errors.unauthorized" }
            await handleUnauthorized()
        } catch APIClientError.network(.cancelled) {
            // Cancellation is expected when the user changes folder/search.
        } catch is CancellationError {
            // Do not turn structured-concurrency cancellation into an error UI.
        } catch {
            guard generation == requestGeneration else { return }
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
        let newValue = !starredIDs.contains(email.id)
        do {
            _ = try await client.patchEmail(id: email.id, fields: ["is_starred": newValue ? 1 : 0])
            if newValue {
                starredIDs.insert(email.id)
            } else {
                starredIDs.remove(email.id)
            }
        } catch APIClientError.unauthorized {
            await handleUnauthorized()
        } catch {
            // Keep the previous visual state on failure.
        }
    }

    private func handleUnauthorized() async {
        await authStore.logout()
    }
}

#Preview {
    InboxView()
        .environment(AuthStore())
}
