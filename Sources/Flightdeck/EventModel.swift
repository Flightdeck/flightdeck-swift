//
//  EventModel.swift
//
//  Created by Flightdeck on 07/11/2022.
//

import Foundation

// MARK: - EVENT DATA MODEL
struct Event: Codable {
    let event, datetimeUTC: String
    var datetimeLocal, timezone, language, properties, sdkVersion, appVersion, appInstallDate, osName, osVersion, deviceManufacturer, deviceModel: String?
    var firstOfSession, firstOfDay, firstOfMonth: Bool?
    var previousEvent, previousEventDatetimeUTC: String?

    enum CodingKeys: String, CodingKey {
        case event
        case datetimeUTC = "datetime_utc"
        case datetimeLocal = "datetime_local"
        case timezone, language
        case properties
        case sdkVersion = "sdk_version"
        case appVersion = "app_version"
        case appInstallDate = "app_install_date"
        case osName = "os_name"
        case osVersion = "os_version"
        case deviceManufacturer = "device_manufacturer"
        case deviceModel = "device_model"
        case firstOfSession = "first_of_session"
        case firstOfDay = "first_of_day"
        case firstOfMonth = "first_of_month"
        case previousEvent = "previous_event"
        case previousEventDatetimeUTC = "previous_event_datetime_utc"
    }
    
    init(event: String, datetimeUTC: String) {
        self.event = event
        self.datetimeUTC = datetimeUTC
    }
}
