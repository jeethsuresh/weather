package dev.jeeth.local_weather

import android.appwidget.AppWidgetManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.os.Bundle
import android.util.SizeF
import org.robolectric.util.ReflectionHelpers
import org.robolectric.util.ReflectionHelpers.ClassParameter
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
        WidgetAdvisories.renderWidth(remote, badge, width.toFloat(),
            if (badge == null || badge.label.isEmpty()) Float.POSITIVE_INFINITY
            else WidgetAdvisories.pillWidth(context, badge, place))
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

    @Test fun locationHasPriorityAtRealTwoCellWidthsAndBodyDoesNotMove() {
        for (width in listOf(110, 130, 140, 160, 180, 240)) {
            for (place in listOf("York", "Yellowknife", "A very long location name that must truncate")) {
                for (label in listOf("Frost", "Severe thunderstorm +2", "")) {
                    val badge = AdvisoryBadge(label, "yellow", "YELLOW ADVISORY - FROST")
                    val empty = widget(width, null, place)
                    val shown = widget(width, badge, place)
                    val location = shown.findViewById<TextView>(R.id.place)
                    val pill = shown.findViewById<TextView>(R.id.advisory_pill)
                    val dot = shown.findViewById<View>(R.id.advisory_dot)
                    val fits = label.isNotEmpty() && width >= WidgetAdvisories.pillWidth(context, badge, place)
                    val indicator = if (fits) R.id.advisory_pill else R.id.advisory_dot
                    assertEquals(place, location.text.toString())
                    assertEquals(if (fits) View.VISIBLE else View.GONE, pill.visibility)
                    assertEquals(if (fits) View.GONE else View.VISIBLE, dot.visibility)
                    assertTrue(bounds(shown, R.id.place).right < bounds(shown, indicator).left)
                    assertTrue(bounds(shown, indicator).right <= width - shown.paddingRight)
                    val locationFitsAlone = location.paint.measureText(place) <= width - 34
                    if (fits || locationFitsAlone) {
                        assertEquals("The alert must never truncate a location that fits", 0,
                            location.layout.getEllipsisCount(0))
                    } else {
                        assertEquals("Long locations get all space except the dot and gap",
                            width - 34, location.width)
                    }
                    if (fits) assertTrue(pill.paint.measureText(label) <= pill.width - pill.paddingLeft - pill.paddingRight)
                    assertEquals(badge.description, shown.findViewById<View>(indicator).contentDescription)
                    for (id in listOf(R.id.temperature, R.id.daily_high, R.id.daily_low,
                        R.id.weather_icon, R.id.temperature_graph, R.id.condition, R.id.wind,
                        R.id.precipitation, R.id.updated)) {
                        assertEquals("Other widget content must stay in place", bounds(empty, id), bounds(shown, id))
                    }
                }
            }
        }
    }

    @Test @Config(fontScale = 1.5f)
    fun largeFontsAlsoGiveTheLocationPriority() {
        val view = widget(130, AdvisoryBadge("Frost", "yellow", "Frost advisory"), "Yellowknife")
        assertEquals(View.GONE, view.findViewById<View>(R.id.advisory_pill).visibility)
        assertEquals(View.VISIBLE, view.findViewById<View>(R.id.advisory_dot).visibility)
        assertEquals("Yellowknife", view.findViewById<TextView>(R.id.place).text.toString())
        assertEquals(0, view.findViewById<TextView>(R.id.place).layout.getEllipsisCount(0))
    }

    @Test @Config(sdk = [31])
    fun android12LauncherChoosesPillOrDotForTheActualWidth() {
        val badge = AdvisoryBadge("Frost", "yellow", "YELLOW ADVISORY - FROST")
        val remote = RemoteViews(context.packageName, R.layout.weather_widget)
        remote.setTextViewText(R.id.place, "Yellowknife")
        val rendered = WidgetAdvisories.render(context, remote, badge, "Yellowknife", Bundle())
        for ((width, visible) in listOf(110f to View.GONE, 240f to View.VISIBLE)) {
            val selected = ReflectionHelpers.callInstanceMethod<RemoteViews>(rendered, "getRemoteViewsToApply",
                ClassParameter.from(Context::class.java, context),
                ClassParameter.from(SizeF::class.java, SizeF(width, 200f)))
            val view = selected.apply(context, null)
            assertEquals(visible, view.findViewById<View>(R.id.advisory_pill).visibility)
        }
    }

    @Test fun providerRendersGraphExtremesAndActiveAlertsFromTheSavedSnapshot() {
        val manager = AppWidgetManager.getInstance(context)
        val shadow = shadowOf(manager)
        val id = shadow.createWidget(WeatherWidgetProvider::class.java, R.layout.weather_widget)
        manager.updateAppWidgetOptions(id, Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 240)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 240)
        })
        val preferences = context.getSharedPreferences("widget-test", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val alert = JSONObject().put("title", "Wind warning").put("label", "Warning")
            .put("colour", "red").put("expires", now + 3600000)
        val data = JSONObject().put("place", "New York City").put("temperature", "16°")
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
        assertEquals("Wind", view.findViewById<TextView>(R.id.advisory_pill).text.toString())
        assertEquals(View.VISIBLE, view.findViewById<View>(R.id.advisory_pill).visibility)
        manager.updateAppWidgetOptions(id, Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 110)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 110)
        })
        update()
        assertEquals(View.VISIBLE, shadow.getViewFor(id).findViewById<View>(R.id.advisory_dot).visibility)
        assertTrue(view.contentDescription.toString().contains("Wind warning"))
        alert.put("expires", now - 1)
        update()
        assertEquals(View.GONE, shadow.getViewFor(id).findViewById<View>(R.id.advisory_pill).visibility)
        assertEquals(View.GONE, shadow.getViewFor(id).findViewById<View>(R.id.advisory_dot).visibility)
    }

    @Test fun previewsAndReapplyClearAnExpiredPill() {
        val directory = File("../../build/previews").apply { mkdirs() }
        for ((colour, label) in listOf("red" to "Wind", "orange" to "Snow", "yellow" to "Frost", "blue" to "Air quality")) {
          for (width in listOf(110, 130, 240)) {
            val view = widget(width, AdvisoryBadge(label, colour, label), "Yellowknife")
            val height = maxOf(180, width)
            view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
            view.layout(0, 0, width, height)
            val bitmap = Bitmap.createBitmap(width * 3, height * 3, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap).apply { scale(3f, 3f) }
            view.draw(canvas)
            File(directory, "widget-$width-$colour.png").outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
            val remote = RemoteViews(context.packageName, R.layout.weather_widget)
            WidgetAdvisories.renderWidth(remote, null, 0f, Float.POSITIVE_INFINITY)
            remote.reapply(context, view)
            assertEquals(View.GONE, view.findViewById<View>(R.id.advisory_pill).visibility)
            assertEquals(View.GONE, view.findViewById<View>(R.id.advisory_dot).visibility)
          }
        }
    }
}
