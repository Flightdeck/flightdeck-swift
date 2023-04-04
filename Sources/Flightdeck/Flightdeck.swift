//
//  Flightdeck.swift
//
//  Created by Flightdeck on 10/01/2023.
//

import Foundation
import os
import SwiftUI


public class Flightdeck {
    public static let shared = Flightdeck()
    private static let logger = Logger()
    
    private let clientType = "iOSlib"
    private let clientVersion = "1.0.0"
    private let clientConfig: String
    private let eventAPIURL = "https://api.flightdeck.cc/v0/events"
    private let automaticEventsPrefix = "(FD) "
    private let projectId: String
    private let projectToken: String
    private let addEventMetadata: Bool
    private let trackAutomaticEvents: Bool
    private let trackUniqueEvents: Bool

    private let notificationCenter = NotificationCenter.default

    private var staticMetaData: StaticMetaData?
    private var superProperties = [String: Any]()
    private var eventsTrackedThisSession = [String]()
    private var eventsTrackedBefore = [EventPeriod: EventSet]()
    private var movedToBackgroundTime: Date?
    private var previousEvent: String?
    private var previousEventDateTimeUTC: String?

    /// Config to store configuration before init
    struct Config {
        var projectId: String
        var projectToken: String
        var addEventMetadata: Bool
        var trackAutomaticEvents: Bool
        var trackUniqueEvents: Bool
    }
    private static var config:Config?

    /// Structure to store metadata that's only updated once per session
    struct StaticMetaData {
        let language: String? = Bundle.main.preferredLocalizations.first
        let appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let appInstallDate: String? = Flightdeck.getAppInstallDate()
        let osName: String = UIDevice.current.systemName
        let deviceModel: String? = Flightdeck.getDeviceModel() /// System representation
        let deviceManufacturer: String = "Apple"
        let osVersion: String? = UIDevice.current.systemVersion.split(separator: ".").first.map { String($0) } /// Major version only for privacy reasons
    }
    
    /// Structure to store events for unique user calculation
    enum EventPeriod: String, CaseIterable, Codable, CodingKeyRepresentable {
        case hour, day, week, month, quarter
    }

    struct EventSet: Codable {
        var date: Int                    /// Int that represent current time period (e.g. hour of day, day of year, day of year, month of year)
        var events: Set<String> = []     /// Set with event names that have been tracked in current time period
    }

    
    // MARK: - initialize

    /**
     Initialize the Flightdeck singleton
     
     Project ID and project token are generated on project creation and can be found in the project settings by team admins and owners.
     
     - parameter projectId:             Project ID
     - parameter projectToken:          Project write API token
     - parameter addEventMetadata:      Enable default metadata to be added to each event
     - parameter trackAutomaticEvents:  Enable tracking automatic events
     - parameter trackUniqueEvents:     Enable tracking daily and monthly unique events (session uniqueness is always tracked)
     
     */
    class public func initialize(
        projectId: String,
        projectToken: String,
        addEventMetadata: Bool = true,
        trackAutomaticEvents: Bool = true,
        trackUniqueEvents: Bool = false
    ) {
        Flightdeck.config = Config(
            projectId: projectId,
            projectToken: projectToken,
            addEventMetadata: addEventMetadata,
            trackAutomaticEvents: trackAutomaticEvents,
            trackUniqueEvents: trackUniqueEvents
        )

        // Call shared instance to start init()
        _ = Flightdeck.shared


    }


