//
//  Flightdeck.swift
//
//  Created by Flightdeck on 10/01/2023.
//

import Foundation
import os
import SwiftUI

open class Flightdeck {
    static let shared = Flightdeck()
    private let sdkVersion = "1.0.0"
    private let eventAPIURL = "https://api.flightdeck.com/v0/events"
    private let automaticEventsPrefix = "(FD) "
    private let projectId: String
    private let projectToken: String
    private let trackAutomaticEvents: Bool
    private let trackUniqueEvents: Bool
    private let addEventMetadata: Bool
    
    private let logger = Logger()
    private let notificationCenter = NotificationCenter.default
    private let userDefaults = UserDefaults.standard
    
    private var superProperties = [String: Any]()
    private var eventsTrackedThisSession = [String]()
    private var eventsTrackedBefore: [String: EventsTrackedBefore] = [
        "day": EventsTrackedBefore(date: Calendar.current.component(.day, from: Date())),
        "month": EventsTrackedBefore(date: Calendar.current.component(.month, from: Date()))
    ]
    private var movedToBackgroundTime: Date?
    private var previousEvent: String?
    private var previousEventDateTimeUTC: String?
    
    /// Config to store configuration before init
    struct Config {
        var projectId: String
        var projectToken: String
        var trackAutomaticEvents: Bool
        var trackUniqueEvents: Bool
        var addEventMetadata: Bool
    }
    private static var config:Config?
    
