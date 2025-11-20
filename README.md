# TruckRemoteStart

This repository already includes the minimal files you need to open and run the project in Xcode. Use the following guide to place everything in the correct locations inside the Xcode workspace and confirm settings.

## Prerequisites
- Xcode 17.x with the iOS 18+ SDK (Base SDK in the project is set to iOS 18.0; Deployment Target is iOS 16.0).
- A physical iOS device running iOS 16 or later for push registration and ASWebAuthenticationSession.
- An Apple Developer account for automatic signing. Set your Team in the project after opening.

## File and Folder Layout
The repository is already laid out so you can open `TruckRemoteStart.xcodeproj` directly. If you prefer to drag files into Xcode, use this mapping:

- **`App.swift`** — Place at the project root in Xcode’s Project Navigator. It contains all models, services, view models, SwiftUI views, app entry, and delegates.
- **`Info.plist`** — Already referenced by the project; keep it at the repository root. It defines the URL scheme (`truckremote`), location usage string, and push capability flags.
- **`Resources/LaunchScreen.storyboard`** — Keep inside a `Resources` group/folder. The project file points to this storyboard for the launch screen.
- **`Assets.xcassets`** — Keep the asset catalog at the root. The `AppIcon.appiconset` only contains `Contents.json` so you can supply your own icon PNGs locally (not committed here to avoid binary assets).
- **`.gitignore`** — Root-level Git ignore tuned for Xcode builds and secret material.
- **`TruckRemoteStart.xcodeproj`** — The Xcode project with build settings, schemes, and capability configuration.

If you add the files manually, keep their relative paths identical so the references in `project.pbxproj` remain valid.

Binary icons and placeholder images are intentionally omitted so this repository stays text-only; add your own art files inside `Assets.xcassets` before archiving for release.

## Opening the Project
1. Double-click `TruckRemoteStart.xcodeproj` to open in Xcode 17.x.
2. In the Project Navigator, select the `TruckRemoteStart` target → **Signing & Capabilities**, choose your Team, and leave "Automatically manage signing" enabled.
3. Ensure the **Deployment Target** is 16.0 and the **Base SDK** is iOS 18.0 (shown as "iOS" in Xcode 17).

## Running on a Device
1. Connect your iPhone (iOS 16+), select it from the run destination menu.
2. The app requests push notification permission on launch. Approve to allow token upload.
3. OAuth uses `ASWebAuthenticationSession` with the custom URL scheme. Make sure the backend callback uses `truckremote://` unless you change it in Developer Settings.

## Developer Settings at Runtime
The Developer Settings tab lets you override `Base URL`, `Client ID`, and `Redirect Scheme` without rebuilding. Tap **Apply & Restart Auth** after edits to relaunch the PKCE flow. You can also sign out and manually upload the APNs token for debugging.

## Notable Behaviors
- First launch fetches vehicles; if the selected vehicle has no `fuelType`, the Fuel Setup sheet prompts for Gas or Diesel and patches the backend.
- The Start command shows a climate sheet; Diesel vehicles display a transient "Warming glow plugs…" banner before sending the start request.
- Location view uses MapKit to pin the vehicle’s `VehicleStatus.location`; no global Codable is added to `CLLocationCoordinate2D` (encoding handled inside `VehicleStatus`).

## Troubleshooting
- If assets appear missing, add your own icons to `Assets.xcassets/AppIcon.appiconset` using Xcode’s template filenames (e.g., `Icon-App-20x20@2x.png`, `Icon-App-20x20@3x.png`, …, `Icon-App-1024x1024@1x.png`). Keeping the file names matching the template keeps the project settings intact.
- If the auth callback fails, confirm the URL type in **Info → URL Types** matches the runtime `Redirect Scheme` setting.
- Push upload requires a real device and valid provisioning profile with Push Notifications capability enabled (already configured in the project).
- If you see `no valid “aps-environment” entitlement string found for application` or Sign in with Apple errors, open **Signing & Capabilities** and make sure your Team is selected so the bundled `TruckRemoteStart.entitlements` file (Push Notifications + Sign in with Apple) is applied to the build. If you change the bundle identifier, update the provisioning profile accordingly.

