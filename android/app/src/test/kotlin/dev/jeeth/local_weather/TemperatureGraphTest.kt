package dev.jeeth.local_weather

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class TemperatureGraphTest {
    private val now = 1792366200000L // 2026-10-18 23:30 UTC, crosses local midnight.

    private fun hour(offset: Long, value: Double, text: String) = JSONObject()
        .put("timestamp", now + offset)
        .put("temperature", value)
        .put("temperatureText", text)
        .put("time", "hour $offset")

    @Test fun extremesUseOnlyThePlottedTwelveHours() {
        val hours = JSONArray()
            .put(hour(13 * 3600000L, 40.0, "40°"))
            .put(hour(-1800000L, -40.0, "-40°"))
            .put(hour(12 * 3600000L, 0.0, "0°"))
            .put(hour(3600000L, -5.0, "-5°"))
            .put(hour(3 * 3600000L, -2.0, "-2°"))
            .put(JSONObject().put("timestamp", now + 7200000)) // missing reading
        val points = TemperatureGraph.points(hours, now)
        assertEquals(listOf(-5.0, -2.0, 0.0), points.map { it.value })
        assertEquals("0°", TemperatureGraph.high(points))
        assertEquals("-5°", TemperatureGraph.low(points))

        // Native redraws advance the range from the same saved snapshot.
        val later = TemperatureGraph.points(hours, now + 4 * 3600000L)
        assertEquals("40°", TemperatureGraph.high(later))
        assertEquals("0°", TemperatureGraph.low(later))
    }

    @Test fun labelsComeFromTheExtremePointsInEitherUnit() {
        for (fahrenheit in listOf(false, true)) {
            val points = listOf(-5.0, -2.0, -8.0).mapIndexed { i, value ->
                val plotted = if (fahrenheit) value * 9 / 5 + 32 else value
                TemperaturePoint(i.toLong(), plotted, "hour $i", "${Math.round(plotted)}°")
            }
            assertEquals(if (fahrenheit) "28°" else "-2°", TemperatureGraph.high(points))
            assertEquals(if (fahrenheit) "18°" else "-8°", TemperatureGraph.low(points))
        }
    }

    @Test fun missingFlatAndSinglePointGraphsHaveMatchingExtremes() {
        assertEquals("—", TemperatureGraph.high(TemperatureGraph.points(null, now)))
        assertEquals("—", TemperatureGraph.low(TemperatureGraph.points(JSONArray(), now)))
        val point = TemperaturePoint(now, 0.0, "now", "0°")
        for (points in listOf(listOf(point), listOf(point, point.copy(time = now + 3600000)))) {
            assertEquals("0°", TemperatureGraph.high(points))
            assertEquals("0°", TemperatureGraph.low(points))
        }
    }
}
