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
    public var currentRecorder: AppState? { sortedApps.first { $0.recordingState != .off && $0.recordingState != .standby } }
    public var haveMultipleRecorders: Bool { apps.values.filter({ $0.recordingState != .off && $0.recordingState != .standby }).count > 1 }

    private lazy var talker: AppGroupTalk = { AppGroupTalk(messagePrefix: self.suiteName) }()

    // MARK: - Public methods

    public init(appName: AppName, suiteName: String) {
        self.thisApp = appName
        self.suiteName = suiteName
        save()

        NotificationCenter.default.addObserver(forName: .receivedAppGroupMessage, object: nil, queue: nil) { note in
            if let messageRaw = note.userInfo?["message"] as? String {
                if let message = AppGroupTalk.Message(rawValue: messageRaw.deletingPrefix(suiteName + ".")) {
                    print("RECEIVED AppGroupTalk.Message: \(message)")
                    self.received(message)
                }
            }
        }
    }

    public var shouldBeTheRecorder: Bool {
        guard let currentRecorder = currentRecorder else { return true }
        if haveMultipleRecorders { return false } // this shouldn't happen in the first place
        if currentRecorder.appName == thisApp { return true }
        if currentRecorder.updated.age > .oneMinute * 10 {
            talker.send(message: .pleaseUpdateAppState)
            return true // TODO: shouldn't just return true here?
        }
        return false
    }

    public func load() {
        print("AppGroup.load()")
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
        print("AppGroup.save()")
        load()
        apps[thisApp] = AppState(appName: thisApp, recordingState: LocomotionManager.highlander.recordingState, updated: Date())
        guard let data = try? AppGroup.encoder.encode(apps[thisApp]) else { return }
        groupDefaults?.set(data, forKey: thisApp.rawValue)
        print("SAVED: \(apps[thisApp]!)")
        talker.send(message: .updatedAppState)
    }

    private func received(_ message: AppGroupTalk.Message) {
        switch message {
        case .updatedAppState:
            if let updated = apps[thisApp]?.updated, updated.age > .oneMinute {
                load()
            }
        case .pleaseUpdateAppState:
            if let updated = apps[thisApp]?.updated, updated.age > .oneMinute {
                save()
            }
        }
    }

    // MARK: - Interfaces

    public enum AppName: String, CaseIterable, Codable { case arcV3, arcMini, arcV4 }

    public struct AppState: Codable {
        public var appName: AppName
        public var recordingState: RecordingState
        public var updated: Date
    }

}

extension NSNotification.Name {
    static let receivedAppGroupMessage = Notification.Name("receivedAppGroupMessage")
}

// https://stackoverflow.com/a/58188965/790036
final public class AppGroupTalk: NSObject {

    public enum Message: String, CaseIterable {
        case updatedAppState
        case pleaseUpdateAppState
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
