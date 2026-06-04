import Foundation

struct TimerSession: Equatable {
  enum RunState: Equatable {
    case idle
    case running
    case paused
  }

  private(set) var seconds: CGFloat = 0
  private(set) var timerTime: Date?
  var inputSeconds = false
  private(set) var lastTimerSeconds: CGFloat?
  private(set) var runState: RunState = .idle

  var minutes: CGFloat {
    floor(self.seconds / 60)
  }

  var isRunning: Bool {
    self.runState == .running
  }

  var isPaused: Bool {
    get { self.runState == .paused }
    set {
      if newValue {
        self.runState = .paused
      } else if self.runState == .paused {
        self.runState = .idle
      }
    }
  }

  mutating func setSeconds(_ seconds: CGFloat) {
    self.seconds = max(0, seconds)
  }

  mutating func setTimerTime(_ timerTime: Date?) {
    self.timerTime = timerTime
  }

  mutating func updateTimerTime(now: Date = Date()) {
    self.timerTime = now.addingTimeInterval(Double(self.seconds))
  }

  mutating func adjustMinutes(by minutes: Int) {
    self.setSeconds(self.seconds + CGFloat(minutes * 60))
    self.updateTimerTime()
  }

  mutating func reset() {
    self.runState = .idle
    self.seconds = 0
    self.inputSeconds = false
    self.updateTimerTime()
  }

  mutating func processBackspace() {
    let currentSeconds = self.seconds.truncatingRemainder(dividingBy: 60)
    let currentMinutes = floor(self.seconds / 60)
    self.runState = .idle
    self.seconds = TimerLogic.processBackspace(
      currentSeconds: currentSeconds,
      currentMinutes: currentMinutes,
      inputSeconds: self.inputSeconds
    )
    self.updateTimerTime()
  }

  mutating func processDigitInput(_ digit: Int) -> Bool {
    let currentSeconds = self.seconds.truncatingRemainder(dividingBy: 60)
    let currentMinutes = floor(self.seconds / 60)
    let result = TimerLogic.processDigitInput(
      digit: digit,
      currentSeconds: currentSeconds,
      currentMinutes: currentMinutes,
      totalSeconds: self.seconds,
      inputSeconds: self.inputSeconds
    )

    guard result.accepted else { return false }

    self.runState = .idle
    self.seconds = result.seconds
    self.updateTimerTime()
    return true
  }

  mutating func start(now: Date = Date()) -> Bool {
    guard self.seconds > 0 else { return false }

    self.lastTimerSeconds = self.seconds
    self.runState = .running
    self.timerTime = now.addingTimeInterval(Double(self.seconds))
    return true
  }

  mutating func start(seconds: CGFloat, now: Date = Date()) -> Bool {
    self.runState = .idle
    self.setSeconds(seconds)
    return self.start(now: now)
  }

  mutating func pause() {
    guard self.isRunning else { return }

    self.runState = .paused
  }

  mutating func stop() {
    if !self.isPaused {
      self.runState = .idle
    }
  }

  mutating func updateRemaining(now: Date = Date()) -> Bool {
    guard let timerTime else { return false }

    self.seconds = max(0, round(CGFloat(timerTime.timeIntervalSince(now))))

    if self.seconds <= 0 {
      self.runState = .idle
      return true
    }
    return false
  }

  mutating func updateCurrentTime(now: Date = Date(), calendar: Calendar = .current) {
    guard !self.isRunning else { return }

    if calendar.component(.second, from: now) == 0 {
      self.timerTime = now
    }
  }
}
