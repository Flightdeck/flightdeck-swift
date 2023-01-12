# Flightdeck

## Installation: Swift Package Manager

## Initialize Flightdeck
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

## Track event

```
Flightdeck.shared.trackEvent("Invite team member", properties: {"team members": 6})
```

## Set super properties

Properties that are automatically sent with each event
```
Flightdeck.shared.setSuperProperties({"account type": "free", "saved projects": 3})
```
