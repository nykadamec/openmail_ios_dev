import Foundation
import UIKit
import UserNotifications
import BackgroundTasks

/// Coordinates local notifications for newly received emails.
///
/// The coordinator is intentionally self-contained: it owns the
/// `UNUserNotificationCenter` delegate, persists the per-profile watermark of
/// the last seen email id, and triggers a notification when the inbox contains
/// ids that have not been seen before.  No remote push (APNs) is involved —
/// background refresh uses `BGAppRefreshTask`.
@MainActor
final class NotificationsCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsCoordinator()

    /// Background task identifier registered in Info.plist
    /// (`BGTaskSchedulerPermittedIdentifiers`).  Must match.
    static let backgroundTaskIdentifier = "nykadamec.openmail.refresh"

    /// Minimum interval (seconds) between background refreshes.  iOS honors
    /// only a lower bound on this value.
    static let backgroundRefreshIntervalSeconds: TimeInterval = 15 * 60

    /// Storage key prefix for the watermark.  Per-profile watermarks keep the
    /// behaviour correct when the user switches between server profiles.
    private let watermarkKeyPrefix = "openmail.notifications.lastSeenID."

    private let defaults = UserDefaults.standard
    private let notificationCenter = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        notificationCenter.delegate = self
    }

    // MARK: - Authorization

    enum AuthorizationState {
        case authorized
        case denied
        case notDetermined
        case provisional
    }

    /// Returns the current iOS-level authorization state.
    func authorizationState() async -> AuthorizationState {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .ephemeral: return .authorized
        case .denied: return .denied
        case .provisional: return .provisional
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// Requests banner + sound authorization.  Idempotent — if the user has
    /// already answered, the cached state is returned without prompting.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> AuthorizationState {
        let current = await authorizationState()
        if current == .notDetermined {
            do {
                _ = try await notificationCenter.requestAuthorization(
                    options: [.alert, .badge, .sound]
                )
            } catch {
                // Failure to request is non-fatal — leave the state as-is.
            }
        }
        return await authorizationState()
    }

    // MARK: - Background refresh

    /// Schedules the next background refresh.  Call when the app moves to
    /// the background.  iOS decides when the system actually wakes the app.
    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(
            timeIntervalSinceNow: Self.backgroundRefreshIntervalSeconds
        )
        // `submit(_:)` was deprecated in iOS 27.0; the modern API surfaces
        // every error via a completion handler instead of throwing.  We
        // use the new API and silently ignore all failures because most of
        // them are non-fatal (simulator, background refresh disabled in
        // iOS Settings, …).
        BGTaskScheduler.shared.submitTaskRequest(request) { _ in
            // No-op: best-effort background scheduling.
        }
    }

    /// Performs a single background refresh: queries the inbox for the active
    /// profile, compares against the watermark, and posts notifications for
    /// any new ids.  Calls `completion` with the BG result so the OS knows
    /// whether to schedule another attempt.
    func handleAppRefresh(client: APIClient, profileID: UUID,
                          completion: @escaping (UIBackgroundFetchResult) -> Void) async {
        let state = await authorizationState()
        guard state == .authorized || state == .provisional else {
            completion(.noData)
            return
        }
        do {
            let page = try await client.emails(limit: 5)
            await processInboxPage(page, profileID: profileID)
            completion(.newData)
        } catch APIClientError.unauthorized {
            completion(.failed)
        } catch {
            completion(.failed)
        }
    }

    /// Variant used when there is no explicit APIClient in scope.  Loads the
    /// active profile from a fresh `ServerProfileStore` (UserDefaults-backed)
    /// and constructs an `APIClient` that restores its session cookie from
    /// the Keychain on first use.
    func handleAppRefresh(completion: @escaping (UIBackgroundFetchResult) -> Void) async {
        let store = ServerProfileStore()
        guard let active = store.activeProfile else {
            completion(.noData)
            return
        }
        let client = APIClient(baseURL: active.baseURL, profileID: active.id)
        _ = client.restorePersistedSession()
        await handleAppRefresh(client: client, profileID: active.id, completion: completion)
    }

    // MARK: - Watermark

    private func watermarkKey(for profileID: UUID) -> String {
        watermarkKeyPrefix + profileID.uuidString
    }

    private func lastSeenID(for profileID: UUID) -> Int {
        defaults.integer(forKey: watermarkKey(for: profileID))
    }

    private func setLastSeenID(_ id: Int, for profileID: UUID) {
        defaults.set(id, forKey: watermarkKey(for: profileID))
    }

    /// Compares the freshly fetched page against the watermark and posts a
    /// notification per unseen email.  Updates the watermark regardless of
    /// whether notifications were posted, so a re-run cannot double-post.
    private func processInboxPage(_ page: EmailPage, profileID: UUID) async {
        let inbox = page.emails.filter { email in
            email.isSpam == false && email.isTrash == false
        }
        guard !inbox.isEmpty else { return }
        let highestSeen = inbox.map { $0.id }.max() ?? 0
        let watermark = lastSeenID(for: profileID)
        // First run for this profile — set the watermark silently and exit
        // so we never flood the user with notifications on first install.
        if watermark == 0 {
            setLastSeenID(highestSeen, for: profileID)
            return
        }
        // Inbox is sorted newest-first; emit one notification per unseen id.
        let unseen = inbox.filter { $0.id > watermark }
        for email in unseen.sorted(by: { $0.id < $1.id }) {
            await postNotification(for: email)
        }
        setLastSeenID(highestSeen, for: profileID)
    }

    private func postNotification(for email: EmailSummary) async {
        let content = UNMutableNotificationContent()
        let sender = email.sender_name ?? email.sender_email ?? ""
        let subject = email.subject ?? ""
        content.title = String(localized: "notifications.newEmailTitle")
        content.body = String(
            localized: "notifications.newEmailBody \(sender) \(subject)"
        )
        content.sound = .default
        content.threadIdentifier = "openmail.inbox.\(email.id)"
        content.userInfo = ["emailID": email.id]

        let openAction = UNNotificationAction(
            identifier: "OPEN_INBOX",
            title: String(localized: "notifications.openAction"),
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "OPEN_INBOX",
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        notificationCenter.setNotificationCategories([category])
        content.categoryIdentifier = "OPEN_INBOX"

        let request = UNNotificationRequest(
            identifier: "inbox.email.\(email.id)",
            content: content,
            trigger: nil
        )
        do {
            try await notificationCenter.add(request)
        } catch {
            // Best effort.
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners even when the app is in the foreground, per the agreed
    /// scope ("Vždy (i při otevřené app)").
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}