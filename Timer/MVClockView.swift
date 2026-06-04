import AppKit

final class MVClockView: NSView {
  enum DisplayMode: String, CaseIterable {
    case analog
    case digital

    static var saved: DisplayMode {
      let rawValue = UserDefaults.standard.string(forKey: MVUserDefaultsKeys.displayMode)
      return rawValue.flatMap(DisplayMode.init(rawValue:)) ?? .analog
    }

    var title: String {
      switch self {
      case .analog: "Analog"
      case .digital: "Digital"
      }
    }
  }

  override var mouseDownCanMoveWindow: Bool { false }

  private static let minutesFont = NSFont.monospacedDigitSystemFont(ofSize: 35, weight: .medium)
  private static let secondsFont = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .regular)
  private static let baseSize: CGFloat = 150.0

  private let progressView = MVClockProgressView()
  private let arrowView = MVClockArrowView(center: CGPoint(x: 75, y: 75))
  private let clockFaceView = MVClockFaceView(frame: NSRect(x: 16, y: 15, width: 118, height: 118))

  private let pauseIconImageView: NSImageView = {
    let view = NSImageView(frame: NSRect(x: 70, y: 99, width: 10, height: 12))
    view.image = NSImage(resource: .iconPause)
    view.alphaValue = 0.0
    return view
  }()

  private let timerTimeLabel: MVLabel = {
    let label = MVLabel(frame: NSRect(x: 0, y: 94, width: 150, height: 20))
    label.font = NSFont.systemFont(ofSize: 15, weight: .medium)
    label.alignment = .center
    label.textColor = NSColor(resource: .timerTime)
    return label
  }()

  private let digitalTimeLabel: MVLabel = {
    let label = MVLabel(frame: NSRect(x: 0, y: 54, width: 150, height: 42))
    label.string = "00:00"
    label.font = NSFont.monospacedDigitSystemFont(ofSize: 38, weight: .semibold)
    label.alignment = .center
    label.textColor = NSColor(resource: .minutes)
    label.alphaValue = 0.0
    return label
  }()

  private let digitalStatusLabel: MVLabel = {
    let label = MVLabel(frame: NSRect(x: 0, y: 38, width: 150, height: 18))
    label.string = ""
    label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    label.alignment = .center
    label.textColor = NSColor(resource: .timerTime)
    label.alphaValue = 0.0
    return label
  }()

  private lazy var displayModeControl: NSSegmentedControl = {
    let control = NSSegmentedControl(
      labels: ["Dial", "Digital"],
      trackingMode: .selectOne,
      target: self,
      action: #selector(self.pickDisplayMode)
    )
    control.segmentStyle = .capsule
    control.selectedSegment = self.displayMode == .analog ? 0 : 1
    control.setToolTip("Analog timer", forSegment: 0)
    control.setToolTip("Digital timer", forSegment: 1)
    return control
  }()

  private let minutesLabel: MVLabel = {
    let label = MVLabel(frame: NSRect(x: 0, y: 57, width: 150, height: 30))
    label.string = ""
    label.font = MVClockView.minutesFont
    label.alignment = .center
    label.textColor = NSColor(resource: .minutes)
    return label
  }()

  private let secondsLabel: MVLabel = {
    let label = MVLabel(frame: NSRect(x: 0, y: 38, width: 150, height: 20))
    label.font = MVClockView.secondsFont
    label.alignment = .center
    label.textColor = NSColor(resource: .seconds)
    return label
  }()

  private let minutesLabelSuffixWidth = "'".size(withAttributes: [.font: MVClockView.minutesFont]).width
  private let minutesLabelSecondsSuffixWidth = "\"".size(withAttributes: [.font: MVClockView.minutesFont]).width
  private let secondsSuffixWidth = "'".size(withAttributes: [.font: MVClockView.secondsFont]).width
  private lazy var timerTimeLabelFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "jj:mm", options: 0, locale: Locale.current)
    return formatter
  }()
  var session = TimerSession()
  var inputSeconds: Bool {
    get { self.session.inputSeconds }
    set { self.session.inputSeconds = newValue }
  }
  var lastTimerSeconds: CGFloat? {
    self.session.lastTimerSeconds
  }
  var inDock: Bool = false {
    didSet {
      if !self.inDock {
        self.removeBadge()
      }
      self.updateBadge()
    }
  }
  var windowIsVisible: Bool = false {
    didSet {
      if self.windowIsVisible {
        self.startClockTimer()
        self.updateAllViews()
      } else {
        self.stopClockTimer()
      }
    }
  }
  var timerTime: Date? {
    get { self.session.timerTime }
    set {
      self.session.setTimerTime(newValue)
      if self.windowIsVisible {
        self.updateTimeLabel()
      }
    }
  }
  var onTimerComplete: (() -> Void)?
  private var notificationTasks: [Task<Void, Never>] = []
  var currentTimeTask: Task<Void, Never>?
  var timerTask: Task<Void, Never>?
  var paused: Bool {
    get { self.session.isPaused }
    set {
      let previousValue = self.session.isPaused
      self.session.isPaused = newValue
      if previousValue != self.session.isPaused {
        self.layoutPauseViews()
      }
    }
  }

  var displayMode: DisplayMode = .saved {
    didSet {
      guard oldValue != self.displayMode else { return }
      UserDefaults.standard.set(self.displayMode.rawValue, forKey: MVUserDefaultsKeys.displayMode)
      self.displayModeControl.selectedSegment = self.displayMode == .analog ? 0 : 1
      self.updateDisplayMode()
      self.refreshForCurrentSize()
    }
  }

  var isRunning: Bool {
    self.session.isRunning
  }

  var seconds: CGFloat {
    get { self.session.seconds }
    set {
      self.session.setSeconds(newValue)
      self.updateAfterSecondsChanged()
    }
  }

  func updateAfterSecondsChanged() {
    if self.windowIsVisible {
      self.updateLabels()
      self.updateDigitalLabels()
      self.layoutSubviews()
    }
    self.updateBadge()
  }

  func updateAfterSessionChanged(updateTimerTimeLabel: Bool = true) {
    if self.windowIsVisible {
      self.updateLabels()
      self.updateDigitalLabels()
      if updateTimerTimeLabel {
        self.updateTimeLabel()
      }
      self.layoutSubviews()
    }
    self.layoutPauseViews()
    self.updateBadge()
  }

  func updateAfterRunStateChanged() {
    if self.windowIsVisible {
      self.updateDigitalLabels()
    }
    self.layoutPauseViews()
    self.updateBadge()
  }

  func cancelTimerTask() {
    self.timerTask?.cancel()
    self.timerTask = nil
  }

  func runTimerTask() {
    self.timerTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(30))
        self?.tick()
      }
    }
  }

  var minutes: CGFloat {
    self.session.minutes
  }

  private var progress: CGFloat {
    self.invertProgressToScale(self.seconds / 60.0 / 60.0)
  }
  var didDrag: Bool = false

  // MARK: -

  convenience init() {
    self.init(frame: NSRect(x: 0, y: 0, width: 150, height: 150))

    self.center(self.progressView)
    self.addSubview(self.progressView)

    self.arrowView.onProgressChanged = { [weak self] progress in self?.handleArrowControl(progress: progress) }
    self.arrowView.onMouseUp = { [weak self] in self?.handleArrowControlMouseUp() }
    self.layoutSubviews()
    self.addSubview(self.arrowView)

    self.addSubview(self.clockFaceView)
    self.addSubview(self.pauseIconImageView)
    self.addSubview(self.timerTimeLabel)
    self.addSubview(self.minutesLabel)
    self.addSubview(self.secondsLabel)
    self.addSubview(self.digitalTimeLabel)
    self.addSubview(self.digitalStatusLabel)
    self.addSubview(self.displayModeControl)

    self.updateClockFaceView()
    self.updateAllViews()
    self.updateDisplayMode()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()

    self.notificationTasks.forEach { $0.cancel() }
    self.notificationTasks.removeAll()

    guard let window = self.window else { return }

    for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
      self.notificationTasks.append(
        Task { [weak self] in
          for await _ in NotificationCenter.default.notifications(named: name, object: window) {
            self?.updateClockFaceView()
            self?.arrowView.needsDisplay = true
            self?.progressView.needsDisplay = true
          }
        }
      )
    }
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    self.refreshForCurrentSize()
  }

  deinit {
    MainActor.assumeIsolated {
      self.notificationTasks.forEach { $0.cancel() }
      self.timerTask?.cancel()
      self.currentTimeTask?.cancel()
    }
  }
}

