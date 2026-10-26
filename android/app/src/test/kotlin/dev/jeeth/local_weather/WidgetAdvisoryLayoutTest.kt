package dev.jeeth.local_weather

import android.appwidget.AppWidgetManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.view.View
import android.view.ViewGroup
import android.widget.RemoteViews
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], qualifiers = "mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WidgetAdvisoryLayoutTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()

    private fun widget(width: Int, badge: AdvisoryBadge?, place: String = "Toronto"): View {
        val remote = RemoteViews(context.packageName, R.layout.weather_widget)
        remote.setTextViewText(R.id.place, place)
        WidgetAdvisories.render(remote, badge)
        remote.setImageViewBitmap(R.id.temperature_graph, TemperatureGraph.draw(
            listOf(17.0, 15.0, 16.0, 10.0, 5.0).mapIndexed { i, temperature ->
                TemperaturePoint(i * 3600000L, temperature, "hour $i", "$temperature°")
            }, false, false))
        val view = remote.apply(context, null)
        view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY))
        view.layout(0, 0, width, width)
        return view
    }

    private fun bounds(root: View, id: Int): Rect {
        val view = root.findViewById<View>(id)
        return Rect(0, 0, view.width, view.height).also {
            (root as ViewGroup).offsetDescendantRectToMyCoords(view, it)
        }
    }

    @Test fun pillFitsBesideLongLocationsWithoutMovingTheRestOfTheLayout() {
        for (width in listOf(180, 240)) {
            val empty = widget(width, null)
            val shown = widget(width, AdvisoryBadge("Warning +2", "red", "Wind warning"),
                "A very long location name that must truncate")
            assertEquals(View.GONE, empty.findViewById<View>(R.id.advisory_pill).visibility)
            val pill = shown.findViewById<TextView>(R.id.advisory_pill)
            assertEquals(View.VISIBLE, pill.visibility)
            assertEquals("Warning +2", pill.text.toString())
            assertEquals("Wind warning", pill.contentDescription)
            assertTrue(bounds(shown, R.id.place).right < bounds(shown, R.id.advisory_pill).left)
            assertTrue(bounds(shown, R.id.advisory_pill).right <= width - shown.paddingRight)
            for (id in listOf(R.id.temperature, R.id.daily_high, R.id.daily_low,
                R.id.weather_icon, R.id.temperature_graph, R.id.condition, R.id.wind,
                R.id.precipitation, R.id.updated)) {
                assertEquals("Other widget content must stay in place", bounds(empty, id), bounds(shown, id))
            }
        }
    }

    @Test fun providerRendersGraphExtremesAndActiveAlertsFromTheSavedSnapshot() {
        val manager = AppWidgetManager.getInstance(context)
        val shadow = shadowOf(manager)
        val id = shadow.createWidget(WeatherWidgetProvider::class.java, R.layout.weather_widget)
        val preferences = context.getSharedPreferences("widget-test", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val alert = JSONObject().put("title", "Wind warning").put("label", "Warning")
            .put("colour", "red").put("expires", now + 3600000)
        val data = JSONObject().put("place", "Toronto").put("temperature", "16°")
            .put("unit", "C").put("fetchedAt", now).put("observedAt", now)
            .put("alerts", JSONArray().put(alert))
            .put("days", JSONArray().put(JSONObject().put("high", "40°").put("low", "-40°")))
            .put("hours", JSONArray().apply {
                for ((offset, temperature) in listOf(1 to -5, 3 to -2, 13 to 40)) {
                    put(JSONObject().put("timestamp", now + offset * 3600000L)
                        .put("temperature", temperature).put("temperatureText", "$temperature°")
                        .put("time", "hour $offset"))
                }
            })
        fun update() {
            preferences.edit().putString("weather", data.toString()).commit()
            WeatherWidgetProvider().onUpdate(context, manager, intArrayOf(id), preferences)
        }
        update()
        val view = shadow.getViewFor(id)
        assertEquals("High -2°", view.findViewById<TextView>(R.id.daily_high).text.toString())
        assertEquals("Low -5°", view.findViewById<TextView>(R.id.daily_low).text.toString())
        assertEquals("Warning", view.findViewById<TextView>(R.id.advisory_pill).text.toString())
        assertTrue(view.contentDescription.toString().contains("Wind warning"))
        alert.put("expires", now - 1)
        update()
        assertEquals(View.GONE, shadow.getViewFor(id).findViewById<View>(R.id.advisory_pill).visibility)
    }

    @Test fun previewsAndReapplyClearAnExpiredPill() {
        val directory = File("../../build/previews").apply { mkdirs() }
        for ((colour, label) in listOf("red" to "Warning", "orange" to "Watch",
            "yellow" to "Advisory", "blue" to "Alert")) {
            val view = widget(240, AdvisoryBadge(label, colour, "Wind $label"))
            val bitmap = Bitmap.createBitmap(480, 480, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap).apply { scale(2f, 2f) }
            view.draw(canvas)
            File(directory, "widget-$colour.png").outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
            val remote = RemoteViews(context.packageName, R.layout.weather_widget)
            WidgetAdvisories.render(remote, null)
            remote.reapply(context, view)
            assertEquals(View.GONE, view.findViewById<View>(R.id.advisory_pill).visibility)
        }
    }
}
