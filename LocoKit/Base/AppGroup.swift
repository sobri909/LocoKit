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
            guard let message = AppGroup.Message(rawValue: messageRaw.deletingPrefix(suiteName + ".")) else { return }
            self.received(message)
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
        send(message: .tookOverRecording)
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
        apps[thisApp] = currentAppState
        guard let data = try? AppGroup.encoder.encode(apps[thisApp]) else { return }
        groupDefaults?.set(data, forKey: thisApp.rawValue)
    }

    var currentAppState: AppState {
        return AppState(appName: thisApp, recordingState: LocomotionManager.highlander.recordingState, updated: Date())
    }

    public func notifyObjectChanges(objectIds: Set<UUID>) {
        let messageInfo = MessageInfo(date: Date(), appState: currentAppState, modifiedObjectIds: objectIds)
        send(message: .modifiedObjects, messageInfo: messageInfo)
    }

    // MARK: - Private

    private func send(message: Message, messageInfo: MessageInfo? = nil) {
        let lastMessage = messageInfo ?? MessageInfo(date: Date(), appState: currentAppState, modifiedObjectIds: nil)
        if let data = try? AppGroup.encoder.encode(lastMessage) {
            groupDefaults?.set(data, forKey: "lastMessage")
        } else {
            print("FAILED TO ENCODE LAST MESSAGE: \(lastMessage)")
        }
        talker.send(message)
    }

    private func received(_ message: AppGroup.Message) {
        print("RECEIVED: \(message)")

        guard let data = groupDefaults?.value(forKey: "lastMessage") as? Data else { print("NO MESSAGE INFO DATA"); return }
        guard let messageInfo = try? AppGroup.decoder.decode(MessageInfo.self, from: data) else { print("NO MESSAGE INFO OBJECT"); return }

        switch message {
        case .modifiedObjects:
            objectsWereModified(by: messageInfo.appState.appName, messageInfo: messageInfo)
        case .tookOverRecording:
            recordingWasTakenOver(by: messageInfo.appState.appName, messageInfo: messageInfo)
        }
    }

    private func recordingWasTakenOver(by: AppName, messageInfo: MessageInfo) {
        if by == thisApp { print("IT WAS ME"); return }
        if LocomotionManager.highlander.recordingState.isCurrentRecorder {
            LocomotionManager.highlander.startStandby()
            NotificationCenter.default.post(Notification(name: .concededRecording, object: self, userInfo: nil))
        }
    }

    private func objectsWereModified(by: AppName, messageInfo: MessageInfo) {
        if by == thisApp { print("IT WAS ME"); return }
        print("[\(by)] modifiedObjectIds: \(messageInfo.modifiedObjectIds)")
    }

    // MARK: - Interfaces

    public enum AppName: String, CaseIterable, Codable { case arcV3, arcMini, arcV4 }

    public struct AppState: Codable {
        public var appName: AppName
        public var recordingState: RecordingState
        public var updated: Date

        public var isAlive: Bool { return updated.age < LocomotionManager.highlander.standbyCycleDuration }
        public var isAliveAndRecording: Bool { return isAlive && recordingState != .off && recordingState != .standby }
    }

    public enum Message: String, CaseIterable {
        case modifiedObjects
        case tookOverRecording
        func withPrefix(_ prefix: String) -> String { return "\(prefix).\(rawValue)" }
    }

    public struct MessageInfo: Codable {
        public var date: Date
        public var appState: AppState
        public var modifiedObjectIds: Set<UUID>? = nil
    }

}

extension NSNotification.Name {
    static let receivedAppGroupMessage = Notification.Name("receivedAppGroupMessage")
}

// https://stackoverflow.com/a/58188965/790036
final public class AppGroupTalk: NSObject {

    private let center = CFNotificationCenterGetDarwinNotifyCenter()
    private let messagePrefix: String
    private let appName: AppGroup.AppName

    public init(messagePrefix: String, appName: AppGroup.AppName) {
        self.messagePrefix = messagePrefix
        self.appName = appName
        super.init()
        startListeners()
    }

    deinit {
        stopListeners()
    }

    // MARK: -

    public func send(_ message: AppGroup.Message) {
        let noteName = CFNotificationName(rawValue: message.withPrefix(messagePrefix) as CFString)
        CFNotificationCenterPostNotification(center, noteName, nil, nil, true)
    }

    // MARK: - Private

    private func startListeners() {
        for message in AppGroup.Message.allCases {
            CFNotificationCenterAddObserver(center, Unmanaged.passRetained(self).toOpaque(), { center, observer, name, object, userInfo in
                NotificationCenter.default.post(name: .receivedAppGroupMessage, object: nil, userInfo: ["message": name?.rawValue as Any])
            }, "\(messagePrefix).\(message.rawValue)" as CFString, nil, .deliverImmediately)
        }
    }

    private func stopListeners() {
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passRetained(self).toOpaque())
    }

}
