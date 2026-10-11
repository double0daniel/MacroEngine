# MacroEngine — SwiftUI implementation

MacroEngine is a UK-oriented nutrition and meal-tracking app scaffold using SwiftUI, Observation, Swift Charts, AVFoundation and Open Food Facts. The source files follow the supplied Slate visual system and keep the original dashboard/search/scanner components in place.

## Included features

- **Onboarding:** age, sex used by the estimate, height (cm), weight (kg), activity level, cutting/bulking/maingain approach and an editable macro review.
- **Target estimates:** Mifflin–St Jeor BMR, activity multipliers, goal-based energy adjustments, and an initial protein/fat/carbohydrate split.
- **Dashboard:** calorie ring, segmented Protein/Carbs/Fat ring with spaced arcs, macro progress bars, rollover calorie banking, and separate Breakfast/Lunch/Dinner/Snacks logs.
- **Daily trackers:** workout journal with burned calories included in net totals, water goal and quick adds, and a daily supplement checklist.
- **Settings:** change cutting/bulking/maingain goals and activity level, recalculate TDEE, and set exact protein/carbohydrate/fat targets.
- **Food logging:** Open Food Facts name search and barcode lookup, clear-search action, gram text field + slider + stepper controls, and meal-category assignment.
- **Food library:** favourites and reusable custom meals composed from favourite foods.
- **Meal feedback:** optional 1–5 satiety and energy ratings on logged foods and custom meal logs, with averages shown on saved custom meals.
- **Recipe imports:** paste a recipe or public social link to read Recipe JSON-LD/Open Graph data, estimate ingredient macros with Open Food Facts, review per-serving values, and save the result as a custom meal. Pages that block reading fall back to an editable form.
- **Widgets:** MacroEngine progress, interactive quick hydration, and Lock Screen widgets share live data through the `group.com.macroengine.app` App Group.
- **Weight telemetry:** daily kg entries persisted locally and a Swift Charts line graph across the recorded history.
- **Persistence:** local JSON-encoded values in `UserDefaults`, with a migration fallback that treats older diary entries with no meal category as Snacks.
- **App icon:** `MacroEngine-Icon-Slate.png` is included in `Assets.xcassets/AppIcon.appiconset` and selected by the XcodeGen target settings.

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

## Build and install an IPA with GitHub Actions

The `Build iOS IPA` workflow builds an unsigned iPhone app on pushes to `main`, version tags (`v*`), or when started manually from the Actions tab. The Actions artifact points directly to `output/MacroEngine-unsigned.ipa`. GitHub packages workflow artifacts as ZIP downloads, so for a raw `.ipa` file, push a version tag (for example, `git tag v0.1.0` then `git push origin v0.1.0`); the workflow attaches the `.ipa` itself to that GitHub Release. No Apple signing certificate, provisioning profile or GitHub Actions secret is needed for the build.

The downloaded IPA must still be signed before iOS will install and run it. On Windows, install AltServer and AltStore using [AltStore's Windows guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows). Then hold **Shift** while clicking the AltServer tray icon, choose **Sideload .ipa…**, and select the downloaded IPA. AltServer signs it with your Apple ID and installs it to the connected iPhone. Keep AltServer installed; apps signed with a free Apple ID need refreshing every seven days. See [AltServer's sideloading notes](https://faq.altstore.io/release-notes/altserver).

After a successful workflow run, open it in the GitHub **Actions** tab and download the `MacroEngine-unsigned-IPA` artifact. Connect and unlock the iPhone, trust the computer if prompted, and make sure Developer Mode is enabled on iOS 16 or later. Your Apple ID is used by AltServer on your own computer; it is not sent to GitHub by this workflow.

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

- Open Food Facts is community-maintained; nutrition values, images, portion sizes and UK product tagging may be missing or inaccurate. Keyword search uses the UK endpoint first and falls back to the wider catalogue; barcode lookup uses the UK product endpoint. Search and barcode results show whether they came from the live UK/global API, a cached offline result, or no available response. Open Food Facts currently supports full-text search through its legacy keyword endpoint; API v2 search is filter-based.
- Diary logs, favourites, custom meals, profile, weight entries, workouts, water and supplement checks currently live on-device in `UserDefaults`. Widget snapshots and widget hydration actions use the shared `group.com.macroengine.app` suite. App Group access must be enabled for both targets in the signing profile used to install the app.
- No analytics, login, cloud sync or external subscription SDK is included.

## Source map

- `Theme.swift`, `Components.swift`, `AppIconArtwork.swift`: slate palette, shared UI primitives and brand artwork.
- `Models.swift`: Codable data, tracker persistence, rollover bank, meal ratings, the observable store and target calculator.
- `TrackerViews.swift`, `SettingsView.swift`: daily workout, hydration and supplement cards, plus TDEE and macro settings.
- `OnboardingView.swift`: questionnaire and editable macro review.
- `DashboardView.swift`: calories, macro rings, diary categories and weight chart.
- `FoodSearchView.swift`: search, scanner entry point, portion editor and nutrition preview.
- `FoodLibraryViews.swift`: favourites, custom meal composer and quick logging.
- `RecipeImporterService.swift`, `RecipeImportPreviewView.swift`: recipe metadata/caption parser, ingredient estimates and editable import preview.
- `OpenFoodFactsService.swift`, `BarcodeScannerView.swift`: remote food lookup and AVFoundation scanning.
- `WidgetExtension.swift`, `WidgetData.swift`, `WidgetDataManager.swift`: WidgetKit timelines, interactive hydration intent and App Group snapshots.
- `MacroEngineApp.swift`: application root and onboarding gate.
