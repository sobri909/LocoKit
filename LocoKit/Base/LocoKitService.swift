//
//  LocoKitService.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 17/11/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

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
                logger.debug("LocoKitService.apiKey cannot be set more than once")
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
            logger.error("ERROR: Missing LocoKitService.apiKey")
            return false
        }
        guard let bundleId = Bundle.main.bundleIdentifier else {
            logger.error("ERROR: Missing bundleIdentifier")
            return false
        }
        if apiKeyDenied {
            logger.error("ERROR: LocoKitService.apiKey is invalid or denied")
            return false
        }

        /** wakeup call request validity checks **/

        guard let deviceToken = deviceToken else {
            logger.error("Can't request a wakeup call without a deviceToken")
            return false
        }
        if let existing = requestedWakeupCall, existing.timeIntervalSinceNow > 60 * 2, abs(requestedDate.timeIntervalSince(existing)) < 60 * 60 {
            logger.debug("Ignoring wakeup call request too close to the previous request")
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

        logger.debug("requestWakeup(at: \(String(describing: wakeupDate)))")

        if useStaging { logger.debug("USING STAGING") }

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
                logger.error("LocoKit API error: \(error.localizedDescription)")
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
                logger.error("ERROR: LocoKitService.apiKey is invalid or denied")
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

}
