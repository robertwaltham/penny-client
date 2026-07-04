import SwiftUI
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        requestNotificationRegistration(application)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        PushNotificationState.shared.updateDeviceToken(token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    private func requestNotificationRegistration(_ application: UIApplication) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                print("Notification authorization failed: \(error.localizedDescription)")
                return
            }

            guard granted else { return }

            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }
}

@MainActor
final class PushNotificationState {
    static let didUpdateDeviceToken = Notification.Name("PushNotificationState.didUpdateDeviceToken")
    static let shared = PushNotificationState()

    private(set) var deviceToken: String?

    func updateDeviceToken(_ token: String) {
        guard deviceToken != token else { return }
        deviceToken = token
        NotificationCenter.default.post(name: Self.didUpdateDeviceToken, object: nil)
    }
}
