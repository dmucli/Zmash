/// Everything a rider can ask for, whatever the input (Ride buttons, touch, keyboard).
public enum RideCommand: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case shiftUp        // harder
    case shiftDown      // easier
    case gradeUp
    case gradeDown
    case pauseToggle
    case endSession
    case toggleTheme
    case nextFace
    case previousFace
    /// The course profile under the face: closer in, or back out towards the whole course.
    case zoomIn
    case zoomOut
    /// Slide the ride's control panel up or down (D108).
    case toggleControls
    /// In a workout: on to the next interval now, or back to the start of this one (D151).
    case skipInterval
    case repeatInterval

    /// How a command is triggered from a physical control.
    public enum Trigger: Sendable {
        case press          // once, on press
        case repeating      // on press, then repeats while held
        case hold           // once, after being held `endHoldDuration`
    }

    public var trigger: Trigger {
        switch self {
        case .gradeUp, .gradeDown: .repeating
        case .endSession: .hold
        case .shiftUp, .shiftDown, .pauseToggle, .toggleTheme, .nextFace, .previousFace, .zoomIn, .zoomOut, .toggleControls,
             .skipInterval, .repeatInterval: .press
        }
    }
}

/// Every physical control on the Zwift Ride, buttons and analog paddles alike.
public enum RideControl: String, Codable, CodingKeyRepresentable, CaseIterable, Hashable, Sendable {
    case up, down, left, right
    case shiftUpLeft, shiftDownLeft, powerUpLeft, onOffLeft, paddleLeft
    case a, b, y, z
    case shiftUpRight, shiftDownRight, powerUpRight, onOffRight, paddleRight

    public var mask: ZwiftRide.Buttons? {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .shiftUpLeft: .shiftUpLeft
        case .shiftDownLeft: .shiftDownLeft
        case .powerUpLeft: .powerUpLeft
        case .onOffLeft: .onOffLeft
        case .a: .a
        case .b: .b
        case .y: .y
        case .z: .z
        case .shiftUpRight: .shiftUpRight
        case .shiftDownRight: .shiftDownRight
        case .powerUpRight: .powerUpRight
        case .onOffRight: .onOffRight
        case .paddleLeft, .paddleRight: nil
        }
    }

    public var isLeft: Bool {
        switch self {
        case .up, .down, .left, .right, .shiftUpLeft, .shiftDownLeft, .powerUpLeft, .onOffLeft, .paddleLeft: true
        default: false
        }
    }

    /// Holding on/off powers the controller down: these only ever react to a short press.
    public var isOnOff: Bool { self == .onOffLeft || self == .onOffRight }

    /// Actions that make sense on this control (on/off can't repeat or hold).
    public var allowedCommands: [RideCommand] {
        isOnOff ? RideCommand.allCases.filter { $0.trigger == .press } : RideCommand.allCases
    }

    public var name: String {
        switch self {
        case .up: "D-pad up"
        case .down: "D-pad down"
        case .left: "D-pad left"
        case .right: "D-pad right"
        case .shiftUpLeft: "Upper side button"
        case .shiftDownLeft: "Middle side button"
        case .powerUpLeft: "Lower side button"
        case .onOffLeft: "On/off"
        case .paddleLeft: "Paddle"
        case .a: "A"
        case .b: "B"
        case .y: "Y"
        case .z: "Z"
        case .shiftUpRight: "Upper side button"
        case .shiftDownRight: "Middle side button"
        case .powerUpRight: "Lower side button"
        case .onOffRight: "On/off"
        case .paddleRight: "Paddle"
        }
    }
}

/// What each control does. Controls not in the map do nothing.
public struct ButtonMap: Codable, Equatable, Sendable {
    public var commands: [RideControl: RideCommand]

    public init(_ commands: [RideControl: RideCommand]) { self.commands = commands }

    public subscript(control: RideControl) -> RideCommand? {
        get { commands[control] }
        set {
            if let newValue, control.allowedCommands.contains(newValue) { commands[control] = newValue }
            else { commands[control] = nil }
        }
    }

    /// Brief §7: right = harder, left = easier (Zwift convention), D-pad up/down = grade, left/right = faces,
    /// A = the control panel (D108), Z/on-off = pause, hold B or left lower = end, Y = theme.
    public static let standard = ButtonMap([
        .up: .gradeUp, .down: .gradeDown, .left: .previousFace, .right: .nextFace,
        .shiftUpLeft: .shiftDown, .shiftDownLeft: .shiftDown, .powerUpLeft: .endSession, .onOffLeft: .pauseToggle,
        .paddleLeft: .shiftDown,
        .a: .toggleControls, .b: .endSession, .y: .toggleTheme, .z: .pauseToggle,
        .shiftUpRight: .shiftUp, .shiftDownRight: .shiftDown, .onOffRight: .pauseToggle,
        .paddleRight: .shiftUp,
    ])
}

