//
//  Logging.swift
//  LocoKit Demo App
//
//  Created by Matt Greenfield on 7/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import SwiftNotes

extension NSNotification.Name {
    public static let logFileUpdated = Notification.Name("logFileUpdated")
}

func log(_ format: String = "", _ values: CVarArg...) {
    DebugLog.logToFile(format, values)
}

class DebugLog {
    static let formatter = DateFormatter()

    static func logToFile(_ format: String = "", _ values: CVarArg...) {
        let prefix = String(format: "[%@] ", Date().timeLogString)
        let logString = String(format: prefix + format, arguments: values)
        do {
            try logString.appendLineTo(logFile)
        } catch {
            // don't care
        }
        print("[LocoKit] " + logString)
        trigger(.logFileUpdated)
    }

    static var logFile: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).last!
        return dir.appendingPathComponent("LocoKitDemoApp.log")
    }

    static func deleteLogFile() {
        do {
            try FileManager.default.removeItem(at: logFile)
        } catch {
            // don't care
        }
        trigger(.logFileUpdated)
    }
}

extension Date {
    var timeLogString: String {
        let formatter = DebugLog.formatter
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: self)
    }
}

extension String {
    func appendLineTo(_ url: URL) throws {
        try appendingFormat("\n").appendTo(url)
    }

    func appendTo(_ url: URL) throws {
        let dataObj = data(using: String.Encoding.utf8)!
        try dataObj.appendTo(url)
    }
}

extension Data {
    func appendTo(_ url: URL) throws {
        if let fileHandle = try? FileHandle(forWritingTo: url) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        } else {
            try write(to: url, options: .atomic)
        }
    }
}

