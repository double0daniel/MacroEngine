# MacroEngine: App icon and branding concept

## Concept

A three-segment ring with a bolt at its centre.

- **The ring** is the macro progress ring from the dashboard. Three arcs stand for protein, carbs and fat, with a small gap at 12 o'clock so it reads as a gauge rather than a loading spinner.
- **The bolt** is the "engine": energy in, energy out. It's the only white shape, so it's the focal point.
- **The ground** is the same slate as the app, so the icon and the first launch screen feel like one continuous object.

The icon is the one place the three macro colors appear together on a quiet slate field. Inside the app they're only used on icons, rings and bars, so the icon works as a preview of the whole system.

## Palette

| Role | Hex | Use |
|---|---|---|
| Slate top | `#2C313C` | Icon gradient, top |
| Slate bottom | `#16191F` | Icon gradient, bottom |
| App canvas | `#1B1E25` | In-app background, launch screen |
| Surface | `#252932` | Cards |
| Surface raised | `#2F3440` | Icon wells, chips, fields |
| Hairline | `#3B414E` | Borders, dividers |
| Text primary | `#F3F4F6` | Headings, numbers, the bolt |
| Text secondary | `#B8BEC9` | Labels, body |
| Text tertiary | `#8D94A3` | Captions only |
| Protein | `#4DA8FF` | Ring arc 1, protein icon and bar |
| Carbs | `#F2C94C` | Ring arc 2, carbs icon and bar |
| Fat | `#5FD6A4` | Ring arc 3, fat icon and bar |
| Calories | `#FF7A59` | Calorie ring and flame, in-app only |

## Geometry (1024 x 1024 canvas)

- Background: linear gradient `#2C313C` to `#16191F`, top to bottom. Full bleed, no rounded corners (iOS applies the mask).
- Ring: 640 px diameter, centred, 78 px stroke, round caps.
- Arcs: three arcs of 24% of the circumference each, starting at 4.7%, 38.0% and 71.3% (measured from 12 o'clock), which leaves a gap at the top.
- Bolt: 236 x 320 px, centred, `#F3F4F6`, with a 14 px round-joined stroke to soften the corners.
- Safe zone: everything sits inside roughly 70% of the canvas, so nothing clips under the squircle mask.

## SF Symbols: where to use them, and where not to

SF Symbols are great for the in-app macro icons and the tab or toolbar glyphs:

| Macro | Symbol |
|---|---|
| Calories | `flame.fill` |
| Protein | `dumbbell.fill` |
| Carbs | `bolt.fill` |
| Fat | `drop.fill` |
| Scan | `barcode.viewfinder` |

Apple's SF Symbols license doesn't allow using symbols in app icons or logos. That's why `AppIconArtwork.swift` draws the bolt as a custom `Path`. If you redraw the icon in Figma or Sketch, trace the bolt yourself rather than exporting `bolt.fill`.

Note that `bolt.fill` is also the in-app carbs symbol, so the icon's bolt and the carbs icon echo each other. If you'd rather keep the logo mark unique, swap the carbs symbol for `leaf.fill` or `carrot.fill` in `MacroKind.symbol`.

## Getting the icon into Xcode

1. In Xcode, open `AppIconArtwork.swift` and use the canvas preview to check the design.
2. Call `IconExporter.export()` once (for example from a temporary button or `.onAppear`) and run on the simulator. The console prints the path to two PNGs: standard and tinted.
3. Open `Assets.xcassets` and select `AppIcon`.
4. In the Attributes inspector, set Appearances to **Any, Dark, Tinted** (iOS 18+). On older Xcode versions, choose **Single Size**.
5. Drag `MacroEngine-AppIcon-1024.png` onto **Any Appearance** and **Dark**. Drag `MacroEngine-AppIcon-1024-tinted.png` onto **Tinted**.
6. In the target's **General** tab, under *App Icons and Launch Screen*, confirm the App Icon is `AppIcon`.
7. Remove the transparency check: the PNG is exported opaque, but if Xcode warns about alpha, re-export or flatten it in Preview (File > Export, uncheck Alpha).

## Other asset catalog entries

- **AccentColor**: `#F3F4F6`. Tints system controls (alerts, keyboard Done button, text cursor) near-white to match the monochrome UI.
- **Launch screen**: add a Color Set named `Slate` with `#1B1E25`, then in Info.plist set `UILaunchScreen` > `UIColorName` to `Slate`. The app opens straight into the slate canvas with no white flash.
- **Info.plist**: add `NSCameraUsageDescription` = "MacroEngine uses the camera to scan food barcodes."

## Wordmark

Set "MacroEngine" in SF Pro Semibold, one weight, one color (`#F3F4F6`), with slightly tight tracking (about -0.5 pt at 28 pt). No icon lockup is needed on the in-app screens: the bolt-and-ring mark is enough on marketing material and the App Store listing.
