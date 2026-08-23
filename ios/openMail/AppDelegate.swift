import UIKit
import BackgroundTasks

/// Application-level lifecycle hook for `openMail`.  Owns the background
/// task registration and hands the system callbacks to
/// `NotificationsCoordinator`.  The struct is exposed to SwiftUI via
/// `@UIApplicationDelegateAdaptor` in `openMailApp.swift`.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                     [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: NotificationsCoordinator.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let appRefresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // The handler runs on a background queue.  Hop to the main actor
            // for the actual work because `NotificationsCoordinator` is
            // @MainActor-isolated.
            Task { @MainActor in
                await NotificationsCoordinator.shared.handleAppRefresh { result in
                    appRefresh.setTaskCompleted(success: result == .newData)
                    NotificationsCoordinator.shared.scheduleNextRefresh()
                }
            }
            appRefresh.expirationHandler = {
                // System reclaimed our time — finish gracefully.
                appRefresh.setTaskCompleted(success: false)
            }
        }
        return true
    }
}