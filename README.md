# Daybreak

A local Android weather app built for the Motorola Razr 2025. Flutter UI, native Kotlin home-screen widget, and Android WorkManager. No account, API keys, app backend, ads, or analytics.

## Install

Download **daybreak-android-arm64.apk** from the [latest GitHub release](https://github.com/jeethsuresh/weather/releases/latest) and install it on the phone. Android may ask you to allow installation from the browser or file manager you use. Open Daybreak, choose a city, then use **Settings → Add home-screen widget** (or long-press the launcher → Widgets → Daybreak).

GitHub releases are signed with a dedicated Daybreak release key. Every update keeps the same package ID and signing certificate. If you already installed the earlier locally provided APK signed with the development key, uninstall that version once before installing the GitHub release. Subsequent GitHub releases update in place.

## Weather sources

- **Canada:** [Environment and Climate Change Canada / MSC GeoMet](https://eccc-msc.github.io/open-data/), using the real-time City Page Weather JSON collection. The collection is experimental; automatic mode falls back if it fails. Nearby forecast cities are resolved on device and their identifiers cached. The selected forecast city is shown under the source.
- **US:** [NOAA National Weather Service](https://www.weather.gov/documentation/services-web-api), using `/points`, SI hourly and daily forecasts, and point-filtered active alerts. The app sends the required identifying User-Agent. The main temperature is the current hourly **forecast**, labelled accordingly.
- **Worldwide / fallback:** [Weather data by Open-Meteo](https://open-meteo.com/), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Its key-free endpoint is for non-commercial use. City search uses Open-Meteo’s geocoding service and [GeoNames](https://www.geonames.org/) data, also CC BY 4.0.

Automatic mode prefers the national service for Canadian and US cities, then Open-Meteo. Manual selection uses the chosen service and reports failure without silently changing sources. No missing measurement is presented as zero. ECCC’s wind chill is ignored outside its applicable temperature range. Official alerts depend on the national feed and are unavailable with Open-Meteo; the app does not send alert notifications.

## Local data and refresh

Settings and successful forecasts are persisted only in Android’s app storage. Forecasts are keyed by coordinates and source. The background isolate uses uncached preferences; switching cities clears old-city widget content immediately. Cache writes do not replace settings. Failed fetches preserve the last successful timestamp and forecast. Android cloud backup and device transfer are disabled for app data.

The phone contacts the weather services directly over HTTPS. Those services receive its IP address and requested coordinates; city search receives the search text. The app requests no GPS permission. Toronto is the initial city, and city selection works without location access.

WorkManager requests a network-connected check every hour and survives ordinary process death and reboot. Android Doze, battery restrictions, force-stop, and connectivity can delay execution. This is an hourly request, not an exact alarm. Opening the app catches up; pull to refresh forces a request. Turning off hourly checks cancels periodic work. Unit and source choices also apply to the widget.

The native widget reads one atomic saved payload, displays update age, marks stale data, advances through cached forecast hours, and opens Daybreak when tapped. Its hourly widget redraw only updates cached presentation; WorkManager fetches fresh weather. Neither the widget nor the app is an emergency warning system.

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

Tests cover real provider fixtures, source routing and fallback, missing data, unit conversion, active/expired alerts, source-specific offline caching, manual refresh, corrupt-cache recovery, unit-change refresh races, DST, city search, and layouts at 320/390/480dp with larger text. The optional live suite makes actual requests to all three weather services and geocoding. Test fixtures are public responses captured on October 18, 2026.

Source map: `lib/weather_api.dart` (requests/decoders), `lib/repository.dart` and `lib/storage.dart` (local persistence), `lib/background.dart` (periodic work/widget publishing), `lib/controller.dart` (foreground state), `lib/ui/weather_screen.dart` (screens), and `android/app/src/main/kotlin/dev/jeeth/local_weather/WeatherWidgetProvider.kt` (widget).

Only Android is configured in this project. No iOS widget or app target is included.

## GitHub releases and future updates

Repository: [jeethsuresh/weather](https://github.com/jeethsuresh/weather). Each release contains `daybreak-android-arm64.apk` and `SHA256SUMS`. Download the APK from the release assets on your phone. A GitHub login is required if the repository is private. The source stays on GitHub; the app still has no backend.

Run the local release command after committing a version bump:

```sh
python3 scripts/release.py
```

It analyzes, tests, builds and signs the APK on the local machine, pushes the `v` tag, then uploads the APK and checksums to GitHub Releases. The signing key stays on this Mac. Install GitHub CLI and authenticate with `gh auth login` if no existing GitHub credential is available; this Mac also has a local CLI copy in ignored `.tools/gh`.

For a new version, change `version` in `pubspec.yaml` (for example, `1.0.1+2`), increasing both the version name and build number, then commit and run the command. Do not reuse published version codes or modify published tags. Obtainium can later subscribe to the repository URL and use these same release assets.

Pushes to `main` and pull requests run `.github/workflows/ci.yml` for analysis and tests. Publishing a release runs `.github/workflows/release.yml`, which verifies the downloaded APK’s checksum, permanent signing certificate, package ID and release version. GitHub does not receive the private signing key or its passwords.

### Signing configuration

Local release builds read the untracked `android/key.properties` file; see `android/key.properties.example`. Release builds fail if signing is missing rather than using an unrelated development key. The dedicated keystore and local credentials are in the ignored `.signing/` directory on the original build machine. Back up that directory securely; do not commit it or add it to release assets. Debug builds do not require the release key.

The public certificate fingerprint is committed as `android/release-certificate.sha256`, so GitHub can verify published APKs without receiving the signing key. No signing secrets are configured in GitHub.
