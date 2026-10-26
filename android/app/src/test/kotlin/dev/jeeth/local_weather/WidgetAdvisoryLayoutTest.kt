package dev.jeeth.local_weather

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.view.View
import android.widget.RemoteViews
import android.widget.TextView
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
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
        val location = IntArray(2)
        view.getLocationOnScreen(location)
        return Rect(location[0], location[1], location[0] + view.width, location[1] + view.height)
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

    @Test fun previewsAndReapplyClearAnExpiredPill() {
        val directory = File("../build/previews").apply { mkdirs() }
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
