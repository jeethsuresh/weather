# Daybreak

A local Android weather app built for the Motorola Razr 2025. Flutter UI, native Kotlin home-screen widget, and Android WorkManager. No account, API keys, app backend, ads, or analytics.

## Install

Download **daybreak-android-arm64.apk** from the [latest GitHub release](https://github.com/jeethsuresh/weather/releases/latest) and install it on the phone. Android may ask you to allow installation from the browser or file manager you use. Open Daybreak, choose a city, then use **Settings → Home-screen widgets** (or long-press the launcher → Widgets → Daybreak).

GitHub releases are signed with a dedicated Daybreak release key. Every update keeps the same package ID and signing certificate. If you already installed the earlier locally provided APK signed with the development key, uninstall that version once before installing the GitHub release. Subsequent GitHub releases update in place.

## Razr cover screen

Short app windows (600 logical pixels tall or less) automatically use a compact, vertically scrolling card layout. Opening the phone returns to the full forecast. There is no portrait lock. The compact layout honors Android's reported camera-cutout and navigation safe insets.

Both the main and cover layouts show a compact, horizontally scrolling strip of connected hourly cells, including the time, conditions icon, temperature and precipitation chance. The main temperature graph always spans the next 24 hours, including across midnight and daylight-saving changes. The time axis stays fixed even when hourly coverage is incomplete. The current card always uses the highest and lowest available temperatures on its 24-hour graph for its high and low. Tap the current-conditions card to flip it to the same 24-hour precipitation-chance graph, wind, humidity and feels-like temperature. Plots use saved hourly data with gaps preserved. The daily forecast is one connected list of thin rows, showing the weekday, calendar date, weather icon and summary, high and low; it has no daily graph cards or flip controls. Missing readings display “—”, and cached data from older versions remains readable. The current card's face survives scrolling and folding, and reduced-motion settings disable its flip animation.

The compact interface is validated at square/short window sizes, simulated camera insets, larger text, and an open/close resize transition. Motorola's exact camera cutouts and external-panel behavior still need a check on the physical Razr. This changes the app UI; the Android home-screen widget remains a separate surface.

## Weather sources

- **Canada:** [Environment and Climate Change Canada / MSC GeoMet](https://eccc-msc.github.io/open-data/), using the real-time City Page Weather JSON collection. The collection is experimental; automatic mode falls back if it fails. Nearby forecast cities are resolved on device and their identifiers cached. The selected forecast city is shown under the source.
- **US:** [NOAA National Weather Service](https://www.weather.gov/documentation/services-web-api), using `/points`, SI hourly and daily forecasts, and point-filtered active alerts. The app sends the required identifying User-Agent. The main temperature is the current hourly **forecast**, labelled accordingly.
- **Worldwide / fallback:** [Weather data by Open-Meteo](https://open-meteo.com/), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Its key-free endpoint is for non-commercial use. City search uses Open-Meteo’s geocoding service and [GeoNames](https://www.geonames.org/) data, also CC BY 4.0.

Automatic mode prefers the national service for Canadian and US cities, then Open-Meteo. Manual selection uses the chosen service and reports failure without silently changing sources. No missing measurement is presented as zero. ECCC’s wind chill is ignored outside its applicable temperature range. Official alerts depend on the national feed and are unavailable with Open-Meteo; the app does not send alert notifications.

## Local data and refresh

Settings and successful forecasts are persisted only in Android’s app storage. Forecasts are keyed by coordinates and source. The background isolate uses uncached preferences; switching cities clears old-city widget content immediately. Cache writes do not replace settings. Failed fetches preserve the last successful timestamp and forecast. Android cloud backup and device transfer are disabled for app data.

The phone contacts the weather services directly over HTTPS. Those services receive its IP address and requested coordinates; city search receives the search text. Open-Meteo also receives coordinates for the timezone lookup, and Android’s geocoder resolves the area name. Toronto is the initial city. **Use current location** in the city picker or settings requests Android foreground location permission and a fresh position fix. Approximate location is accepted if that is what the user shares; its reported accuracy is shown in the picker. The app stores the coordinates locally, resolves the area name through Android’s geocoder, and resolves the timezone through Open-Meteo. It rechecks location when the app resumes if current-location mode is selected. Hourly background weather uses the last saved coordinates and never requests background location. Denying permission, disabling location services or timing out keeps the saved area unchanged; manual city selection always remains available.

WorkManager requests a network-connected check every hour and survives ordinary process death and reboot. Android Doze, battery restrictions, force-stop, and connectivity can delay execution. This is an hourly request, not an exact alarm. Opening the app catches up; pull to refresh forces a request. Turning off hourly checks cancels periodic work. Unit and source choices also apply to the widget.

Three fixed-size native widgets are available: **1×1** (temperature and icon), **2×1** (temperature, icon and conditions), and **2×2** (the 12-hour graph’s high above the current temperature and low below it, filling the left column vertically, weather icon with a small 12-hour temperature graph beneath it, conditions, wind speed and precipitation chance for the nearest forecast hour). There is no 4×2 option. Launcher cell dimensions vary by device. All sizes read one atomic saved payload and open Daybreak when tapped. The graph uses cached hourly temperatures and labels its start/end hours; gaps stay gaps and expired hours drop out. The 2×2 widget always uses the highest and lowest available temperatures on its 12-hour graph, recalculated from unexpired hours on native redraws. Its high and low can differ from the app’s 24-hour values; this is expected. Highs and lows without hourly data and unavailable hourly trends remain labelled as unavailable. The 2×2 names the precipitation hour and shows update age; small widgets turn the temperature amber when weather is stale. Missing readings display “—”; expired precipitation hours are never shown as current. Hourly native redraws advance the cached precipitation hour; WorkManager fetches fresh weather. Existing installations keep their original widget, now using the 2×2 content; remove and re-add it to reclaim the old launcher space. Neither the widget nor the app is an emergency warning system.

## Develop

The tested toolchain is Flutter `3.32.0-0.2.pre` / Dart `3.8.0-278.1.beta`, JDK 17+, Android API 36, Android NDK `27.0.12077973`. Minimum Android version is 7.0 (API 24). Dependencies are locked in `pubspec.lock`; dynamic AndroidX dependencies from `home_widget` are pinned to stable compatible versions in `android/build.gradle.kts`.

```sh
flutter --no-version-check pub get
flutter --no-version-check analyze
flutter --no-version-check test --reporter expanded
flutter --no-version-check test test/live_weather_test.dart --dart-define=LIVE_WEATHER=true --reporter expanded
flutter --no-version-check run
flutter --no-version-check build apk --release --target-platform android-arm64
```

`--no-version-check` avoids a hanging online SDK update check on this Mac. It does not disable dependency verification.

Tests cover real provider fixtures, source routing and fallback, missing data, unit conversion, active/expired alerts, source-specific offline caching, manual refresh, corrupt-cache recovery, unit-change refresh races, DST, city search, and layouts at 320/390/480dp with larger text. Widget tests cover metric/imperial snapshots, missing versus zero readings, expired hours, clearing a location, publishing all three providers, and rejecting an old location/unit refresh. Additional tests cover compact square/short windows, simulated camera insets, independent flip state while scrolling, reduced motion, open/close resizing, keyboard-constrained city search, GPS permission denial, approximate fixes, stale-location rejection and picker dismissal during a pending fix. The optional live suite makes actual requests to all three weather services and geocoding. Test fixtures are public responses captured on October 18, 2026.

Source map: `lib/weather_api.dart` (requests/decoders), `lib/repository.dart` and `lib/storage.dart` (local persistence), `lib/background.dart` (periodic work/widget publishing), `lib/controller.dart` (foreground state), `lib/location.dart` (foreground position and permission flow), `lib/ui/weather_screen.dart` (full forecast and sheets), `lib/ui/compact_weather.dart` (cover-screen cards), and `android/app/src/main/kotlin/dev/jeeth/local_weather/WeatherWidgetProvider.kt` (widget).

Only Android is configured in this project. No iOS widget or app target is included.

## GitHub releases and future updates

Repository: [jeethsuresh/weather](https://github.com/jeethsuresh/weather). Each release contains `daybreak-android-arm64.apk` and `SHA256SUMS`. Download the APK from the release assets on your phone. A GitHub login is required if the repository is private. The source stays on GitHub; the app still has no backend.

Increase both the version name and build number in `pubspec.yaml`, then push or merge to `main`. GitHub's **Signed Android release** workflow automatically tests, signs with the permanent Daybreak key, verifies the APK and publishes the new version. The signing credentials are stored in the main-only `android-release` GitHub environment. Any machine with repository access can submit the version bump.

See [signed Android releases](ANDROID_RELEASES.md) for verification-only builds, secret maintenance and the release manifest. The protected original key remains the backup. Debug builds do not require it.

### Signing configuration

Local release builds read the untracked `android/key.properties` file; see `android/key.properties.example`. Release builds fail if signing is missing rather than using an unrelated development key. The dedicated keystore and local credentials are in the ignored `.signing/` directory on the original build machine. Back up that directory securely; do not commit it or add it to release assets. Debug builds do not require the release key.

The public certificate fingerprint is committed as `android/release-certificate.sha256`, so every build can verify the permanent certificate. GitHub signing uses encrypted `android-release` environment secrets restricted to `main`; the original protected local key remains the backup.
