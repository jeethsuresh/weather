package dev.jeeth.local_weather

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.File

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
        assertEquals("Wind +2", badge.label)
        assertEquals("red", badge.colour)
        assertEquals("Weather alerts: Wind Warning; Wind Watch; Wind Advisory", badge.description)
    }

    @Test fun officialColourIsPreservedAndRedrawsRemoveExpiredAlerts() {
        val alerts = JSONArray().put(alert("Warning", "yellow", now + 1))
            .put(alert("Advisory", "orange", null))
        assertEquals("orange", WidgetAdvisories.badge(alerts, now)!!.colour)
        assertEquals("Wind +1", WidgetAdvisories.badge(alerts, now)!!.label)
        assertEquals("Wind", WidgetAdvisories.badge(alerts, now + 1)!!.label)
    }

    @Test fun malformedEntriesAreIgnoredAndUnknownCategoriesUseANeutralPill() {
        val alerts = JSONArray().put(12).put(JSONObject()).put(alert("Statement", "unknown", null))
        val badge = WidgetAdvisories.badge(alerts, now)!!
        assertEquals("Wind", badge.label)
        assertEquals("blue", badge.colour)
    }

    @Test fun everyOfficialNwsEventUsesItsSubjectInsteadOfTheVerboseHeadline() {
        val entries = JSONObject(File("../../test/fixtures/alert_events.json").readText()).getJSONArray("nws")
        for (i in 0 until entries.length()) {
            val entry = entries.getJSONObject(i)
            val event = entry.getString("event")
            val alert = JSONObject().put("event", event)
                .put("title", "$event issued October 26 at 3PM until Tuesday for several counties")
                .put("colour", "yellow")
            assertEquals(event, entry.getString("hazard"),
                WidgetAdvisories.badge(JSONArray().put(alert), now)!!.label)
        }
    }

    @Test fun canadaColourPrefixesAndLegacySnapshotsNameEveryHazard() {
        val hazards = JSONObject(File("../../test/fixtures/alert_events.json").readText()).getJSONArray("canadaHazards")
        for (i in 0 until hazards.length()) {
            val hazard = hazards.getString(i)
            for (type in listOf("warning", "watch", "advisory")) {
                for (colour in listOf("yellow", "orange", "red")) {
                    val title = "${colour.uppercase()} ${type.uppercase()} - ${hazard.uppercase()}"
                    for (event in listOf("", type)) {
                        assertEquals(title, if (hazard == "Weather") "" else hazard,
                            WidgetAdvisories.hazard(event, title))
                    }
                }
            }
        }
        assertEquals("Frost", WidgetAdvisories.hazard("advisory", " YELLOW ADVISORY – FROST "))
        assertEquals("Air quality", WidgetAdvisories.hazard("statement", "Special Air Quality Statement"))
        assertEquals("New hazard", WidgetAdvisories.hazard("warning", "RED WARNING - NEW HAZARD"))
        assertEquals("", WidgetAdvisories.hazard("advisory", "YELLOW ADVISORY"))
    }
}
