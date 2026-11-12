import SwiftUI
import WidgetKit

private struct WeatherEntry: TimelineEntry {
    let date: Date
    let snapshot: WeatherSnapshot?
}

private struct WeatherProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        let date = Date()
        return WeatherEntry(date: date, snapshot: .sample(at: date))
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        let date = Date()
        completion(WeatherEntry(date: date, snapshot: context.isPreview ? .sample(at: date) : .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        let now = Date()
        guard let snapshot = WeatherSnapshot.load(), snapshot.fetched != nil else {
            completion(Timeline(entries: [WeatherEntry(date: now, snapshot: nil)], policy: .never))
            return
        }
        let horizon = now.addingTimeInterval(86_400)
        let dates = snapshot.hours.flatMap {
            [$0.date.addingTimeInterval(-43_200), $0.date.addingTimeInterval(-5_400),
             $0.date.addingTimeInterval(1_800)]
        } + snapshot.staleDates + snapshot.sunTimes + snapshot.alerts.compactMap(\.expiry)
        let boundaries = Set(dates.filter { $0 > now && $0 < horizon }).sorted()
        completion(Timeline(entries: ([now] + boundaries).map {
            WeatherEntry(date: $0, snapshot: snapshot)
        }, policy: .after(horizon)))
    }
}

private struct WeatherView: View {
    let entry: WeatherEntry
    @Environment(\.widgetFamily) private var family

    private let secondary = Color(red: 0.78, green: 0.87, blue: 0.95)
    private let warm = Color(red: 1, green: 0.80, blue: 0.56)

    private var sky: LinearGradient {
        let night = entry.snapshot?.isNight(at: entry.date) ?? false
        let storm = ["rain", "storm", "snow", "fog"].contains(entry.snapshot?.kind ?? "")
        return LinearGradient(
            colors: night
                ? [Color(red: 0.13, green: 0.29, blue: 0.50), Color(red: 0.04, green: 0.12, blue: 0.26)]
                : [Color(red: 0.15, green: storm ? 0.32 : 0.44, blue: 0.65),
                   Color(red: 0.06, green: 0.22, blue: 0.39)],
            startPoint: .topTrailing, endPoint: .bottomLeading
        )
    }

