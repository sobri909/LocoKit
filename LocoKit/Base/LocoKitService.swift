//
//  LocoKitService.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 17/11/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import CoreLocation

/**
 Settings for use of the LocoKit Service.
 */
public struct LocoKitService {

    internal static let useStaging = false
    internal static let baseUrl = "https://arc-web.herokuapp.com/api/1"
    internal static let stagingUrl = "https://arc-web-staging.herokuapp.com/api/1"
    internal static var apiUrl: String { return useStaging ? stagingUrl : baseUrl }

    internal static var apiKeyDenied = false

    private static var _apiKey: String?

    private static let mutex = UnfairLock()

    /**
     Set this property to your LocoKit API key.

     ```swift
     LocoKitService.apiKey = "<put your API key here>"
     ```

     If you do not yet have an LocoKit API key, you will need to create one on the LocoKit
     website: https://www.bigpaua.com/locokit/account

     - Note: An API key is only required for the use of Activity Type Classifiers (eg `TimelineClassifier` or
     `ActivityTypeClassifier`). This property can safely be left nil if you do not intend to make use of LocoKit's
     machine learning features.

     - Warning: Your API key's "App bundle ID" must exactly match your app's "Bundle Identifier" in Xcode.
     */
    public static var apiKey: String? {
        get { return _apiKey }
        set(key) {
            if _apiKey != nil {
                os_log("LocoKitService.apiKey cannot be set more than once.", type: .debug)
                return
            }
            _apiKey = key
        }
    }

    public static var deviceToken: Data?
    public private(set) static var requestedWakeupCall: Date?
    public private(set) static var requestingWakeupCall: Bool = false
    private static var requestTask: URLSessionDataTask?

    private static var fetchingQueries: [String] = []

    @discardableResult
    public static func requestWakeup(at requestedDate: Date) -> Bool {
        if requestingWakeupCall { return false }

        /** API key validity checks **/

        guard let apiKey = apiKey else {
            os_log("ERROR: Missing LocoKitService.apiKey.", type: .error)
            return false
        }
        guard let bundleId = Bundle.main.bundleIdentifier else {
            os_log("ERROR: Missing bundleIdentifier.", type: .error)
            return false
        }
        if apiKeyDenied {
            os_log("ERROR: LocoKitService.apiKey is invalid or denied.", type: .error)
            return false
        }

        /** wakeup call request validity checks **/

        guard let deviceToken = deviceToken else {
            os_log("Can't request a wakeup call without a deviceToken.", type: .error)
            return false
        }
        if let existing = requestedWakeupCall, existing.timeIntervalSinceNow > 60 * 2, abs(requestedDate.timeIntervalSince(existing)) < 60 * 60 {
            os_log("Ignoring wakeup call request too close to the previous request.", type: .debug)
            return false
        }

        // requested time too soon? set it to the minimum
        var wakeupDate = requestedDate
        if wakeupDate.timeIntervalSinceNow < 60 * 15 {
            wakeupDate = Date(timeIntervalSinceNow: 60 * 15)
            return false
        }

        /** checks passed, so let's make the request **/

        requestingWakeupCall = true

        os_log("requestWakeup(at: %@)", type: .debug, String(describing: wakeupDate))

        if useStaging { os_log("USING STAGING", type: .debug) }

        let query = String(format: "%@/wakeupcall", apiUrl)
        guard let url = URL(string: query) else {
            requestingWakeupCall = false
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue(apiKey, forHTTPHeaderField: "Authorization")
        request.addValue(bundleId, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "deviceToken": deviceToken.hexString, "timestamp": wakeupDate.timeIntervalSince1970
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            fatalError("request.httpBody FAIL: \(body)")
        }

        requestTask = URLSession.shared.dataTask(with: request) { data, response, error in
            requestingWakeupCall = false

            if let error = error {
                os_log("LocoKit API error: %@", type: .error, error.localizedDescription)
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

            // all good?
            if statusCode == 200 {
                requestedWakeupCall = wakeupDate
                return
            }

            if statusCode == 401 {
                self.apiKeyDenied = true
                os_log("ERROR: LocoKitService.apiKey is invalid or denied.", type: .error)
                return
            }

            if let data = data {
                print("RESPONSE [\(statusCode)]: \(String(data: data, encoding: .utf8) ?? "nil")")

                do {
                    let responseJSON = try JSONSerialization.jsonObject(with: data)
                    print("responseJSON: \(String(describing: responseJSON))")

                } catch {
                    if statusCode != 200 {
                        print("RESPONSE JSON ERROR: \(error)")
                    }
                }
            }
        }

        requestTask?.resume()

        return true
    }

    public static func fetchModelsFor(coordinate: CLLocationCoordinate2D, depth: Int, completion: @escaping ([String: Any]?) -> Void) {
        guard let apiKey = apiKey else {
            os_log("ERROR: Missing LocoKitService.apiKey.", type: .error)
            return
        }
        guard let bundleId = Bundle.main.bundleIdentifier else {
            os_log("ERROR: Missing bundleIdentifier.", type: .error)
            return
        }
        if apiKeyDenied {
            os_log("ERROR: LocoKitService.apiKey is invalid or denied.", type: .error)
            return
        }

        var query = String(format: "%@/models/?depth=%d", apiUrl, depth)

        if depth == 2 {
            query = query + String(format: "&coordinate=%.2f,%.2f", coordinate.latitude, coordinate.longitude)
        } else if depth == 1 {
            query = query + String(format: "&coordinate=%.0f,%.0f", coordinate.latitude, coordinate.longitude)
        }

        guard let url = URL(string: query) else { return }

        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "Authorization")
        request.addValue(bundleId, forHTTPHeaderField: "Authorization")

        // don't double up the requests
        var alreadyFetching = false
        mutex.sync {
            if fetchingQueries.contains(query) {
                alreadyFetching = true
            } else {
                fetchingQueries.append(query)
            }
        }
        guard !alreadyFetching else { return }

        if useStaging { os_log("USING STAGING", type: .debug) }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            self.mutex.sync { self.fetchingQueries.remove(query) }

            if let error = error { print(error); return }

            guard let data = data else { return }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(json)
                }

            } catch {
                if let response = response as? HTTPURLResponse {
                    if response.statusCode == 401 {
                        LocoKitService.apiKeyDenied = true
                        os_log("ERROR: LocoKitService.apiKey is invalid or denied.", type: .error)
                    } else {
                        os_log("LocoKit API error (statusCode: %d)", type: .error, response.statusCode)
                    }
                } else {
                    os_log("ERROR: Unknown LocoKitService error", type: .error)
                }
            }
        }

        task.resume()
    }

}