    // MARK: - Private init()
    /// Init
    private init() {
        guard let config = Self.config else {
            fatalError("Flightdeck: Flightdeck.initialize must be called before accessing Flightdeck.shared")
        }
        self.projectId = config.projectId
        self.projectToken = config.projectToken
        self.addEventMetadata = config.addEventMetadata
        self.trackAutomaticEvents = config.trackAutomaticEvents
        self.trackUniqueEvents = config.trackUniqueEvents
        self.clientConfig = "\(self.addEventMetadata ? 1 : 0)\(self.trackAutomaticEvents ? 1 : 0)\(self.trackUniqueEvents ? 1 : 0)"
        /**
            sdkConfig
         
            Position 1: 1 = iOS SDK
            Position 2: addEventMetadata true/false (1 or 0)
            Position 3: trackAutomaticEvents true/false  (1 or 0)
            Position 4: trackUniqueEvents true/false  (1 or 0)
         **/
        
        /// Set static metadata if tracked
        if self.addEventMetadata {
            self.staticMetaData = StaticMetaData()
        }

        /// Observe app state changes
        notificationCenter.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appMovedToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appTerminated), name: UIApplication.willTerminateNotification, object: nil)
        
        /// Retrieve events that have been tracked before from UserDefaults
        if self.trackUniqueEvents {

            /// Initialize eventsTrackedBefore and set empty default values for each period
            var trackedBefore = EventPeriod.allCases.reduce(into: [EventPeriod: EventSet]()) { trackedBefore, period in
                trackedBefore[period] = EventSet(date: Self.getCurrentDatePeriod(period: period))
            }

            /// Check if userDefaults for previous eventsTrackedBefore, and set those if time period matches current
            if
                let data = UserDefaults.standard.data(forKey: "FDEventsTrackedBefore"),
                let storedEvents: [EventPeriod: EventSet] = try? JSONDecoder().decode([EventPeriod: EventSet].self, from: data)
            {
                trackedBefore.forEach { period, eventSet in
                    if
                        let storedEventSet = storedEvents[period],
                        storedEventSet.date == eventSet.date
                    {
                            trackedBefore[period] = storedEventSet
                        
                    }
                }

                /// UserDefaults data is cleaned for duplicates across periods. Revert this for use during session
                /// This makes sure that all events of a shorter time period are copied to the longer time periods
                for (index, period) in EventPeriod.allCases.enumerated() where index > 1 {
                    let prevPeriod = EventPeriod.allCases[index - 1]
                    trackedBefore[period]!.events.formUnion(trackedBefore[prevPeriod]!.events)
                }

            }
            
            self.eventsTrackedBefore = trackedBefore
        }

        /// Track session start
        self.trackAutomaticEvent("Session start")
    }


    // MARK: - setSuperProperties

    /**
     Sets properties that are included with each event during the duration of the current initialization.
     Super properties are reset everytime the app is terminated.
     Make sure to set necessary super properties everytime after Flightdeck.initialize() is called.
     
     Super properties can be overwritten by similarly named properties that are provided with trackEvent()
     
     - parameter properties: properties dictionary
     */

    public func setSuperProperties(_ properties: [String: Any]) {
        self.superProperties = properties
    }



    // MARK: - trackEvent

    /**
     Tracks an event with properties.
     Properties are optional and can be added only if needed.
     
     Properties will allow you to segment your events in your Mixpanel reports.
     Property keys must be String objects and the supported value types need to conform to MixpanelType.
     MixpanelType can be either String, Int, UInt, Double, Float, Bool, [MixpanelType], [String: MixpanelType], Date, URL, or NSNull.
     If the event is being timed, the timer will stop and be added as a property.
     
     - parameter event:      event name
     - parameter properties: properties dictionary
     */

    /// Public trackEvent function
    public func trackEvent(_ event: String, properties: [String: Any]? = nil){
        if event.hasPrefix(self.automaticEventsPrefix) {
            Self.logger.error("Flightdeck: Event name has forbidden prefix \(self.automaticEventsPrefix)")
        } else {
            self.trackEventCore(event, properties: properties)
        }
    }

    /// Private trackEvent function used for automatic events
    private func trackAutomaticEvent(_ event: String, properties: [String: Any]? = nil){
        if self.trackAutomaticEvents {
            self.trackEventCore("\(self.automaticEventsPrefix)\(event)", properties: properties)
        }
    }

    /// Private trackEventCore function
    private func trackEventCore(_ event: String, properties: [String: Any]? = nil){

        let currentDateTime = self.getCurrentDateTime()

        /// Initialize a new Event object with event string and current UTC datetime
        var eventData = Event(
            clientType: self.clientType,
            clientVersion: self.clientVersion,
            clientConfig: self.clientConfig,
            event: event,
            datetimeUTC: currentDateTime.datetimeUTC
        )

        /// Set custom properties, merged with super properties, if any
        if var props = properties {
            props.merge(self.superProperties) { (current, _) in current }
            eventData.properties = self.stringifyProperties(properties: props)
        } else if !self.superProperties.isEmpty {
            eventData.properties = self.stringifyProperties(properties: superProperties)
        }

        /// Add metadata to event
        if (self.addEventMetadata) {

            /// Set local time and timzone
            eventData.datetimeLocal = currentDateTime.datetimeLocal
            eventData.timezone = currentDateTime.timezone

            /// Set static metadata
            if let staticMetaData = self.staticMetaData {
                eventData.language = staticMetaData.language
                eventData.appVersion = staticMetaData.appVersion
                eventData.appInstallDate = staticMetaData.appInstallDate
                eventData.osName = staticMetaData.osName
                eventData.osVersion = staticMetaData.osVersion
                eventData.deviceModel = staticMetaData.deviceModel
                eventData.deviceManufacturer = staticMetaData.deviceManufacturer
            }

        }

        /// Set previous event name and datetime if any
        if
            let previousEvent = self.previousEvent,
            let previousEventDateTimeUTC = self.previousEventDateTimeUTC
        {
            eventData.previousEvent = previousEvent
            eventData.previousEventDatetimeUTC = previousEventDateTimeUTC
        }

        /// Store current event name and datetime for use as future previous event
        self.previousEvent = eventData.event
        self.previousEventDateTimeUTC = eventData.datetimeUTC

        /// Set event unqiueness of current session
        eventData.firstOfSession = self.trackFirstOfSession(event: eventData.event)

        /// Set daily and monthly uniqueness of event
        if self.trackUniqueEvents {
            let isFirstOf = trackFirstOfPeriod(event: eventData.event)
            eventData.firstOfHour = isFirstOf[.hour]
            eventData.firstOfDay = isFirstOf[.day]
            eventData.firstOfWeek = isFirstOf[.week]
            eventData.firstOfMonth = isFirstOf[.month]
            eventData.firstOfQuarter = isFirstOf[.quarter]
        }

        /// Convert Event object to JSON
        guard let eventDataJSON = try? JSONEncoder().encode(eventData) else {
            Self.logger.error("Flightdeck: Failed to encode event data to JSON")
            return
        }

        /// Post event data
        guard let url = URL(string: "\(self.eventAPIURL)?name=\(self.projectId)") else {
            Self.logger.error("Flightdeck: Failed to use Flightdeck API URL")
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(self.projectToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = eventDataJSON
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if (error != nil) {
                Self.logger.error("Flightdeck: Failed to send event to server. Error: \(error?.localizedDescription ?? "No error data")")
                return
            }
        }.resume()
    }


    // MARK: - Helper functions

    /**
     Get the current UTC datetime, local datetime, and timezone code
     
     - parameters: none
     - returns: CurrentDateTime object
    */

    struct CurrentDateTime {
        var datetimeUTC: String
        var datetimeLocal: String
        var timezone: String
    }

    private func getCurrentDateTime() -> CurrentDateTime {
        let dateNow = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        dateFormatter.timeZone = TimeZone.current
        let datetimeLocal = dateFormatter.string(from: dateNow)

        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        let datetimeUTC = dateFormatter.string(from: dateNow)

        return CurrentDateTime(
            datetimeUTC: datetimeUTC,
            datetimeLocal: datetimeLocal,
            timezone: TimeZone.current.identifier
        )
    }


    /**
     Turn optional properties array into strinified JSON
     
     - parameter properties: properties array
     - returns: Stringyfied JSON of properties array
    */
    private func stringifyProperties(properties: [String: Any]) -> String {
        guard let jsonProperties = try? JSONSerialization.data(withJSONObject: properties) else {
            Self.logger.error("Flightdeck: Failed to convert event properties to JSON. Check your properties dictionary.")
            return ""
        }
        guard let jsonPropertiesString = String(data: jsonProperties, encoding: .utf8) else {
            Self.logger.error("Flightdeck: Failed to convert event properties to JSON string. Check your properties dictionary.")
            return ""
        }
        
        return jsonPropertiesString
    }


    /**
     Check if a specified event has been tracked before and set event as tracked if it was the first occurance.
     
     - parameter event: Event name
     - returns:         true if event is first of session, false if event has been tracked before
    */
    private func trackFirstOfSession(event: String) -> Bool {
        if self.eventsTrackedThisSession.contains(event) {
            return false
        } else {
            self.eventsTrackedThisSession.append(event)
            return true
        }
    }

    /**
     Check if a specified event has been tracked before during the current period and set event as tracked if it was the first occurance.
     
     - parameter event:     Event name
     - parameter period:    Period string ("day", "month")
     - returns:             Dictionary of EventPeriod keys with boolean reflecting
                            whether an event has been tracked before during the period
    */
    private func trackFirstOfPeriod(event: String) -> [EventPeriod: Bool] {
        
        /// Set return variable with default values False
        var isFirstOf = EventPeriod.allCases.reduce(into: [EventPeriod: Bool]()) { isFirstOf, period in
            isFirstOf[period] = false
        }
        
        /// Loop through eventsTrackedBefore to check event for each time period
        for (period, eventSet) in self.eventsTrackedBefore {
            let currentDatePeriod = Self.getCurrentDatePeriod(period: period)
            
            /// Check if eventsCollection in memory is from the current time period before checking for the event
            if eventSet.date == currentDatePeriod {
                if !eventSet.events.contains(event) {
                    var updatedEventSet = eventSet
                    updatedEventSet.events.insert(event)
                    self.eventsTrackedBefore[period] = updatedEventSet
                    isFirstOf[period] = true
                }
                
            /// If eventsCollection in memory is old, empty the collection and set date to current time period
            } else {
                self.eventsTrackedBefore[period] = EventSet(date: currentDatePeriod)
                isFirstOf[period] =  true
            }
        }
        
        return isFirstOf
    }


    /**
     Get the current ordinal number representing a date period in this year.
     
     - parameter period:    hour, day, week, month, or quarter
     - returns:             Integer representing the period in the year (or other larger timeframe)
    */
    private static func getCurrentDatePeriod(period: EventPeriod) -> Int {
        let calender = Calendar.current
        let date = Date()

        switch period {
        case .hour:
            return calender.ordinality(of: .hour, in: .year, for: date) ?? Calendar.current.component(.hour, from: date)
        case .day:
            return calender.ordinality(of: .day, in: .year, for: date) ?? Calendar.current.component(.day, from: date)
        case .week:
            return calender.component(.weekOfYear, from: date)
        case .month:
            return calender.component(.month, from: date)
        case .quarter:
            return calender.component(.quarter, from: date)
        }
    }
    
    
    /**
     Get app install date
     
     - parameters:  none
     - returns:     Install date string
    */
    private static func getAppInstallDate() -> String? {
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: documentsDirectory.path)
                if let creationDate = attributes[.creationDate] as? Date {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd" // Don't store exact time for privacy reasons
                    dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
                    return dateFormatter.string(from: creationDate)
                }
            } catch {
                self.logger.warning("Flightdeck: Unable to determine app install date")
            }
        }
        return nil
    }
    
    
    /**
     Returns device model as represented by the syste. This slightly differs from marketing names of Apple devices.
     More information: https://github.com/EmilioOjeda/Device
     
     
     - parameter period:    hour, day, week, month, or quarter
     - returns:             Integer representing the period in the year (or other larger timeframe)
    */
    private static func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return String(
            cString: [UInt8](
                Data(
                    bytes: &systemInfo.machine,
                    count: Int(_SYS_NAMELEN)
                )
            )
        )
    }


    /**
     Perform actions on app lifecylce state changes
     
     Session start: Occurs when Flightdeck singleton is initialized or app moves to foreground
     Session end: Occurs when app is terminated or moves to forground after 60 seconds of being inactive
     
     Previous event: Event name and datetime of the previous event are removed on session end
     
     Unique events: Store events fired today and this month in UserDefaults when app terminates
    */
    @objc private func appMovedToBackground() {
        self.movedToBackgroundTime = Date()
    }

    @objc private func appMovedToForeground() {
        if let movedToBackgroundTime = self.movedToBackgroundTime {

            if Date().timeIntervalSince(movedToBackgroundTime) > 60 {
                self.eventsTrackedThisSession.removeAll()
                self.previousEvent = nil
                self.previousEventDateTimeUTC = nil
                self.trackAutomaticEvent("Session start")
            }
        }
    }

    @objc private func appTerminated() {
        if !self.trackUniqueEvents { return }

        /// Compress eventsTrackedBefore by removing duplicate sessions across time periods
        var eventsTrackedBefore = self.eventsTrackedBefore
        for (index, period) in EventPeriod.allCases.enumerated() where index > 1 {
            let prevPeriod = EventPeriod.allCases[index - 1]
            eventsTrackedBefore[period]!.events.subtract(eventsTrackedBefore[prevPeriod]!.events)
        }
        
        /// Store eventsTrackedBefore for use in later sessions
        if let encodedData = try? JSONEncoder().encode(eventsTrackedBefore) {
            UserDefaults.standard.set(encodedData, forKey: "FDEventsTrackedBefore")
        }
    }

}
