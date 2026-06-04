import AppKit

// MARK: - Event Handling

extension MVClockView {
  override func mouseDown(with event: NSEvent) {
    self.didDrag = false
    self.updateClockFaceView(highlighted: true)
    self.nextResponder?.mouseDown(with: event)
  }

  override func mouseDragged(with _: NSEvent) {
    if !self.didDrag {
      self.didDrag = true
      self.updateClockFaceView()
    }
  }

  override func scrollWheel(with event: NSEvent) {
    guard !self.isRunning, !self.paused else { return }

    let delta: CGFloat
    if event.hasPreciseScrollingDeltas {
      delta = event.scrollingDeltaY * 3
    } else {
      delta = event.scrollingDeltaY * 30
    }

    guard delta != 0 else { return }

    var newSeconds = self.seconds + delta
    newSeconds = max(0, newSeconds)

    if newSeconds <= 300 {
      newSeconds -= newSeconds.truncatingRemainder(dividingBy: 10)
    } else {
      newSeconds -= newSeconds.truncatingRemainder(dividingBy: 60)
    }

    self.session.setSeconds(newSeconds)
    self.session.updateTimerTime()
    self.updateAfterSessionChanged()
  }

  override func mouseUp(with event: NSEvent) {
    let point = self.convert(event.locationInWindow, from: nil)
    if self.hitTest(point) == self, !self.didDrag {
      self.handleClick()
    }
    self.updateClockFaceView()
  }

  override func keyUp(with event: NSEvent) {
    let modifiers = event.modifierFlags
    let chars = event.charactersIgnoringModifiers
    let minuteAmount = modifiers.contains(.shift) ? 10 : 1

    // Use the physical key ("=" is the +/= key; shift state isn't reliable on keyUp)
    let isAdd = chars == "\u{F700}" || chars == "=" // up arrow or +/= key
    let isSubtract = chars == "\u{F701}" || chars == "-" // down arrow or -/_ key

    if isAdd {
      self.adjustMinutes(by: minuteAmount)
    } else if isSubtract {
      self.adjustMinutes(by: -minuteAmount)
    } else {
      switch chars {
      case ".":
        self.session.inputSeconds.toggle()

      case "\u{1B}": // escape
        self.resetTimer()

      case "\u{7F}", "\u{F728}": // delete, forward delete
        self.handleBackspace()

      case "\r", " ", "\u{03}": // return, space, keypad enter
        self.handleClick()

      case "r":
        if !self.isRunning, !self.paused, let seconds = self.lastTimerSeconds {
          self.startTimer(seconds: seconds)
        }

      default:
        self.handleDigitInput(event)
      }
    }
  }

  private func adjustMinutes(by minutes: Int) {
    self.session.adjustMinutes(by: minutes)
    self.updateAfterSessionChanged()
  }

  private func resetTimer() {
    self.stop()
    self.session.reset()
    self.updateAfterSessionChanged()
  }

  private func handleBackspace() {
    self.stop()
    self.session.processBackspace()
    self.updateAfterSessionChanged()
  }

  private func handleDigitInput(_ event: NSEvent) {
    guard let characters = event.characters, let number = Int(characters) else { return }

    if self.session.processDigitInput(number) {
      self.stop()
      self.updateAfterSessionChanged()
    }
  }
}

// MARK: - Timer

extension MVClockView {
  func start() {
    self.cancelTimerTask()
    guard self.session.start() else { return }

    self.updateAfterSessionChanged()
    self.runTimerTask()
  }

  func stop() {
    self.cancelTimerTask()
    self.session.stop()

    if self.inDock, !self.paused {
      self.removeBadge()
    }
    self.updateAfterRunStateChanged()
  }

  func startTimer(seconds: CGFloat) {
    self.cancelTimerTask()
    guard self.session.start(seconds: seconds) else { return }

    self.updateAfterSessionChanged()
    self.runTimerTask()
  }

  func tick() {
    let completed = self.session.updateRemaining()
    self.updateAfterSessionChanged(updateTimerTimeLabel: false)

    if completed {
      self.cancelTimerTask()
      self.postAccessibilityValueChanged()
      self.onTimerComplete?()
    }
  }

  func startClockTimer() {
    guard self.currentTimeTask == nil else { return }

    if !self.isRunning {
      self.timerTime = Date()
    }

    self.currentTimeTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(500))
        self?.maintainCurrentTime()
      }
    }
  }

  func stopClockTimer() {
    self.currentTimeTask?.cancel()
    self.currentTimeTask = nil
  }

  private func maintainCurrentTime() {
    guard !self.isRunning else { return }

    self.session.updateCurrentTime()
    self.updateAfterSessionChanged()
  }
}

// MARK: - Accessibility

extension MVClockView {
  override func isAccessibilityElement() -> Bool { true }
  override func accessibilityRole() -> NSAccessibility.Role? { .group }
  override func accessibilityLabel() -> String? { "Timer" }
  override func accessibilityValue() -> Any? { self.accessibilityTimerDescription }

  private var accessibilityTimerDescription: String {
    let mins = Int(self.minutes)
    let secs = Int(self.seconds.truncatingRemainder(dividingBy: 60))

    if self.seconds <= 0, !self.isRunning {
      return "Ready"
    }

    let timeDescription = TimerLogic.accessibilityTimeDescription(minutes: mins, seconds: secs)

    if self.paused {
      return "Paused at \(timeDescription)"
    }
    if self.isRunning {
      return "\(timeDescription) remaining"
    }
    return timeDescription
  }

  func postAccessibilityValueChanged() {
    NSAccessibility.post(element: self, notification: .valueChanged)
  }
}
