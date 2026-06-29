import AppKit
import UserNotifications

extension AppDelegate {
  nonisolated func userNotificationCenter(
    _: UNUserNotificationCenter,
    willPresent _: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .sound])
  }

  nonisolated func userNotificationCenter(
    _: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void) {
    let actionIdentifier = response.actionIdentifier
    let controllerIdentifier = response.notification.request.content.userInfo[
      MVNotificationUserInfoKeys.controllerIdentifier
    ] as? String

    completionHandler()

    DispatchQueue.main.async { [weak self] in
      self?.handleNotificationAction(actionIdentifier, controllerIdentifier: controllerIdentifier)
    }
  }

  func registerNotificationCategories() {
    let restartAction = UNNotificationAction(
      identifier: MVNotificationIdentifiers.restartTimerActionIdentifier,
      title: "Restart",
      options: []
    )
    let addFiveMinutesAction = UNNotificationAction(
      identifier: MVNotificationIdentifiers.addFiveMinutesActionIdentifier,
      title: "+5 min",
      options: []
    )
    let stopAction = UNNotificationAction(
      identifier: MVNotificationIdentifiers.stopTimerActionIdentifier,
      title: "Stop",
      options: [.destructive]
    )
    let category = UNNotificationCategory(
      identifier: MVNotificationIdentifiers.timerCompleteCategoryIdentifier,
      actions: [restartAction, addFiveMinutesAction, stopAction],
      intentIdentifiers: [],
      options: []
    )

    UNUserNotificationCenter.current().setNotificationCategories([category])
  }

  private func handleNotificationAction(_ actionIdentifier: String, controllerIdentifier: String?) {
    let controller = self.controller(matching: controllerIdentifier)

    switch actionIdentifier {
    case MVNotificationIdentifiers.restartTimerActionIdentifier:
      controller.restartLastTimer()

    case MVNotificationIdentifiers.addFiveMinutesActionIdentifier:
      controller.addTime(seconds: CGFloat(5 * 60))

    case MVNotificationIdentifiers.stopTimerActionIdentifier:
      controller.stopTimer()

    case UNNotificationDefaultActionIdentifier:
      controller.window?.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)

    default:
      break
    }
  }
}
