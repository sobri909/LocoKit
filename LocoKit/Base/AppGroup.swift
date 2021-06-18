//
//  AppGroup.swift
//  Arc
//
//  Created by Matt Greenfield on 28/5/20.
//  Copyright © 2020 Big Paua. All rights reserved.
//

import Foundation

public class AppGroup {

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // MARK: - Properties

    public let thisApp: AppName
    public let suiteName: String
    public var timelineRecorder: TimelineRecorder?

    public private(set) var apps: [AppName: AppState] = [:]
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
        // should always be current recorder in foreground
        if LocomotionManager.highlander.applicationState == .active { return true }

        // there's no current recorder? then we should take on the job
        guard let currentRecorder = currentRecorder else { return true }

        // there's multiple recorders, and we're not in foreground? it's time to concede
        if haveMultipleRecorders { return false }

        // if this app is the current recorder, it should continue to be so
        return currentRecorder.appName == thisApp
    }

    public var isAnActiveRecorder: Bool {
        return currentAppState.recordingState.isCurrentRecorder
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
        send(message: .updatedState)
    }

    var currentAppState: AppState {
        var deepSleepUntil: Date?
        if let until = LocoKitService.requestedWakeupCall, until.age < 0 {
            deepSleepUntil = until
        }
        if let currentItem = timelineRecorder?.currentItem {
            if currentRecorder?.appName == thisApp {
                return AppState(appName: thisApp, recordingState: LocomotionManager.highlander.recordingState,
                                currentItemId: currentItem.itemId, currentItemTitle: currentItem.title, deepSleepingUntil: deepSleepUntil)
            } else {
                return AppState(appName: thisApp, recordingState: LocomotionManager.highlander.recordingState,
                                currentItemId: currentItem.itemId, deepSleepingUntil: deepSleepUntil)
            }
        }
        return AppState(appName: thisApp, recordingState: LocomotionManager.highlander.recordingState, deepSleepingUntil: deepSleepUntil)
    }

    public func notifyObjectChanges(objectIds: Set<UUID>) {
        let messageInfo = MessageInfo(date: Date(), message: .modifiedObjects, appName: thisApp, modifiedObjectIds: objectIds)
        send(message: .modifiedObjects, messageInfo: messageInfo)
    }
    
    // MARK: - Shared settings
    
    public func get(setting key: String) -> Any? {
        return groupDefaults?.value(forKey: "sharedSetting." + key) as Any?
    }
    
    public func set(setting key: String, value: Any?) {
        groupDefaults?.set(value, forKey: "sharedSetting." + key)
    }

    // MARK: - Private

    private func send(message: Message, messageInfo: MessageInfo? = nil) {
        let lastMessage = messageInfo ?? MessageInfo(date: Date(), message: message, appName: thisApp, modifiedObjectIds: nil)
        if let data = try? AppGroup.encoder.encode(lastMessage) {
            groupDefaults?.set(data, forKey: "lastMessage")
        }
        talker.send(message)
    }

    private func received(_ message: AppGroup.Message) {
        guard let data = groupDefaults?.value(forKey: "lastMessage") as? Data else { return }
        guard let messageInfo = try? AppGroup.decoder.decode(MessageInfo.self, from: data) else { return }
        guard messageInfo.appName != thisApp else { return }
        guard messageInfo.message == message else { print("LASTMESSAGE.MESSAGE MISMATCH (expected: \(message.rawValue), got: \(messageInfo.message.rawValue))"); return }

        load()

        switch message {
        case .updatedState:
            appStateUpdated(by: messageInfo.appName)
        case .modifiedObjects:
            objectsWereModified(by: messageInfo.appName, messageInfo: messageInfo)
        case .tookOverRecording:
            recordingWasTakenOver(by: messageInfo.appName, messageInfo: messageInfo)
        }
    }
    
    private func appStateUpdated(by: AppName) {
        print("RECEIVED: .updatedState, from: \(by)")
        guard let currentRecorder = currentRecorder else { print("wtf. no currentRecorder"); return }
        guard let currentItemId = currentRecorder.currentItemId else { print("wtf. no currentItemId"); return }
        if !isAnActiveRecorder, currentAppState.currentItemId != currentItemId {
            print("need to update local currentItem (mine: \(currentAppState.currentItemId?.uuidString ?? "nil"), theirs: \(currentItemId))")
            timelineRecorder?.store.connectToDatabase()
            timelineRecorder?.updateCurrentItem()
        }
    }

    private func recordingWasTakenOver(by: AppName, messageInfo: MessageInfo) {
        if LocomotionManager.highlander.recordingState.isCurrentRecorder {
            LocomotionManager.highlander.startStandby()
            NotificationCenter.default.post(Notification(name: .concededRecording, object: self, userInfo: nil))
        }
    }

    private func objectsWereModified(by: AppName, messageInfo: MessageInfo) {
        print("modifiedObjectIds: \(messageInfo.modifiedObjectIds?.count ?? 0) by: \(by)")
        if let objectIds = messageInfo.modifiedObjectIds, !objectIds.isEmpty {
            let note = Notification(name: .timelineObjectsExternallyModified, object: self, userInfo: ["modifiedObjectIds": objectIds])
            NotificationCenter.default.post(note)
        }
    }

    // MARK: - Interfaces

    public enum AppName: String, CaseIterable, Codable {
        case arcV3, arcMini, arcV4
        public var sortIndex: Int {
            switch self {
            case .arcV3: return 0
            case .arcMini: return 1
            case .arcV4: return 2
            }
        }
    }

    public struct AppState: Codable {
        public let appName: AppName
        public let recordingState: RecordingState
        public var currentItemId: UUID?
        public var currentItemTitle: String?
        public var deepSleepingUntil: Date?
        public var updated = Date()

        public var isAlive: Bool {
            if isDeepSleeping { return true }
            return updated.age < LocomotionManager.highlander.standbyCycleDuration + 2
        }
        public var isAliveAndRecording: Bool { return isAlive && recordingState != .off && recordingState != .standby }
        public var isDeepSleeping: Bool {
            guard let until = deepSleepingUntil else { return false }
            return until.age < 0
        }
    }

    public enum Message: String, CaseIterable, Codable {
        case updatedState
        case modifiedObjects
        case tookOverRecording
        func withPrefix(_ prefix: String) -> String { return "\(prefix).\(rawValue)" }
    }

    public struct MessageInfo: Codable {
        public var date: Date
        public var message: Message
        public var appName: AppName
        public var modifiedObjectIds: Set<UUID>? = nil
    }

}

// MARK: -

extension NSNotification.Name {
    static let receivedAppGroupMessage = Notification.Name("receivedAppGroupMessage")
}

// MARK: -

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