/// Maps Zwift Ride keypad frames to `RideCommand`s through a `ButtonMap`.
///
/// - `press` commands fire on the press edge; `repeating` ones then repeat while held;
///   `hold` ones fire once after `endHoldDuration`.
/// - On/off buttons fire on *release* after a short press only — a long hold powers the controller off.
/// - Paddles are analog: pressed at |value| ≥ 25, released below 15.
///
/// Pure and clock-injected: call `update` for every keypad frame and `tick` periodically while `needsTicks`.
public struct RideInputMapper: Sendable {
    public static let repeatDelay = 0.4
    public static let repeatInterval = 0.25
    public static let shortPressLimit = 0.6
    /// Long enough not to end a ride by accident; the ride screen fills a circle meanwhile (D108).
    public static let endHoldDuration = 3.0
    public static let paddlePress = 25
    public static let paddleRelease = 15

    public typealias B = ZwiftRide.Buttons

    public var map: ButtonMap

    private var held: Set<RideControl> = []
    private var paddlesHeld: Set<RideControl> = []
    private var pressedAt: [RideControl: Double] = [:]
    private var lastRepeat: [RideControl: Double] = [:]
    private var holdFired: Set<RideControl> = []

    public init(map: ButtonMap = .standard) { self.map = map }

    /// When a hold-to-end began (in the mapper's clock), while one is under way and hasn't fired yet.
    public var holdStartedAt: Double? {
        held.filter { !$0.isOnOff && map[$0]?.trigger == .hold && !holdFired.contains($0) }
            .compactMap { pressedAt[$0] }.min()
    }

    public var needsTicks: Bool {
        held.contains { control in
            guard !control.isOnOff, let command = map[control] else { return false }
            switch command.trigger {
            case .repeating: return true
            case .hold: return !holdFired.contains(control)
            case .press: return false
            }
        }
    }

    public mutating func update(pressed: B, paddles: [ZwiftRide.Paddle] = [], at now: Double) -> [RideCommand] {
        for paddle in paddles where paddle.location == 0 || paddle.location == 1 {
            let control: RideControl = paddle.location == 0 ? .paddleLeft : .paddleRight
            let magnitude = abs(paddle.value)
            if paddlesHeld.contains(control) {
                if magnitude < Self.paddleRelease { paddlesHeld.remove(control) }
            } else if magnitude >= Self.paddlePress {
                paddlesHeld.insert(control)
            }
        }

        var current = paddlesHeld
        for control in RideControl.allCases {
            if let mask = control.mask, pressed.contains(mask) { current.insert(control) }
        }

        var commands: [RideCommand] = []
        for control in RideControl.allCases where current.contains(control) && !held.contains(control) {
            pressedAt[control] = now
            lastRepeat[control] = nil
            holdFired.remove(control)
            guard !control.isOnOff, let command = map[control], command.trigger != .hold else { continue }
            commands.append(command)
        }
        for control in RideControl.allCases where held.contains(control) && !current.contains(control) {
            if control.isOnOff, let command = map[control], let t = pressedAt[control], now - t < Self.shortPressLimit {
                commands.append(command)
            }
            pressedAt[control] = nil
            lastRepeat[control] = nil
            holdFired.remove(control)
        }
        held = current
        return commands + tick(at: now)
    }

    public mutating func tick(at now: Double) -> [RideCommand] {
        var commands: [RideCommand] = []
        for control in RideControl.allCases where held.contains(control) && !control.isOnOff {
            guard let command = map[control], let start = pressedAt[control] else { continue }
            switch command.trigger {
            case .repeating:
                guard now - start >= Self.repeatDelay else { continue }
                let last = lastRepeat[control] ?? (start + Self.repeatDelay - Self.repeatInterval)
                if now - last >= Self.repeatInterval {
                    commands.append(command)
                    lastRepeat[control] = now
                }
            case .hold:
                if !holdFired.contains(control), now - start >= Self.endHoldDuration {
                    commands.append(command)
                    holdFired.insert(control)
                }
            case .press:
                break
            }
        }
        return commands
    }
}
