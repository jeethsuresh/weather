# Widget alert labels

The location has priority in the detailed widget header. A pill appears only
when the full location and hazard label fit together. Otherwise the alert is an
8dp coloured dot; the location gets the remaining row. Very long locations can
still ellipsize within that space. The body layout is unchanged. Both indicators
retain all active alert titles for accessibility, and tapping opens Daybreak.

## Provider data

- **Environment and Climate Change Canada:** City Page Weather supplies
  `description`, `type` and `alertColourLevel`. The current description format is
  `YELLOW ADVISORY - FROST`, so the displayed subject is `Frost`, with the supplied
  yellow colour. The colour and warning/watch/advisory category are not the
  subject. This also works for older descriptions such as `Wind warning`.
  Current hazard families include cold, frost, heat, tropical weather, ice, rain,
  snow, snow squalls, thunderstorms, tornadoes, visibility, wind, winter storms
  and coastal flooding/storm surge; air-quality statements are also supported.
- **US National Weather Service:** use `properties.event`, not `headline` (which
  can contain issue times, expiry times and counties). Remove the category suffix
  to retain subjects such as `Frost`, `Air quality`, `Flash flood`, `Rip current`
  and `Severe thunderstorm`. Non-weather events retain their subject too. `Red
  Flag Warning` becomes `Fire danger`; `Blue Alert` becomes `Officer safety`.
  The app's existing red-warning/orange-watch/yellow-advisory/blue-other palette
  applies; it is not the NWS map's event-specific palette.
- **Open-Meteo:** the forecast API has no official warning/watch/advisory field.
  Its forecasts do not create alert pills or infer official alerts from weather
  codes. This applies when Open-Meteo is selected or used as a fallback.

Generic statements without a supplied hazard use a dot, rather than inventing a
subject from forecast conditions or printing `Advisory`/`Special weather`.
Unfamiliar hazards pass through without needing an allowlist. Multiple alerts
keep the highest-priority colour and append a count when the label fits.

Android 12+ selects between dot and pill layouts using the actual widget width.
Older Android versions use the launcher's portrait/landscape width options;
unknown widths default to a dot. The fit threshold measures the real location
and pill fonts, padding and system font scale. Cached alerts from older app
versions also pass through subject extraction on native redraws.

## Sources and regression data

Checked 2026-10-26 against primary provider documentation:

- [ECCC City Page Weather](https://eccc-msc.github.io/open-data/msc-data/citypage-weather/readme_citypageweather_en/)
- [ECCC description/colour format change](https://comm.collab.science.gc.ca/mailman3/hyperkitty/list/dd_info%40comm.collab.science.gc.ca/thread/WD6KUIDXQHEHTTMVYZI2HTQMZYBV4DBH/)
- [ECCC hazard impact guides](https://www.canada.ca/en/services/environment/weather/severeweather/weather-alerts/weather-impact-guides.html)
- [ECCC air-quality statements](https://www.canada.ca/en/environment-climate-change/services/air-quality-health-index/wildfire-smoke.html/1000)
- [NWS alert service](https://www.weather.gov/documentation/services-web-alerts) and [all 111 current event types](https://api.weather.gov/alerts/types)
- [NWS non-weather event definitions](https://www.weather.gov/media/directives/010_pdfs/pd01005018curr.pdf)
- [Open-Meteo forecast API fields](https://open-meteo.com/en/docs)
- [Android responsive widget layouts](https://developer.android.com/develop/ui/views/appwidgets/layouts)

`test/fixtures/alert_events.json` snapshots all 111 NWS names and representative
current/legacy Canadian hazards. Tests cover provider parsing through the widget
payload, native subjects, official Canadian colours, expiry, cached titles,
110–240dp layouts, long locations, font scaling and Android 12 size selection.