    var body: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(for: .widget) { sky }
        } else {
            content.padding(14).background(sky)
        }
    }

    private var content: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.fetched != nil {
                switch family {
                case .systemLarge:
                    details(snapshot)
                case .systemMedium:
                    summary(snapshot)
                default:
                    temperatureOnly(snapshot)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "cloud.sun").font(.title2)
                    Text("Daybreak").font(.headline)
                    Text("Open Daybreak to load your forecast.")
                        .font(.footnote).foregroundStyle(secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.white)
    }

    private func symbol(_ snapshot: WeatherSnapshot) -> String {
        let night = snapshot.isNight(at: entry.date)
        switch snapshot.kind {
        case "sun": return night ? moonSymbol(snapshot) : "sun.max.fill"
        case "partly": return night ? "cloud.moon.fill" : "cloud.sun.fill"
        case "cloud": return "cloud.fill"
        case "rain": return "cloud.rain.fill"
        case "storm": return "cloud.bolt.rain.fill"
        case "snow": return "cloud.snow.fill"
        case "fog": return "cloud.fog.fill"
        default: return "cloud"
        }
    }

    private func moonSymbol(_ snapshot: WeatherSnapshot) -> String {
        let cycle = 29.530588853
        let reference = 947_182_440.0
        let elapsed = (entry.date.timeIntervalSince1970 - reference) / 86_400
        let phase = Int(((elapsed / cycle - floor(elapsed / cycle)) * 8).rounded()) % 8
        let symbols = ["moonphase.new.moon", "moonphase.waxing.crescent", "moonphase.first.quarter",
                       "moonphase.waxing.gibbous", "moonphase.full.moon", "moonphase.waning.gibbous",
                       "moonphase.last.quarter", "moonphase.waning.crescent"]
        return symbols[(snapshot.latitude ?? 0) < 0 ? (8 - phase) % 8 : phase]
    }

    private func temperature(_ snapshot: WeatherSnapshot, size: CGFloat) -> some View {
        Text(snapshot.temperature)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(snapshot.stale(at: entry.date) ? warm : .white)
            .accessibilityLabel("\(snapshot.temperature) \(snapshot.unit)")
    }

    private func icon(_ snapshot: WeatherSnapshot, size: CGFloat) -> some View {
        Image(systemName: symbol(snapshot))
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size))
            .foregroundStyle(warm)
            .accessibilityLabel(snapshot.summary)
    }

    private func temperatureOnly(_ snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(snapshot.place).font(.caption.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 0)
            icon(snapshot, size: 25)
            temperature(snapshot, size: 39)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func summary(_ snapshot: WeatherSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.place).font(.caption.weight(.semibold)).lineLimit(1)
                temperature(snapshot, size: 42)
                Text(snapshot.summary).font(.subheadline).lineLimit(2)
                    .foregroundStyle(secondary)
            }
            Spacer(minLength: 10)
            icon(snapshot, size: 43).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func details(_ snapshot: WeatherSnapshot) -> some View {
        let hours = snapshot.trend(at: entry.date)
        let precip = snapshot.precipitation(at: entry.date)
        let alerts = snapshot.advisories(at: entry.date)
        let high = hours.max { $0.temperature < $1.temperature }?.temperatureText ?? "—"
        let low = hours.min { $0.temperature < $1.temperature }?.temperatureText ?? "—"
        let stale = snapshot.stale(at: entry.date)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(snapshot.place).font(.headline).lineLimit(2).layoutPriority(1)
                Spacer(minLength: 5)
                if let alert = alerts.first {
                    advisory(alert, alerts: alerts)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    temperature(snapshot, size: 46)
                    Text(snapshot.summary).font(.subheadline).lineLimit(2).foregroundStyle(secondary)
                }
                Spacer()
                icon(snapshot, size: 41).accessibilityHidden(true)
            }
            if let sun = sunLine(snapshot) {
                Text(sun).font(.caption2).foregroundStyle(secondary)
            }
            Spacer(minLength: 0)
            HStack {
                Text("Next 12 hours").font(.caption.weight(.semibold))
                Spacer()
                Text("High \(high)  Low \(low)").font(.caption2).foregroundStyle(secondary)
            }
            if let first = hours.first, let last = hours.last, hours.count > 1 {
                ForecastGraph(hours: hours, unit: snapshot.unit, tint: warm)
                    .frame(minHeight: 26, idealHeight: 48, maxHeight: 56)
                    .accessibilityLabel("Hourly temperature, \(first.temperatureText) at \(first.time) to \(last.temperatureText) at \(last.time)")
                HStack {
                    Text(first.time)
                    Spacer()
                    Text(last.time)
                }
                .font(.caption2).foregroundStyle(secondary)
            } else {
                Text("No hourly data").font(.caption).foregroundStyle(secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 18) {
                metric("Wind", snapshot.wind)
                metric(precip.map { "Precip · \($0.time)" } ?? "Precip · next hr", precip?.rain ?? "—")
            }
            if let fetched = snapshot.fetched {
                let elapsed = Text(fetched, style: .relative)
                Group {
                    if stale {
                        Text("Saved · \(elapsed) ago")
                    } else {
                        Text("Updated \(elapsed) ago")
                    }
                }
                .font(.caption2).foregroundStyle(stale ? warm : secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func advisory(_ alert: WeatherSnapshot.Alert, alerts: [WeatherSnapshot.Alert]) -> some View {
        let color: Color = ["red": .red, "orange": .orange, "yellow": .yellow][alert.colour] ?? .blue
        let additional = alerts.count > 1 ? " +\(alerts.count - 1)" : ""
        return Label(alert.name + additional, systemImage: "exclamationmark.triangle.fill")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(color.opacity(0.35), in: Capsule())
            .accessibilityLabel(alerts.map(\.title).joined(separator: "; "))
    }

    private func sunLine(_ snapshot: WeatherSnapshot) -> String? {
        guard let solar = snapshot.solarDay(at: entry.date) else { return nil }
        guard let sunrise = solar.sunrise, let sunset = solar.sunset else {
            return solar.polarDay ? "Midnight sun" : "Polar night"
        }
        let formatter = DateFormatter()
        formatter.timeZone = snapshot.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        formatter.timeStyle = .short
        let rise = formatter.string(from: Date(timeIntervalSince1970: sunrise / 1_000))
        let set = formatter.string(from: Date(timeIntervalSince1970: sunset / 1_000))
        return "Sunrise \(rise)  ·  Sunset \(set)"
    }

    private func metric(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption2).foregroundStyle(secondary)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ForecastGraph: View {
    let hours: [WeatherSnapshot.Hour]
    let unit: String
    let tint: Color

    var body: some View {
        Canvas { context, size in
            guard let first = hours.first, let last = hours.last,
                  let low = hours.map(\.temperature).min(), let high = hours.map(\.temperature).max() else { return }
            let timeSpan = max(1, last.timestamp - first.timestamp)
            let temperatureSpan = max(unit == "F" ? 7.2 : 4, high - low)
            let midpoint = (high + low) / 2
            func point(_ hour: WeatherSnapshot.Hour) -> CGPoint {
                CGPoint(x: 3 + (size.width - 6) * (hour.timestamp - first.timestamp) / timeSpan,
                        y: 3 + (size.height - 6) * (0.5 - (hour.temperature - midpoint) / temperatureSpan))
            }
            var line = Path()
            var previous: WeatherSnapshot.Hour?
            for hour in hours {
                let p = point(hour)
                if let previous, hour.timestamp - previous.timestamp <= 5_400_000 {
                    line.addLine(to: p)
                } else {
                    line.move(to: p)
                }
                context.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)),
                             with: .color(tint))
                previous = hour
            }
            context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

@main
struct DaybreakWeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DaybreakWeather", provider: WeatherProvider()) {
            WeatherView(entry: $0).widgetURL(URL(string: "daybreak://weather"))
        }
            .configurationDisplayName("Daybreak Weather")
            .description("See the temperature, conditions, or the 12-hour forecast and weather alerts.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
