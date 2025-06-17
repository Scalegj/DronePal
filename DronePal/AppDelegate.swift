import UIKit
import CloudKit

/// A custom notification name used to signal that CloudKit data has changed.
extension Notification.Name {
    static let cloudKitDataChanged = Notification.Name("cloudKitDataChangedNotification")
}

class AppDelegate: NSObject, UIApplicationDelegate {
    
    // This is called when the app finishes launching.
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // Register for SILENT remote notifications. This is the key for CloudKit sync.
        application.registerForRemoteNotifications()
        return true
    }
    
    // This is called when the app successfully registers for remote notifications.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        AppLogger.general.info("Successfully registered for remote notifications with device token: \(token)")
    }
    
    // This is called when the app fails to register for remote notifications.
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLogger.general.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // This method is called when a remote notification arrives while the app is running or in the background.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        // ** THE FIX IS HERE **
        // The API changed. We now use the initializer `CKNotification(fromRemoteNotificationDictionary:)`
        if let _ = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            AppLogger.network.info("Received a CloudKit push notification.")
            
            // Post a notification that our AppViewModel will be listening for.
            // This tells the ViewModel to fetch the latest changes from the server.
            NotificationCenter.default.post(name: .cloudKitDataChanged, object: nil)
            
            // Inform the system that we have new data.
            completionHandler(.newData)
        } else {
            // It's some other kind of push notification.
            completionHandler(.noData)
        }
    }
}
