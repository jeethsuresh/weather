package dev.jeeth.local_weather

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WidgetAdvisoriesTest {
    private val now = 1792366200000L
    private fun alert(label: String, colour: String, expiry: Long? = now + 3600000) = JSONObject()
        .put("title", "Wind $label")
        .put("label", label)
        .put("colour", colour)
        .put("expires", expiry ?: JSONObject.NULL)

    @Test fun noActiveAlertsHideThePillIncludingOnOlderSnapshots() {
        assertNull(WidgetAdvisories.badge(null, now))
        assertNull(WidgetAdvisories.badge(JSONArray(), now))
        assertNull(WidgetAdvisories.badge(JSONArray().put(alert("Warning", "red", now)), now))
    }

    @Test fun highestColourWinsAndOtherAlertsAreCountedAndAccessible() {
        val badge = WidgetAdvisories.badge(JSONArray()
            .put(alert("Advisory", "yellow"))
            .put(alert("Watch", "orange"))
            .put(alert("Warning", "red")), now)!!
        assertEquals("Warning +2", badge.label)
        assertEquals("red", badge.colour)
        assertEquals("Weather alerts: Wind Warning; Wind Watch; Wind Advisory", badge.description)
    }

    @Test fun officialColourIsPreservedAndRedrawsRemoveExpiredAlerts() {
        val alerts = JSONArray().put(alert("Warning", "yellow", now + 1))
            .put(alert("Advisory", "orange", null))
        assertEquals("orange", WidgetAdvisories.badge(alerts, now)!!.colour)
        assertEquals("Advisory +1", WidgetAdvisories.badge(alerts, now)!!.label)
        assertEquals("Advisory", WidgetAdvisories.badge(alerts, now + 1)!!.label)
    }

    @Test fun malformedEntriesAreIgnoredAndUnknownCategoriesUseANeutralPill() {
        val alerts = JSONArray().put(12).put(JSONObject()).put(alert("Statement", "unknown", null))
        val badge = WidgetAdvisories.badge(alerts, now)!!
        assertEquals("Alert", badge.label)
        assertEquals("blue", badge.colour)
    }
}
