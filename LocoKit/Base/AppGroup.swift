//
//  AppGroup.swift
//  Arc
//
//  Created by Matt Greenfield on 28/5/20.
//  Copyright © 2020 Big Paua. All rights reserved.
//

public class AppGroup {

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // MARK: - Properties

    private var apps: [AppName: AppState] = [:]

    public let thisApp: AppName
    public let suiteName: String

    public private(set) lazy var groupDefaults: UserDefaults? = { UserDefaults(suiteName: suiteName) }()
    public var sortedApps: [AppState] { apps.values.sorted { $0.updated > $1.updated } }
    public var currentRecorder: AppState? { sortedApps.first { $0.isAliveAndRecording } }
    public var haveMultipleRecorders: Bool { apps.values.filter({ $0.isAliveAndRecording }).count > 1 }
    public var haveAppsInStandby: Bool { apps.values.filter({ $0.recordingState == .standby }).count > 0 }

    private lazy var talker: AppGroupTalk = { AppGroupTalk(messagePrefix: suiteName, appName: thisApp) }()

    // MARK: - Public methods

    public init(appName: AppName, suiteName: String, readOnly: Bool = false) {
        self.thisApp = appName
        self.suiteName = suiteName

        if readOnly { load(); return }

        save()

        NotificationCenter.default.addObserver(forName: .receivedAppGroupMessage, object: nil, queue: nil) { note in
            guard let messageRaw = note.userInfo?["message"] as? String else { return }
            guard let message = AppGroupTalk.Message(rawValue: messageRaw.deletingPrefix(suiteName + ".")) else { return }
            if message == .modifiedObjects {
                // TODO: this ain't gonna happen. userInfo aint there
                print("RECEIVED 2 cfUserInfo: \(note.userInfo?["cfUserInfo"])")
            }
            if let cfUserInfo = note.userInfo?["cfUserInfo"] as? [NSString: Any] {
                self.received(message, userInfo: cfUserInfo)
            } else {
                self.received(message)
            }
        }
    }

    public var shouldBeTheRecorder: Bool {
        guard let currentRecorder = currentRecorder else { return true }
        if haveMultipleRecorders { return false } // this shouldn't happen in the first place
        if currentRecorder.appName == thisApp { return true }
        return false
    }

    public var isTheCurrentRecorder: Bool {
        return currentRecorder?.appName == thisApp
    }

    public func becameCurrentRecorder() {
        save()
        talker.send(message: .tookOverRecording)
    }

    // MARK: - 

    public func load() {
        var states: [AppName: AppState] = [:]
        for appName in AppName.allCases {
            if let data = groupDefaults?.value(forKey: appName.rawValue) as? Data {
                if let state = try? AppGroup.decoder.decode(AppState.self, from: data) {
                    states[appName] = state
                }
            }
        }
        apps = states
    }

    public func save() {
        load()
        apps[thisApp] = AppState(appName: thisApp, recordingState: LocomotionManager.highlander.recordingState, updateInfo: [:], updated: Date())
        guard let data = try? AppGroup.encoder.encode(apps[thisApp]) else { return }
        groupDefaults?.set(data, forKey: thisApp.rawValue)
        talker.send(message: .updatedAppState)
    }

    private func received(_ message: AppGroupTalk.Message, userInfo: [NSString: Any]? = nil) {
        switch message {
        case .updatedAppState:
            if let updated = apps[thisApp]?.updated, updated.age > .oneMinute {
                load()
            }
        case .modifiedObjects:
            if let userInfo = userInfo {
            }
        case .tookOverRecording:
            fatalError() // TODO: uh, no
        }
    }

    // MARK: - Interfaces

    public enum AppName: String, CaseIterable, Codable { case arcV3, arcMini, arcV4 }

    public struct AppState: Codable {
        public var appName: AppName
        public var recordingState: RecordingState
        public var updateInfo: [String: String]
        public var updated: Date

        public var isAlive: Bool { return updated.age < LocomotionManager.highlander.standbyCycleDuration }
        public var isAliveAndRecording: Bool { return isAlive && recordingState != .off && recordingState != .standby }
    }

}

extension NSNotification.Name {
    static let receivedAppGroupMessage = Notification.Name("receivedAppGroupMessage")
}

// https://stackoverflow.com/a/58188965/790036
final public class AppGroupTalk: NSObject {

    public enum Message: String, CaseIterable {
        case updatedAppState
        case modifiedObjects
        case tookOverRecording
        func withPrefix(_ prefix: String) -> String { return "\(prefix).\(rawValue)" }
    }

    // MARK: -

    private let center = CFNotificationCenterGetDarwinNotifyCenter()
    private let messagePrefix: String

    public init(messagePrefix: String) {
        self.messagePrefix = messagePrefix
        super.init()
        startListeners()
    }

    deinit {
        stopListeners()
    }

    public func send(message: Message) {
        let fullMessage = "\(messagePrefix).\(message.rawValue)"
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(rawValue: fullMessage as CFString), nil, nil, true)
    }

    // MARK: - Private

    private func startListeners() {
        for message in Message.allCases {
            CFNotificationCenterAddObserver(center, Unmanaged.passRetained(self).toOpaque(), { center, observer, name, object, userInfo in
                NotificationCenter.default.post(name: .receivedAppGroupMessage, object: nil, userInfo: ["message": name?.rawValue as Any])
            }, "\(messagePrefix).\(message.rawValue)" as CFString, nil, .deliverImmediately)
        }
    }

    private func stopListeners() {
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passRetained(self).toOpaque())
    }

}
