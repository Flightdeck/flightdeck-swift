//
//  EventModel.swift
//
//  Created by Flightdeck on 07/11/2022.
//

import Foundation

// MARK: - EVENT DATA MODEL
struct Event: Codable {
    let clientType, clientConfig, clientVersion, event, datetimeUTC: String
    var datetimeLocal, timezone, language, properties, appVersion, appInstallDate, osName, osVersion, deviceManufacturer, deviceModel: String?
    var debug: Bool = false
    var firstOfSession, firstOfHour, firstOfDay, firstOfWeek, firstOfMonth, firstOfQuarter: Bool?
    var previousEvent, previousEventDatetimeUTC: String?

    enum CodingKeys: String, CodingKey {
        case clientType = "client_type"
        case clientVersion = "client_version"
        case clientConfig = "client_config"
        case event
        case datetimeUTC = "datetime_utc"
        case datetimeLocal = "datetime_local"
        case timezone, language
        case properties
        case appVersion = "app_version"
        case osName = "os_name"
        case osVersion = "os_version"
        case deviceManufacturer = "device_manufacturer"
        case deviceModel = "device_model"
        case debug = "debug"
        case firstOfSession = "first_of_session"
        case firstOfHour = "first_of_hour"
        case firstOfDay = "first_of_day"
        case firstOfWeek = "first_of_week"
        case firstOfMonth = "first_of_month"
        case firstOfQuarter = "first_of_quarter"
        case previousEvent = "previous_event"
        case previousEventDatetimeUTC = "previous_event_datetime_utc"
    }
}
