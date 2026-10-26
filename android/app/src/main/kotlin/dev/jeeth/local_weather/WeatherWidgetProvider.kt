package dev.jeeth.local_weather

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.os.Bundle
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

// Keep the original receiver name so installed widgets survive an app update.
class WeatherWidgetProvider : CachedWeatherWidget(R.layout.weather_widget, true)
class TemperatureWidgetProvider : CachedWeatherWidget(R.layout.weather_widget_temperature)
class SummaryWidgetProvider : CachedWeatherWidget(R.layout.weather_widget_summary)

/** Every size reads the same local snapshot. Only WorkManager fetches weather. */
abstract class CachedWeatherWidget(
    private val layout: Int,
    private val details: Boolean = false,
) : HomeWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray,
                          widgetData: SharedPreferences) {
        val data = try { JSONObject(widgetData.getString("weather", "{}") ?: "{}") }
                   catch (_: Exception) { JSONObject() }
        val now = System.currentTimeMillis()
        val fetchedAt = data.optLong("fetchedAt", 0)
        val observedAt = data.optLong("observedAt", 0)
        val minutes = ((now - fetchedAt) / 60000).coerceAtLeast(0)
        val stale = fetchedAt > 0 && (minutes >= 120 ||
            (observedAt > 0 && now - observedAt > 10800000))
        val age = when {
            fetchedAt == 0L -> "Tap to set up"
            minutes < 1 -> "Updated now"
            minutes < 60 -> "Updated ${minutes}m ago"
            minutes < 1440 -> "${minutes / 60}h old"
            else -> "${minutes / 1440}d old"
        }
        val temperature = data.optString("temperature", "—")
        val summary = data.optString("summary", "Tap to set up")
        val hours = data.optJSONArray("hours")
        // Advance the next-hour chance during native redraws, even when offline.
        // Never substitute a distant hour or a missing probability with zero.
        val nextHour = (0 until (hours?.length() ?: 0))
            .mapNotNull { hours?.optJSONObject(it) }
            .filter { it.optLong("timestamp") > now - 1800000 &&
                it.optLong("timestamp") <= now + 5400000 }
            .minByOrNull { it.optLong("timestamp") }
        val rain = if (nextHour == null || nextHour.isNull("rain")) "—"
                   else nextHour.optString("rain", "—")
        val rainLabel = if (nextHour == null) "Precip · next hr"
                        else "Precip · ${nextHour.optString("time")}"
        val trend = if (details) TemperatureGraph.points(hours, now) else emptyList()
        val high = TemperatureGraph.high(trend)
        val low = TemperatureGraph.low(trend)
        val graph = if (details) TemperatureGraph.draw(trend, stale, data.optString("unit") == "F") else null
        val advisory = WidgetAdvisories.badge(data.optJSONArray("alerts"), now)
        val graphTime = if (trend.size < 2) "No hourly data"
                        else "${trend.first().label}–${trend.last().label}"
        for (id in ids) {
            val views = RemoteViews(context.packageName, layout)
            views.setTextViewText(R.id.temperature, temperature)
            views.setTextColor(R.id.temperature, Color.parseColor(if (stale) "#FFD29C" else "#FFFFFF"))
            views.setImageViewResource(R.id.weather_icon, icon(data.optString("kind")))
            if (layout != R.layout.weather_widget_temperature) {
                views.setTextViewText(R.id.condition, summary)
            }
            if (details) {
                views.setTextViewText(R.id.daily_high, "High $high")
                views.setTextViewText(R.id.daily_low, "Low $low")
                views.setImageViewBitmap(R.id.temperature_graph, graph)
                views.setTextViewText(R.id.graph_time, graphTime)
                views.setTextViewText(R.id.place, data.optString("place", "Daybreak"))
                WidgetAdvisories.render(views, advisory)
                views.setTextViewText(R.id.wind, data.optString("wind", "—"))
                views.setTextViewText(R.id.precipitation, rain)
                views.setTextViewText(R.id.precipitation_label, rainLabel)
                views.setTextViewText(R.id.updated, if (stale) "Saved · $age" else age)
                views.setTextColor(R.id.updated, Color.parseColor(if (stale) "#FFD29C" else "#AAC5B9"))
            }
            val description = buildString {
                append("${data.optString("place", "Daybreak")}, ${temperature.removeSuffix("°")} degrees ${data.optString("unit")}, $summary. ")
                if (details) {
                    append("Next 12 hours: high $high, low $low. ")
                    if (advisory != null) append("${advisory.description}. ")
                    if (trend.size >= 2) append("Hourly temperature trend: ${trend.first().temperature} at ${trend.first().label} to ${trend.last().temperature} at ${trend.last().label}. ")
                }
                if (details) append("Wind ${data.optString("wind", "not reported")}. $rainLabel, $rain chance. ")
                append(if (stale) "Saved weather. $age. " else "$age. ")
                append("${data.optString("source", "Daybreak")}. Tap to open Daybreak.")
            }
            views.setContentDescription(R.id.widget_root, description)
            val launch = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val click = PendingIntent.getActivity(context, id, launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_root, click)
            manager.updateAppWidget(id, views)
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager,
                                           id: Int, newOptions: Bundle) {
        super.onAppWidgetOptionsChanged(context, manager, id, newOptions)
        onUpdate(context, manager, intArrayOf(id))
    }

    private fun icon(kind: String) = when (kind) {
        "sun" -> R.drawable.widget_sun
        "partly" -> R.drawable.widget_partly
        "cloud" -> R.drawable.widget_cloud
        "rain" -> R.drawable.widget_rain
        "storm" -> R.drawable.widget_storm
        "snow" -> R.drawable.widget_snow
        "fog" -> R.drawable.widget_fog
        else -> R.drawable.widget_unknown
    }
}
