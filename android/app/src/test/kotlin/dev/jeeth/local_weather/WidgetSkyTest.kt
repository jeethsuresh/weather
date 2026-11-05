package dev.jeeth.local_weather

import android.appwidget.AppWidgetManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.view.View
import android.widget.ImageView
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.time.Instant
import java.util.Calendar
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], qualifiers = "mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WidgetSkyTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val now = Instant.parse("2026-11-05T17:00:00Z").toEpochMilli()
    private fun data() = JSONObject().put("latitude",43.6532).put("longitude",-79.3832)
        .put("timeZone","America/Toronto").put("kind","sun")

    @Test fun solarTimesAndPolarDayNightWorkWithoutNetworkOrProviderFields() {
        val data = data()
        val sun = WidgetSky.sun(data, now)
        val local = Calendar.getInstance(TimeZone.getTimeZone("America/Toronto"))
        local.timeInMillis = sun.rise!!
        assertEquals(5,local.get(Calendar.DAY_OF_MONTH)); assertTrue(local.get(Calendar.HOUR_OF_DAY)*60 + local.get(Calendar.MINUTE) in 414..426)
        local.timeInMillis = sun.set!!
        assertEquals(17,local.get(Calendar.HOUR_OF_DAY))
        assertFalse(sun.night(now))
        assertTrue(sun.night(Instant.parse("2026-11-06T03:00:00Z").toEpochMilli()))
        val supplied = now + 7200000
        data.put("sunset",supplied)
        assertEquals(supplied,WidgetSky.sun(data,now).set)
        assertNotEquals(supplied,WidgetSky.sun(data,now+86400000).set)
        data.put("latitude",69.65).put("longitude",18.96).put("timeZone","Europe/Oslo")
        val summer = Instant.parse("2026-06-21T12:00:00Z").toEpochMilli()
        val winter = Instant.parse("2026-12-21T12:00:00Z").toEpochMilli()
        assertNull(WidgetSky.sun(data,summer).rise)
        assertFalse(WidgetSky.sun(data,summer).night(summer))
        assertTrue(WidgetSky.sun(data,winter).night(winter))
        assertEquals("New moon",WidgetSky.phaseName(WidgetSky.phase(947182440000L)))
    }
    @Test fun nativeRedrawDropsExpiredEdgesAndKeepsAllActiveHazards() {
        val alerts = JSONArray().put(JSONObject().put("title","Frost advisory"))
            .put(JSONObject().put("event","High Wind Warning").put("expires",now+1))
            .put(JSONObject().put("title","Severe thunderstorm watch"))
        assertEquals(setOf("frost","wind","thunder"),WidgetSky.hazards(alerts,now))
        assertEquals(setOf("frost","thunder"),WidgetSky.hazards(alerts,now+1))
        assertTrue(WidgetSky.hazards(JSONArray(),now).isEmpty())
        assertNotEquals(WidgetSky.color("sun",false),WidgetSky.color("cloud",false))
        assertNotEquals(WidgetSky.color("cloud",false),WidgetSky.color("rain",false))
        assertNotEquals(WidgetSky.color("sun",false),WidgetSky.color("sun",true))
    }
    @Test fun everyProviderRendersSkyMoonAndWarningsThenClearsExpiredArtwork() {
        val manager = AppWidgetManager.getInstance(context)
        val shadow = shadowOf(manager)
        val previews = File("../../build/previews").apply { mkdirs() }
        for ((provider,layout,width,height) in listOf(
            Quad(TemperatureWidgetProvider(),R.layout.weather_widget_temperature,100,100),
            Quad(SummaryWidgetProvider(),R.layout.weather_widget_summary,220,100),
            Quad(WeatherWidgetProvider(),R.layout.weather_widget,220,220),
        )) {
            val id = shadow.createWidget(provider.javaClass,layout)
            val preferences = context.getSharedPreferences("sky-$layout",Context.MODE_PRIVATE)
            val current = System.currentTimeMillis()
            val alert = JSONObject().put("title","Frost and wind advisory with thunderstorms")
                .put("colour","yellow").put("expires",current+3600000)
            val data = data().put("place","Toronto").put("temperature","12°").put("unit","C")
                .put("summary","Clear sky").put("fetchedAt",current).put("observedAt",current)
                .put("sunrise",current-7200000).put("sunset",current-3600000)
                .put("alerts",JSONArray().put(alert))
            fun update(): View {
                preferences.edit().putString("weather",data.toString()).commit()
                provider.onUpdate(context,manager,intArrayOf(id),preferences)
                return shadow.getViewFor(id)
            }
            val view = update()
            assertTrue(view.contentDescription.toString().contains("Frost and wind"))
            assertTrue(view.contentDescription.toString().contains("approximate moon phase"))
            assertEquals("12°",view.findViewById<TextView>(R.id.temperature).text.toString())
            if(layout == R.layout.weather_widget) assertTrue(view.findViewById<TextView>(R.id.sky_details).text.toString().contains("↑"))
            val background = (view.findViewById<ImageView>(R.id.sky_background).drawable as BitmapDrawable).bitmap.copy(Bitmap.Config.ARGB_8888,false)
            view.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(height,View.MeasureSpec.EXACTLY))
            view.layout(0,0,width,height)
            val bitmap = Bitmap.createBitmap(width*3,height*3,Bitmap.Config.ARGB_8888)
            view.draw(Canvas(bitmap).apply { scale(3f,3f) })
            File(previews,"sky-widget-$width-$height.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }
            alert.put("expires",current-1)
            val updated = update()
            val clean = (updated.findViewById<ImageView>(R.id.sky_background).drawable as BitmapDrawable).bitmap
            assertFalse(background.sameAs(clean))
            assertFalse(updated.contentDescription.toString().contains("Frost and wind"))
        }
    }
    private data class Quad(val provider: CachedWeatherWidget,val layout: Int,val width: Int,val height: Int)
}
