# MacroEngine — SwiftUI implementation

MacroEngine is a UK-oriented nutrition and meal-tracking app scaffold using SwiftUI, Observation, Swift Charts, AVFoundation and Open Food Facts. The source files follow the supplied Slate visual system and keep the original dashboard/search/scanner components in place.

## Included features

- **Onboarding:** age, sex used by the estimate, height (cm), weight (kg), activity level, cutting/bulking/maingain approach and an editable macro review.
- **Target estimates:** Mifflin–St Jeor BMR, activity multipliers, goal-based energy adjustments, and an initial protein/fat/carbohydrate split.
- **Dashboard:** calorie ring, segmented Protein/Carbs/Fat ring with spaced arcs, macro progress bars, and separate Breakfast/Lunch/Dinner/Snacks logs.
- **Food logging:** Open Food Facts name search and barcode lookup, clear-search action, gram text field + slider + stepper controls, and meal-category assignment.
- **Food library:** favourites and reusable custom meals composed from favourite foods.
- **Weight telemetry:** daily kg entries persisted locally and a Swift Charts line graph across the recorded history.
- **Persistence:** local JSON-encoded values in `UserDefaults`, with a migration fallback that treats older diary entries with no meal category as Snacks.

## Important platform note

VS Code on Windows is suitable for editing Swift files and using Git, but **the standard Apple iOS build toolchain (Xcode, iOS Simulator and signing) runs on macOS**. The repository intentionally contains app source and an XcodeGen project specification rather than pretending a Windows build can validate an iOS target. Generate the Xcode project on a Mac, or use a macOS CI runner.

## Build on macOS

1. Install Xcode 15 or later and open it once to install its platform components.
2. Install XcodeGen (`brew install xcodegen`) if it is not installed.
3. From this folder, run:

   ```sh
   xcodegen generate
   open MacroEngine.xcodeproj
   ```

4. Select the `MacroEngine` scheme and run on an iOS 17+ simulator or a physical iPhone.
5. Camera barcode scanning needs `NSCameraUsageDescription`. This project specifies it in `project.yml`; if you create a project manually, add the same key to the app target's Info settings:

   `MacroEngine uses the camera to scan food barcodes.`

The simulator may not provide a usable live camera feed, so test scanning on a physical device. Search remains available without camera access.

## Build an installable IPA with GitHub Actions

The `Build iOS IPA` workflow archives the app and exports an Ad Hoc signed IPA on pushes to `main` or when started manually from the Actions tab. Ad Hoc signing requires an Apple Developer account, an Apple Distribution certificate, and a provisioning profile that includes the iPhone's registered device identifier.

Add these repository actions secrets under **Settings → Secrets and variables → Actions**:

- `IOS_CERTIFICATE_BASE64`: base64-encoded `.p12` Apple Distribution certificate.
- `IOS_CERTIFICATE_PASSWORD`: password used when exporting that `.p12` file.
- `IOS_PROVISIONING_PROFILE_BASE64`: base64-encoded Ad Hoc provisioning profile for `com.double0daniel.MacroEngine`.
- `IOS_TEAM_ID`: Apple Developer team ID.
- `KEYCHAIN_PASSWORD`: any temporary password for the workflow's build keychain.

On macOS, base64-encode the `.p12` and `.mobileprovision` files with `base64 -i file -o file.base64`, then copy their contents into the matching secrets. Register the iPhone's UDID in the Apple Developer account and include it in the Ad Hoc profile before exporting the profile. After a successful workflow run, download `MacroEngine-IPA` from the run's **Artifacts** section and install the IPA using a device installation tool such as Apple Configurator.

The signing certificate and profile are private credentials. Store them only in GitHub Actions secrets; do not commit them to this repository.

## VS Code / Git setup

- Open this folder as the workspace.
- Install a Swift language extension for navigation and formatting; remember that IntelliSense is not a substitute for building the target in Xcode.
- The app's entry point is `MacroEngineApp.swift`. Add the `.swift` files listed under the app target in `project.yml` if constructing the Xcode project manually.
- To put the source in the empty GitHub repository, from this folder run:

  ```sh
  git init
  git add .
  git commit -m "Implement MacroEngine SwiftUI app"
  git branch -M main
  git remote add origin https://github.com/double0daniel/MacroEngine.git
  git push -u origin main
  ```

  If the repository has already been initialised locally, skip `git init`. If `origin` already exists, use `git remote set-url origin https://github.com/double0daniel/MacroEngine.git` instead.

## Target estimation notes

BMR follows Mifflin–St Jeor:

- Male coefficient: `+5`
- Female coefficient: `−161`
- Prefer not to say: midpoint coefficient (`−78`) as an estimate

Estimated maintenance calories are `BMR × activity multiplier` (1.20, 1.375, 1.55, 1.725 or 1.90). Starting goal adjustments are −15% fat loss, −20% overall weight loss, +8% lean bulk, +15% higher-surplus bulk and maintenance for maingain. Initial macros use a goal-specific protein-per-kg estimate, approximately 25% of target energy from fat and remaining energy from carbohydrates. On the review screen, manually changed grams recalculate the displayed target using 4 kcal/g protein, 4 kcal/g carbohydrate and 9 kcal/g fat.

These settings are intentionally transparent and editable: equations provide starting estimates, not personalised medical advice or a guarantee of results. MacroEngine's default calculator is intended for adults. People with medical conditions, a history of disordered eating, pregnancy, or other specific nutrition needs should seek qualified guidance before following calorie targets.

## Data / production considerations

- Open Food Facts is community-maintained; nutrition values, images, portion sizes and UK product tagging may be missing or inaccurate. Search tries UK-tagged products first and falls back to the wider catalogue. Barcode lookup uses the worldwide catalogue.
- Diary logs, favourites, custom meals, profile and weight entries currently live on-device in `UserDefaults`. This keeps the implementation self-contained and compatible with the supplied store; for a larger production app, consider migrating the collections to SwiftData and adding export/backup and deletion controls.
- No analytics, login, cloud sync or external subscription SDK is included.

## Source map

- `Theme.swift`, `Components.swift`, `AppIconArtwork.swift`: slate palette, shared UI primitives and brand artwork.
- `Models.swift`: Codable data, the observable store, target calculator and local persistence.
- `OnboardingView.swift`: questionnaire and editable macro review.
- `DashboardView.swift`: calories, macro rings, diary categories and weight chart.
- `FoodSearchView.swift`: search, scanner entry point, portion editor and nutrition preview.
- `FoodLibraryViews.swift`: favourites, custom meal composer and quick logging.
- `OpenFoodFactsService.swift`, `BarcodeScannerView.swift`: remote food lookup and AVFoundation scanning.
- `MacroEngineApp.swift`: application root and onboarding gate.
