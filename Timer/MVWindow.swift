import AppKit

final class MVWindow: NSWindow {
  convenience init(mainView: NSView) {
    let styleMask: NSWindow.StyleMask = [.closable, .fullSizeContentView, .resizable, .titled]
    let size: CGFloat = 150.0

    let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
    let windowFrame = NSRect(
      x: screenFrame.width / 2 - size / 2,
      y: screenFrame.height / 2 - size / 2,
      width: size,
      height: size
    )

    self.init(
      contentRect: windowFrame,
      styleMask: styleMask,
      backing: .buffered,
      defer: true
    )

    mainView.frame = NSRect(x: 0, y: 0, width: size, height: size)
    mainView.autoresizingMask = [.width, .height]

    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.isMovableByWindowBackground = true
    self.contentAspectRatio = NSSize(width: 1, height: 1)
    self.contentMinSize = NSSize(width: 150, height: 150)
    self.contentMaxSize = NSSize(width: 360, height: 360)
    self.contentView = mainView

    // Create a transparent titlebar accessory to overlay the window (to capture drag events)
    let titleBarController = MVTitlebarAccessoryViewController()
    titleBarController.view.frame = NSRect(x: 0, y: 0, width: size, height: size)
    titleBarController.view.autoresizingMask = [.width, .height]
    self.addTitlebarAccessoryViewController(titleBarController)

    // Hide some of the default window buttons
    self.standardWindowButton(.miniaturizeButton)?.isHidden = true

    // Adjust the close button
    if let closeButton = self.standardWindowButton(.closeButton) {
      var closeFrame = closeButton.frame
      closeFrame.origin.y -= 2
      closeButton.frame = closeFrame
    }
  }
}
