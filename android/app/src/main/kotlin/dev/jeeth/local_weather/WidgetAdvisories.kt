package dev.jeeth.local_weather

import android.appwidget.AppWidgetManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.RemoteViews
import android.widget.TextView
import org.json.JSONArray
import java.util.Locale
import kotlin.math.ceil

internal data class AdvisoryBadge(val label: String, val colour: String, val description: String)

internal object WidgetAdvisories {
    private val priority = mapOf("blue" to 0, "yellow" to 1, "orange" to 2, "red" to 3)
    private val generic = setOf("", "weather", "special weather", "severe weather", "hazardous weather",
        "marine weather", "special marine", "short term", "hydrologic", "administrative", "test", "warning", "watch", "advisory", "alert",
        "statement", "message", "outlook", "forecast")

    /** No allowlist: preserve new provider hazards instead of silently dropping them. */
    internal fun hazard(event: String, title: String): String {
        fun subject(value: String): String {
            when (value.trim().lowercase(Locale.ROOT)) {
                "blue alert" -> return "Officer safety"
                "red flag warning" -> return "Fire danger"
                "special air quality statement", "special air quality advisory" -> return "Air quality"
            }
            val clean = value.replace(Regex("\\s+"), " ").trim().lowercase(Locale.ROOT)
                .replace(Regex("^(?:(?:yellow|orange|red) +)?(?:weather +)?(?:warning|watch|advisory|alert) *[-–—:] *"), "")
                .replace(Regex(" +(?:warning|watch|advisory|alert|statement|message|outlook|forecast)$"), "")
            if (clean == "special air quality") return "Air quality"
            return if (clean in generic || clean in setOf("yellow", "orange", "red")) ""
                else clean.replaceFirstChar { it.titlecase(Locale.ROOT) }
        }
        val categoryOnly = event.trim().lowercase(Locale.ROOT) in setOf(
            "", "warning", "watch", "advisory", "alert", "statement", "message")
        return subject(if (categoryOnly) title else event)
    }

    /** Measure the real font/padding, including Android's font scaling, before sharing the row. */
    internal fun pillWidth(context: Context, badge: AdvisoryBadge, place: String): Float {
        val root = LayoutInflater.from(context).inflate(R.layout.weather_widget, null)
        val location = root.findViewById<TextView>(R.id.place)
        val pill = root.findViewById<TextView>(R.id.advisory_pill)
        val margins = pill.layoutParams as ViewGroup.MarginLayoutParams
        val pixels = root.paddingLeft + root.paddingRight +
            ceil(location.paint.measureText(place)) + location.compoundPaddingLeft + location.compoundPaddingRight +
            ceil(pill.paint.measureText(badge.label)) + pill.compoundPaddingLeft + pill.compoundPaddingRight +
            margins.marginStart + margins.marginEnd
        // Round up and leave a small margin for launcher/text measurement rounding.
        return ceil(pixels / context.resources.displayMetrics.density) + 2f
    }

    fun render(context: Context, views: RemoteViews, badge: AdvisoryBadge?, place: String,
               options: Bundle): RemoteViews {
        val minimum = if (badge == null || badge.label.isEmpty()) Float.POSITIVE_INFINITY
            else pillWidth(context, badge, place)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && minimum.isFinite()) {
            // The launcher picks for its actual size, including rotation/foldable changes.
            return RemoteViews(mapOf(
                SizeF(0f, 0f) to renderWidth(views.clone(), badge, 0f, minimum),
                SizeF(minimum, 0f) to renderWidth(views.clone(), badge, minimum, minimum),
            ))
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && minimum.isFinite()) {
            val portrait = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH).toFloat()
            val landscape = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH).toFloat()
            return RemoteViews(renderWidth(views.clone(), badge, landscape, minimum),
                renderWidth(views.clone(), badge, portrait, minimum))
        }
        return renderWidth(views, badge, 0f, minimum)
    }

    internal fun renderWidth(views: RemoteViews, badge: AdvisoryBadge?, width: Float,
                             minimum: Float): RemoteViews {
        val pill = badge != null && badge.label.isNotEmpty() && width >= minimum
        views.setViewVisibility(R.id.advisory_pill, if (pill) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.advisory_dot, if (badge != null && !pill) View.VISIBLE else View.GONE)
        if (badge == null) return views
        val background = when (badge.colour) {
            "red" -> R.drawable.widget_advisory_red
            "orange" -> R.drawable.widget_advisory_orange
            "yellow" -> R.drawable.widget_advisory_yellow
            else -> R.drawable.widget_advisory_blue
        }
        views.setTextViewText(R.id.advisory_pill, badge.label)
        views.setInt(R.id.advisory_pill, "setBackgroundResource", background)
        // Rounded pill shapes become circles in the square dot bounds.
        views.setInt(R.id.advisory_dot, "setBackgroundResource", background)
        views.setContentDescription(R.id.advisory_pill, badge.description)
        views.setContentDescription(R.id.advisory_dot, badge.description)
        return views
    }

    fun badge(alerts: JSONArray?, now: Long): AdvisoryBadge? {
        val active = (0 until (alerts?.length() ?: 0)).mapNotNull { alerts?.optJSONObject(it) }
            .filter { alert ->
                alert.optString("title").isNotBlank() &&
                    (alert.isNull("expires") || alert.optLong("expires") > now)
            }
            .sortedByDescending { priority[it.optString("colour")] ?: 0 }
        val first = active.firstOrNull() ?: return null
        // Old snapshots lack event; normalize their title too, including ECCC's colour prefix.
        val label = hazard(first.optString("event"), first.optString("title"))
        val colour = first.optString("colour").takeIf { it in priority } ?: "blue"
        return AdvisoryBadge(
            if (label.isEmpty()) "" else label + if (active.size > 1) " +${active.size - 1}" else "",
            colour,
            "Weather alerts: " + active.joinToString("; ") { it.optString("title") },
        )
    }
}
