package dev.jeeth.local_weather

import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

internal data class AdvisoryBadge(val label: String, val colour: String, val description: String)

internal object WidgetAdvisories {
    private val priority = mapOf("blue" to 0, "yellow" to 1, "orange" to 2, "red" to 3)

    fun render(views: RemoteViews, badge: AdvisoryBadge?) {
        views.setViewVisibility(R.id.advisory_pill, if (badge == null) View.GONE else View.VISIBLE)
        if (badge == null) return
        views.setTextViewText(R.id.advisory_pill, badge.label)
        views.setInt(R.id.advisory_pill, "setBackgroundResource", when (badge.colour) {
            "red" -> R.drawable.widget_advisory_red
            "orange" -> R.drawable.widget_advisory_orange
            "yellow" -> R.drawable.widget_advisory_yellow
            else -> R.drawable.widget_advisory_blue
        })
        views.setContentDescription(R.id.advisory_pill, badge.description)
    }

    fun badge(alerts: JSONArray?, now: Long): AdvisoryBadge? {
        val active = (0 until (alerts?.length() ?: 0)).mapNotNull { alerts?.optJSONObject(it) }
            .filter { alert ->
                alert.optString("title").isNotBlank() &&
                    (alert.isNull("expires") || alert.optLong("expires") > now)
            }
            .sortedByDescending { priority[it.optString("colour")] ?: 0 }
        val first = active.firstOrNull() ?: return null
        val label = first.optString("label").takeIf { it in setOf("Warning", "Watch", "Advisory") } ?: "Alert"
        val colour = first.optString("colour").takeIf { it in priority } ?: "blue"
        return AdvisoryBadge(
            label + if (active.size > 1) " +${active.size - 1}" else "",
            colour,
            "Weather alerts: " + active.joinToString("; ") { it.optString("title") },
        )
    }
}
