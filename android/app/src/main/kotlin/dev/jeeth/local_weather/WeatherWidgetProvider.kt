package dev.jeeth.local_weather

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.graphics.Color
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/** Renders only the last saved forecast. Network refreshes run in WorkManager. */
class WeatherWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray,
                          widgetData: SharedPreferences) {
        val data = try { JSONObject(widgetData.getString("weather", "{}") ?: "{}") }
                   catch (_: Exception) { JSONObject() }
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.weather_widget)
            views.setTextViewText(R.id.place, data.optString("place", "Daybreak"))
            views.setTextViewText(R.id.temperature, data.optString("temperature", "—"))
            views.setTextViewText(R.id.condition, data.optString("summary", "Open Daybreak to get a forecast"))
            views.setTextViewText(R.id.feels_like, data.optString("feelsLike", ""))
            views.setTextViewText(R.id.weather_symbol, symbol(data.optString("kind")))
            views.setTextViewText(R.id.source, data.optString("source", "Daybreak"))
            val fetchedAt = data.optLong("fetchedAt", 0)
            val observedAt = data.optLong("observedAt", 0)
            val minutes = ((System.currentTimeMillis() - fetchedAt) / 60000).coerceAtLeast(0)
            val stale = minutes >= 120 || (observedAt > 0 && System.currentTimeMillis() - observedAt > 10800000)
            val age = when {
                fetchedAt == 0L -> "Tap to set up"
                minutes < 1 -> "Updated now"
                minutes < 60 -> "Updated ${minutes}m ago"
                minutes < 1440 -> "${minutes / 60}h old"
                else -> "${minutes / 1440}d old"
            }
            views.setTextViewText(R.id.updated, if (stale) "Saved · $age" else age)
            views.setTextColor(R.id.updated, Color.parseColor(if (stale) "#FFD29C" else "#AAC5B9"))
            val hourIds = intArrayOf(R.id.hour_1, R.id.hour_2, R.id.hour_3, R.id.hour_4)
            val hours = data.optJSONArray("hours")
            val upcoming = (0 until (hours?.length() ?: 0)).mapNotNull { hours?.optJSONObject(it) }
                .filter { it.optLong("timestamp") > System.currentTimeMillis() - 1800000 }
                .take(4)
            for (i in hourIds.indices) {
                val hour = upcoming.getOrNull(i)
                // Do not leave expired forecast hours looking current after a long offline period.
                views.setTextViewText(hourIds[i], if (hour == null || minutes > 1440) "—"
                    else "${hour.optString("time")}  ${hour.optString("temperature")}")
            }
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

    private fun symbol(kind: String) = when (kind) {
        "sun" -> "☀"
        "partly", "cloud" -> "☁"
        "snow" -> "❄"
        "rain", "storm" -> "☂"
        "fog" -> "≋"
        else -> "°"
    }
}
