# Keep Sure

Keep Sure is a SwiftUI iOS app for tracking product returns, warranties, and proof of purchase in one calm, premium experience.

Instead of acting like a receipt folder, Keep Sure is designed to help people act before they lose money. It captures receipts, stores purchase details, tracks return windows and warranty periods, and surfaces the deadlines that matter most.

## Highlights

- `Home` dashboard focused on urgent return deadlines, upcoming warranties, recent items, and family activity
- `Capture` flow with receipt scanning, OCR-powered extraction review, and manual entry
- `Profile` area for Gmail connection, household settings, and notification preferences
- Core Data persistence for tracked purchases and timeline metadata
- Gmail import flow for turning purchase emails into tracked items
- Soft, premium SwiftUI visual design tailored for a consumer-facing app

## Tech Stack

- SwiftUI
- Core Data
- VisionKit and Vision
- AuthenticationServices
- Gmail REST API

## Project Status

Keep Sure is currently an early product prototype / MVP.

The project already includes:

- a 3-tab app shell
- receipt scanning and extraction review
- return and warranty tracking models
- Gmail authentication and import groundwork

The Gmail flow still depends on Google Cloud OAuth configuration, consent-screen setup, and approved test users during development.

## Getting Started

1. Open [KeepSure.xcodeproj](/Users/abhishekgangdeb/Documents/Ok/KeepSure/KeepSure.xcodeproj/project.pbxproj) in Xcode.
2. Select your signing team and bundle settings if needed.
3. If you want Gmail import to work, configure your Google OAuth client, consent screen, and test users.
4. Build and run on a simulator or device.

## Repository Structure

- [KeepSure/App](/Users/abhishekgangdeb/Documents/Ok/KeepSure/KeepSure/App)
- [KeepSure/Models](/Users/abhishekgangdeb/Documents/Ok/KeepSure/KeepSure/Models)
- [KeepSure/Persistence](/Users/abhishekgangdeb/Documents/Ok/KeepSure/KeepSure/Persistence)
- [KeepSure/Views](/Users/abhishekgangdeb/Documents/Ok/KeepSure/KeepSure/Views)
- [KeepSure/Resources](/Users/abhishekgangdeb/Documents/Ok/KeepSure/KeepSure/Resources)
- [KeepSureTests](/Users/abhishekgangdeb/Documents/Ok/KeepSure/KeepSureTests)
- [KeepSureUITests](/Users/abhishekgangdeb/Documents/Ok/KeepSure/KeepSureUITests)

## License

This project is licensed under the MIT License. See [LICENSE](/Users/abhishekgangdeb/Documents/Ok/KeepSure/LICENSE).

