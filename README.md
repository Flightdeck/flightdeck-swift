# ![flightdeck-logo-flat-brand](https://user-images.githubusercontent.com/3425455/212749718-85e425da-1e17-4c80-8dc0-c7db3b04490c.svg) Flightdeck Swift

## Installation: Swift Package Manager
Use Swift Package Manager to add Flightdeck to your project in Xcode:
1. In Xcode, select File > Add Packages...
2. Enter the package URL for this repository [Flightdeck Swift](https://github.com/Flightdeck/flightdeck-swift/).

## Initialize Flightdeck

### SwiftUI
Import FlightDeck into your `@main` struct, and initialize Flightdeck within `init()`:
```swift
import Flightdeck

@main
struct MyApp: App {
    init() {
        Flightdeck.initialize(
            projectId: "FLIGHTDECK_PROJECT_ID",
            projectToken: "FLIGHTDECK_PROJECT_TOKEN"
        )
    }
    
    ...
}
```


### UIKit
Import Flightdeck into AppDelegate.swift, and initialize Flightdeck within application:didFinishLaunchingWithOptions:
```swift
import Flightdeck

func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
    ...
    Flightdeck.initialize(projectId: "FLIGHTDECK_PROJECT_ID", projectToken: "FLIGHTDECK_PROJECT_TOKEN")
    ...
}
```


### Advanced initialization
`Flightdeck.initialize(...)`

#### Parameters

| Parameter             | Required      | Type                    | Description                                                                 |
| --------------------- | ------------- | ----------------------- | --------------------------------------------------------------------------- |
| projectId             | Required      | `String`                | Project ID¹                                                                 |
| ProjectToken          | Required      | `String`                | Project write API token¹                                                    |
| addEventMetadata      | Optional      | `Bool` default *true*   | Enable device, timezone, and app version metadata to be added to each event |
| trackAutomaticEvents  | Optional      | `Bool` default *true*   | Enable tracking automatic events (e.g. Session start)                       |
| trackUniqueEvents     | Optional      | `Bool` default *false*  | Enable tracking daily and monthly unique events²                            |

¹ Project ID and project token are generated on project creation and can be found in the project settings by team admins and owners.

² In order to track whether an event has been sent before during the current week or month, a list of previously sent events is store on the device. The information stored includes event names only. No idenfitying information or metadata is stored. However, legislation in some countries forbids storing information on a user's device without explicit permission, even when this information does not contain personal data. If you want to run Flightdeck without making any use of permanent storage, keep this option disabled. Note that session uniqueness is always tracked, because this doesn't require storing any inromation.

## Track event

### Send data

```swift
Flightdeck.shared.trackEvent("New project created", properties: [
  "Subscription type": "premium",
  "Active projects": 12,
])
```

#### Parameters

| Parameter  | Required   | Type          | Description                                   |
| ---------- | ---------- | ------------- | --------------------------------------------- |
| event      | Required   | `String`      | Name of the event                             |
| properties | Optional   | `Dictionary`¹ | Any metadata you want to attach to the event  |

¹ The properties dictionary expects keys as `String` and any type that can be converted to string (e.g. String, Int, Double, Bool) as value.


## Set super properties

Set properties that are automatically sent with each event.

```swift
Flightdeck.shared.setSuperProperties([
  "Subscription type": "premium",
  "Active projects": 12,
])
```

When you pass a similarly named property with `trackEvent()` as one of the super properties, the super proerty will be overwritten for the specific trackEvent() call.
