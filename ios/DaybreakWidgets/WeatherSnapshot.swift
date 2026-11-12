import Foundation

struct WeatherSnapshot: Decodable {
    struct SolarDay: Decodable {
        let date: Double
        let sunrise: Double?
        let sunset: Double?
        let polarDay: Bool

        var boundaries: [Date] {
            [date, sunrise, sunset].compactMap { $0.map { Date(timeIntervalSince1970: $0 / 1_000) } }
        }
    }

    struct Hour: Decodable {
        let timestamp: Double
        let time: String
        let temperature: Double
        let temperatureText: String
        let rain: String?

        var date: Date { Date(timeIntervalSince1970: timestamp / 1_000) }
    }

    struct Alert: Decodable {
        let title: String
        let event: String
        let colour: String
        let expires: Double?

        var expiry: Date? { expires.map { Date(timeIntervalSince1970: $0 / 1_000) } }
        var priority: Int { ["red": 3, "orange": 2, "yellow": 1][colour] ?? 0 }
        var name: String {
            let category = event.trimmingCharacters(in: .whitespacesAndNewlines)
            let generic = ["", "warning", "watch", "advisory", "alert", "statement", "message"]
            return generic.contains(category.lowercased()) ? title : category
        }
    }

    let place: String
    let timeZone: String?
    let latitude: Double?
    let solarDays: [SolarDay]?
    let unit: String
    let temperature: String
    let summary: String
    let wind: String
    let fetchedAt: Double
    let observedAt: Double
    let hours: [Hour]
    let alerts: [Alert]
    let kind: String

    static func load() -> WeatherSnapshot? {
        guard let data = UserDefaults(suiteName: "group.dev.jeeth.daybreak")?
            .string(forKey: "weather")?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    static func sample(at date: Date) -> Self {
        let sampleHours = [18, 19, 21, 22, 21, 20, 18].enumerated().map { index, value in
            let hour = date.addingTimeInterval(Double(index) * 3_600)
            let formatter = DateFormatter()
            formatter.dateFormat = "ha"
            return Hour(timestamp: hour.timeIntervalSince1970 * 1_000,
                        time: formatter.string(from: hour).lowercased(),
                        temperature: Double(value), temperatureText: "\(value)°", rain: "20%")
        }
        return Self(place: "Toronto", timeZone: "America/Toronto", latitude: 43.65,
                    solarDays: nil, unit: "C", temperature: "18°",
                    summary: "Partly cloudy", wind: "14 km/h",
                    fetchedAt: date.timeIntervalSince1970 * 1_000,
                    observedAt: date.timeIntervalSince1970 * 1_000,
                    hours: sampleHours, alerts: [], kind: "partly")
    }

    var fetched: Date? { fetchedAt > 0 ? Date(timeIntervalSince1970: fetchedAt / 1_000) : nil }
    var sunTimes: [Date] { solarDays?.flatMap(\.boundaries) ?? [] }

    private var locationCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        return calendar
    }

    func solarDay(at date: Date) -> SolarDay? {
        let calendar = locationCalendar
        return solarDays?.first {
            calendar.isDate(date, inSameDayAs: Date(timeIntervalSince1970: $0.date / 1_000))
        }
    }

    var staleDates: [Date] {
        [fetched?.addingTimeInterval(7_200),
         observedAt > 0 ? Date(timeIntervalSince1970: observedAt / 1_000 + 10_800) : nil].compactMap { $0 }
    }

    func stale(at date: Date) -> Bool {
        fetched != nil && staleDates.contains { $0 <= date }
    }

    func isNight(at date: Date) -> Bool {
        if let solar = solarDay(at: date) {
            guard let sunrise = solar.sunrise, let sunset = solar.sunset else { return !solar.polarDay }
            let seconds = date.timeIntervalSince1970 * 1_000
            return seconds < sunrise || seconds >= sunset
        }
        return !(6..<18).contains(locationCalendar.component(.hour, from: date))
    }

    func trend(at date: Date) -> [Hour] {
        var seen = Set<Double>()
        return Array(hours.sorted { $0.timestamp < $1.timestamp }.filter {
            $0.date > date.addingTimeInterval(-1_800) &&
            $0.date <= date.addingTimeInterval(43_200) &&
            seen.insert($0.timestamp).inserted
        }.prefix(13))
    }

    func precipitation(at date: Date) -> Hour? {
        hours.filter { $0.date > date.addingTimeInterval(-1_800) && $0.date <= date.addingTimeInterval(5_400) }
            .min { $0.timestamp < $1.timestamp }
    }

    func advisories(at date: Date) -> [Alert] {
        alerts.filter { !$0.title.isEmpty && ($0.expiry ?? .distantFuture) > date }
            .sorted { $0.priority > $1.priority }
    }
}