// MARK: - Layout & Updates

extension MVClockView {
  func updateClockFaceView(highlighted: Bool = false) {
    self.clockFaceView.update(highlighted: highlighted)
  }

  private func center(_ view: NSView) {
    var frame = view.frame
    frame.origin.x = round((self.bounds.width - frame.size.width) / 2)
    frame.origin.y = round((self.bounds.height - frame.size.height) / 2)
    view.frame = frame
  }

  override func layout() {
    super.layout()
    self.refreshForCurrentSize()
  }

  private func layoutSubviews() {
    let scale = self.layoutScale
    let center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
    self.progressView.frame = self.rect(x: 17, y: 17, width: 116, height: 116)
    self.clockFaceView.frame = self.rect(x: 16, y: 15, width: 118, height: 118)
    self.pauseIconImageView.frame = self.rect(x: 70, y: 99, width: 10, height: 12)
    self.arrowView.frame.size = NSSize(width: 25 * scale, height: 25 * scale)
    self.arrowView.updateControlCenter(center)

    let angle = -self.progress * .pi * 2 + .pi / 2

    // swiftlint:disable identifier_name
    let x = center.x + cos(angle) * self.progressView.bounds.width / 2
    let y = center.y + sin(angle) * self.progressView.bounds.height / 2
    // swiftlint:enable identifier_name

    let point = NSPoint(x: x - self.arrowView.bounds.width / 2, y: y - self.arrowView.bounds.height / 2)
    var frame = self.arrowView.frame
    frame.origin = point
    self.arrowView.frame = frame

    self.progressView.progress = self.progress
    self.arrowView.progress = self.progress
  }