    /// Used to store events for daily and monthly unique calculation
    struct EventsTrackedBefore {
        var date: Int               /// Int that represent current time period (e.g. day of year, month of year)
        var events = [String]()     /// Array with event names that have been tracked in current time period
    }

    
    // MARK: - Private init()
    /// Init
    private init() {
        guard let config = Flightdeck.config else {
            fatalError("Flightdeck: Flightdeck.initialize must be called before accessing Flightdeck.shared")
        }
        self.projectId = config.projectId
        self.projectToken = config.projectToken
        self.trackAutomaticEvents = config.trackAutomaticEvents
        self.trackUniqueEvents = config.trackAutomaticEvents
        self.addEventMetadata = config.trackAutomaticEvents
        
        /// Observe app state changes
        notificationCenter.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appMovedToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appTerminated), name: UIApplication.willTerminateNotification, object: nil)
        
        /// Retrieve events that have been tracked before from UserDefaults
        if self.trackUniqueEvents {
            if let eventsCollection = userDefaults.object(forKey: "eventsTrackedBefore") as? [String: EventsTrackedBefore] {
                if eventsCollection["day"]?.date == Calendar.current.component(.day, from: Date()) {
                    /// Still the same day: Reuse entire past events collection from UserDefaults
                    self.eventsTrackedBefore = eventsCollection
                } else if eventsCollection["month"]?.date == Calendar.current.component(.month, from: Date()){
                    /// New day, same month: Reuse monthly events from UserDefaults, but reset daily unique
                    self.eventsTrackedBefore["month"] = eventsCollection["month"]
                } /// New day and month, leave the empty default values unchanged
            }
        }
        
        /// Track session start
        self.trackAutomaticEvent("Session Start")
    }
    
    // MARK: - initialize
    
    /**
     Initialize the Flightdeck singleton
     
     Project ID and project token are generated on project creation and can be found in the project settings by team admins and owners.
     
     - parameter projectId:             Project ID
     - parameter projectToken:          Project write API token
     - parameter trackAutomaticEvents:  Enable tracking automatic events
     - parameter trackUniqueEvents:     Enable tracking daily and monthly unique events (session uniqueness is always tracked)
     - parameter addEventMetadata:      Enable default metadata to be added to each event
     
     */
    public class func initialize(
        projectId: String,
        projectToken: String,
        trackAutomaticEvents: Bool = true,
        trackUniqueEvents: Bool = true,
        addEventMetadata: Bool = true
    ){
        Flightdeck.config = Config(
            projectId: projectId,
            projectToken: projectToken,
            trackAutomaticEvents: trackAutomaticEvents,
            trackUniqueEvents: trackUniqueEvents,
            addEventMetadata: addEventMetadata
        )
        
        // Call shared instance to start init()
        _ = Flightdeck.shared
        
        
    }
    // MARK: - setSuperProperties
    
    /**
     Sets properties that are included with each event during the duration of the current initialization.
     Super properties are reset everytime the app is terminated. Make sure to set necessary super properties everytime after Flightdeck.initialize() is called.
     
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
            logger.error("Flightdeck: Event name has forbidden prefix \(self.automaticEventsPrefix)")
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
        var eventData = Event(event: event, datetimeUTC: currentDateTime.datetimeUTC)
        
        /// Set custom properties, merged with super properties, if any
        if var props = properties {
            props.merge(self.superProperties) { (current, _) in current }
            eventData.properties = self.stringifyProperties(properties: props)
        } else if !self.superProperties.isEmpty {
            eventData.properties = self.stringifyProperties(properties: superProperties)
        }
        
        /// Set SDK version
        eventData.sdkVersion = self.sdkVersion
        
        if (self.addEventMetadata) {
            
            /// Set local time and timzone
            eventData.datetimeLocal = currentDateTime.datetimeLocal
            eventData.timezone = currentDateTime.timezone
            
            /// Set current UI language
            eventData.language = Bundle.main.preferredLocalizations.first
            
            /// Set app version, if available
            if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                eventData.appVersion = appVersion
            }
            
            /// Set OS name and major OS version
            eventData.osName = UIDevice.current.systemName
            eventData.osVersion = String(describing: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) /// Major version only for privacy reasons
            eventData.deviceModel = UIDevice.current.model
            eventData.deviceManufacturer = "Apple"
            
            /// Set app install date
            if let appInstalldate = self.getAppInstallDate() {
                eventData.appInstallDate = appInstalldate
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
        eventData.firstOfSession = self.isFirstOfSession(event: eventData.event)
        
        /// Set daily and monthly uniqueness of event
        if self.trackUniqueEvents {
            eventData.firstOfDay = self.isFirstOfPeriod(event: eventData.event, period: "day")
            eventData.firstOfMonth = self.isFirstOfPeriod(event: eventData.event, period: "month")
        }
        
        /// Convert Event object to JSON
        guard let eventDataJSON = try? JSONEncoder().encode(eventData) else {
            self.logger.error("Flightdeck: Failed to encode even data to JSON")
            return
        }
        
        /// Post event data
        guard let url = URL(string: "\(self.eventAPIURL)?name=\(self.projectId)") else {
            self.logger.error("Flightdeck: Failed to use Flightdeck API URL")
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(self.projectToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = eventDataJSON
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if (error != nil) {
                self.logger.error("Flightdeck: Failed to send event to server. Error: \(error?.localizedDescription ?? "No error data")")
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
            self.logger.error("Flightdeck: Failed to convert event properties to JSON. Check your properties dictionary.")
            return ""
        }
        guard let jsonPropertiesString = String(data: jsonProperties, encoding: .utf8) else {
            self.logger.error("Flightdeck: Failed to convert event properties to JSON string. Check your properties dictionary.")
            return ""
        }
        
        return jsonPropertiesString
    }
    
    
    /**
     Check when the app was installed and return this value as a string
     
     - parameters: none
     - returns: Date string or nil if install date retrieval fails
    */
    private func getAppInstallDate() -> String? {
        guard
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last,
            let attributes = try? FileManager.default.attributesOfItem(atPath: documentsURL.path),
            let creationDate = attributes[.creationDate] as? String
        else { return nil }
        return creationDate
    }
    
    
    /**
     Check if a specified event has been tracked before during the current session
     
     - parameter event: Event name
     - returns:         true if event is first of session, false if event has been tracked before
    */
    private func isFirstOfSession(event: String) -> Bool {
        if self.eventsTrackedThisSession.contains(event) {
            return false
        } else {
            self.eventsTrackedThisSession.append(event)
            return true
        }
    }
    
    /**
     Check if a specified event has been tracked before during the current month
     
     - parameter event:     Event name
     - parameter period:    Period string ("day", "month")
     - returns:             true if event is first of this month, false if event has been tracked before
    */
    private func isFirstOfPeriod(event: String, period: String) -> Bool {
        guard let eventsCollection = self.eventsTrackedBefore["period"] else {
            return false
        }
        
        if eventsCollection.events.contains(event) {
            return false
        } else {
            self.eventsTrackedBefore["period"]?.events.append(event)
            return true
        }
    }
    
    
    /**
     Perform actions on app lifecylce state changes
     
     Session start: Occurs when Flightdeck singleton is initialized or app moves to foreground
     Session end: Occurs when app is terminated or moves to forground after 60 seconds of being inactive
     
     Previous event: Event name and datetime of the previous event are removed on session end
     
     Unique events: Store events fired today and this month in UserDefaults when app terminates
    */
    @objc private func appMovedToBackground(){
        self.movedToBackgroundTime = Date()
    }

    @objc private func appMovedToForeground(){
        if let movedToBackgroundTime = self.movedToBackgroundTime {
            if Date().timeIntervalSince(movedToBackgroundTime) > 60  {
                self.trackAutomaticEvent("Session End")
                self.eventsTrackedThisSession.removeAll()
                self.previousEvent = nil
                self.previousEventDateTimeUTC = nil
            }
            self.trackAutomaticEvent("Session Start")
        }
    }
    
    @objc private func appTerminated(){
        self.trackAutomaticEvent("Session End")
        
        if self.trackUniqueEvents {
            userDefaults.set(self.eventsTrackedBefore, forKey: "eventsTrackedBefore")
        }
    }
}