  private func refreshForCurrentSize() {
    self.layoutSubviews()
    self.layoutDisplayLabels()
    self.updateLabels()
    self.updateDigitalLabels()
    self.progressView.needsDisplay = true
    self.arrowView.needsDisplay = true
    self.clockFaceView.needsDisplay = true
  }

  private var layoutScale: CGFloat {
    max(1, min(self.bounds.width, self.bounds.height) / Self.baseSize)
  }

  private func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    let scale = self.layoutScale
    let contentSize = Self.baseSize * scale
    let originX = round((self.bounds.width - contentSize) / 2 + x * scale)
    let originY = round((self.bounds.height - contentSize) / 2 + y * scale)
    return NSRect(x: originX, y: originY, width: width * scale, height: height * scale)
  }

  private func handleArrowControl(progress rawProgress: CGFloat) {
    var progressValue = rawProgress
    progressValue = self.convertProgressToScale(progressValue)
    var seconds: CGFloat = round(progressValue * 60.0 * 60.0)
    if seconds <= 300 {
      seconds -= seconds.truncatingRemainder(dividingBy: 10)
    } else {
      seconds -= seconds.truncatingRemainder(dividingBy: 60)
    }
    self.stop()

    self.session.setSeconds(seconds)
    self.session.updateTimerTime()
    self.updateAfterSessionChanged()
  }

  private func handleArrowControlMouseUp() {
    self.start()
  }

  func handleClick() {
    guard self.seconds > 0 else { return }
    if !self.isRunning {
      self.start()
    } else {
      self.session.pause()
      self.cancelTimerTask()
      self.updateAfterRunStateChanged()
    }
    self.postAccessibilityValueChanged()
  }

  private func layoutPauseViews() {
    let showAnalog = self.displayMode == .analog
    let showPauseIcon = showAnalog && self.paused
    let pauseIconAlpha = showPauseIcon ? 1.0 : 0.0
    let timerTimeAlpha = showAnalog && !showPauseIcon ? 1.0 : 0.0
    guard self.pauseIconImageView.alphaValue != pauseIconAlpha || self.timerTimeLabel.alphaValue != timerTimeAlpha else {
      return
    }

    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.2
      ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      self.pauseIconImageView.animator().alphaValue = pauseIconAlpha
      self.timerTimeLabel.animator().alphaValue = timerTimeAlpha
    }
  }

  private func updateAllViews() {
    self.updateLabels()
    self.updateDigitalLabels()
    self.updateTimeLabel()
    self.layoutSubviews()
  }

  func updateTimerTime() {
    self.session.updateTimerTime()
    if self.windowIsVisible {
      self.updateTimeLabel()
    }
  }

  private func updateLabels() {
    let scale = self.layoutScale
    self.minutesLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 35 * scale, weight: .medium)
    self.secondsLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 15 * scale, weight: .regular)
    self.minutesLabel.string = TimerLogic.minutesDisplayString(seconds: self.seconds)
    let suffixWidth: CGFloat = self.seconds < 60 ? self.minutesLabelSecondsSuffixWidth * scale : self.minutesLabelSuffixWidth * scale
    self.minutesLabel.sizeToFit()

    var frame = self.minutesLabel.frame
    frame.origin.y = self.rect(x: 0, y: 57, width: Self.baseSize, height: 30).origin.y
    frame.origin.x = round((self.bounds.width - (frame.size.width - suffixWidth)) / 2)
    self.minutesLabel.frame = frame

    self.secondsLabel.string = TimerLogic.secondsDisplayString(seconds: self.seconds)
    if self.seconds >= 60 {
      self.secondsLabel.sizeToFit()

      frame = self.secondsLabel.frame
      frame.origin.y = self.rect(x: 0, y: 38, width: Self.baseSize, height: 20).origin.y
      frame.origin.x = round((self.bounds.width - (frame.size.width - self.secondsSuffixWidth * scale)) / 2)
      self.secondsLabel.frame = frame
    }
  }

  private func layoutDisplayLabels() {
    let scale = self.layoutScale
    self.timerTimeLabel.frame = self.rect(x: 0, y: 94, width: Self.baseSize, height: 20)
    self.timerTimeLabel.font = NSFont.systemFont(ofSize: 15 * scale, weight: .medium)

    self.digitalTimeLabel.frame = self.rect(x: 4, y: 55, width: 142, height: 44)
    self.digitalTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 34 * scale, weight: .semibold)
    self.digitalStatusLabel.frame = self.rect(x: 0, y: 39, width: Self.baseSize, height: 18)
    self.digitalStatusLabel.font = NSFont.systemFont(ofSize: 11 * scale, weight: .medium)

    let controlWidth = min(106 * scale, self.bounds.width - 28)
    self.displayModeControl.frame = NSRect(
      x: round((self.bounds.width - controlWidth) / 2),
      y: round(10 * scale),
      width: controlWidth,
      height: 22
    )
  }

  private func updateDigitalLabels() {
    self.digitalTimeLabel.string = self.digitalTimeString
    if self.paused {
      self.digitalStatusLabel.string = "Paused"
    } else if self.isRunning {
      self.digitalStatusLabel.string = "Remaining"
    } else if self.seconds > 0 {
      self.digitalStatusLabel.string = "Ready"
    } else {
      self.digitalStatusLabel.string = "Set timer"
    }
  }

  private var digitalTimeString: String {
    let totalSeconds = Int(self.seconds)
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds / 60) % 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
  }

  private func updateDisplayMode() {
    let showDigital = self.displayMode == .digital
    let analogTextAlpha = showDigital ? 0.0 : 1.0
    let digitalAlpha = showDigital ? 1.0 : 0.0
    self.progressView.isHidden = false
    self.arrowView.isHidden = false
    self.clockFaceView.alphaValue = analogTextAlpha
    self.clockFaceView.isHidden = showDigital
    for view in [self.minutesLabel, self.secondsLabel, self.timerTimeLabel] {
      view.alphaValue = analogTextAlpha
      view.isHidden = showDigital
    }
    self.pauseIconImageView.isHidden = showDigital
    self.digitalTimeLabel.alphaValue = digitalAlpha
    self.digitalStatusLabel.alphaValue = digitalAlpha
    self.digitalTimeLabel.isHidden = !showDigital
    self.digitalStatusLabel.isHidden = !showDigital
    self.layoutPauseViews()
  }

  @objc private func pickDisplayMode(_ sender: NSSegmentedControl) {
    self.displayMode = sender.selectedSegment == 0 ? .analog : .digital
  }

  private func updateBadge() {
    if self.inDock {
      if self.isRunning || self.paused {
        let badgeSeconds = Int(self.seconds.truncatingRemainder(dividingBy: 60))
        let badgeMinutes = Int(self.minutes)
        NSApplication.shared.dockTile.badgeLabel = TimerLogic.badgeString(minutes: badgeMinutes, seconds: badgeSeconds)
      } else {
        self.removeBadge()
      }
    }
  }

  func removeBadge() {
    NSApplication.shared.dockTile.badgeLabel = ""
  }

  private func updateTimeLabel() {
    let timeString = self.timerTimeLabelFormatter.string(from: self.timerTime ?? Date())
    self.timerTimeLabel.string = timeString

    if let ampmRange = (
      timeString.range(of: " AM", options: [.caseInsensitive]) ??
      timeString.range(of: " PM", options: [.caseInsensitive])
    ) {
      self.timerTimeLabel.setFont(
        NSFont.systemFont(ofSize: 12, weight: .medium),
        range: NSRange(ampmRange, in: timeString)
      )
    }
  }

  override func hitTest(_ aPoint: NSPoint) -> NSView? {
    let view = super.hitTest(aPoint)
    if view == self.displayModeControl || view?.isDescendant(of: self.displayModeControl) == true {
      return view
    }
    if view == self.arrowView {
      return view
    }
    if view != nil {
      return self
    }
    return nil
  }

  private func convertProgressToScale(_ progress: CGFloat) -> CGFloat {
    TimerLogic.convertProgressToScale(progress, minutes: self.minutes)
  }

  private func invertProgressToScale(_ progress: CGFloat) -> CGFloat {
    TimerLogic.invertProgressToScale(progress, minutes: self.minutes)
  }
}
