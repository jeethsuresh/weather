package dev.jeeth.local_weather

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.math.*

/** Offline sky calculation. Mirrors lib/sky.dart; cached provider events win today. */
object WidgetSky {
    data class Sun(val rise: Long?, val set: Long?, val polarDay: Boolean = false) {
        fun night(now: Long) = if (rise == null || set == null) !polarDay else now < rise || now >= set
    }
    fun sun(data: JSONObject, now: Long): Sun {
        val zone = TimeZone.getTimeZone(data.optString("timeZone", "UTC"))
        val local = Calendar.getInstance(zone).apply { timeInMillis = now }
        val date = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear(); set(local.get(Calendar.YEAR), local.get(Calendar.MONTH), local.get(Calendar.DAY_OF_MONTH))
        }
        // Legacy snapshots have no coordinates: retain reported times, and avoid inventing a location.
        if (!data.has("latitude") || !data.has("longitude")) {
            return Sun(data.optLong("sunrise").takeIf { it > 0 }, data.optLong("sunset").takeIf { it > 0 }, true)
        }
        val gamma = 2 * PI / local.getActualMaximum(Calendar.DAY_OF_YEAR) * (local.get(Calendar.DAY_OF_YEAR) - 1)
        val eq = 229.18 * (.000075 + .001868*cos(gamma) - .032077*sin(gamma) - .014615*cos(2*gamma) - .040849*sin(2*gamma))
        val decl = .006918 - .399912*cos(gamma) + .070257*sin(gamma) - .006758*cos(2*gamma) + .000907*sin(2*gamma) - .002697*cos(3*gamma) + .00148*sin(3*gamma)
        val lat = Math.toRadians(data.optDouble("latitude"))
        val cosHour = cos(Math.toRadians(90.833)) / (cos(lat)*cos(decl)) - tan(lat)*tan(decl)
        if (!cosHour.isFinite() || abs(cosHour) > 1) return Sun(null, null, cosHour < -1)
        val hour = Math.toDegrees(acos(cosHour))
        fun event(key: String, angle: Double): Long {
            val supplied = data.optLong(key)
            val candidate = Calendar.getInstance(zone).apply { timeInMillis = supplied }
            if (supplied > 0 && candidate.get(Calendar.YEAR) == local.get(Calendar.YEAR) &&
                candidate.get(Calendar.DAY_OF_YEAR) == local.get(Calendar.DAY_OF_YEAR)) return supplied
            var estimate = date.timeInMillis + ((720 - 4*(data.optDouble("longitude") + angle) - eq)*60000).roundToLong()
            candidate.timeInMillis = estimate
            // UTC+/-14 and the date line can put a UTC event on an adjacent local day.
            val targetDate = date.timeInMillis
            val actualDate = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
                clear(); set(candidate.get(Calendar.YEAR), candidate.get(Calendar.MONTH), candidate.get(Calendar.DAY_OF_MONTH))
            }.timeInMillis
            estimate += targetDate - actualDate
            return estimate
        }
        return Sun(event("sunrise", hour), event("sunset", -hour))
    }
    fun phase(now: Long): Double {
        val newMoon = 947182440000L // 2000-01-06 18:14 UTC
        val cycles = (now - newMoon) / 86400000.0 / 29.530588853
        return ((cycles % 1) + 1) % 1
    }
    fun phaseName(phase: Double) = arrayOf("New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
        "Full moon", "Waning gibbous", "Last quarter", "Waning crescent")[floor(phase*8+.5).toInt() % 8]

    fun hazards(alerts: JSONArray?, now: Long): Set<String> = buildSet {
        for (i in 0 until (alerts?.length() ?: 0)) {
            val alert = alerts?.optJSONObject(i) ?: continue
            if (!alert.isNull("expires") && alert.optLong("expires") <= now) continue
            val text = "${alert.optString("title")} ${alert.optString("event")}".lowercase(Locale.ROOT)
            if (Regex("\\b(frost|freeze|freezing|cold|wind chill)\\b").containsMatchIn(text)) add("frost")
            if (Regex("\\b(wind|windstorm|gale|hurricane|tropical storm)\\b").containsMatchIn(text)) add("wind")
            if (text.contains("thunder") || text.contains("lightning")) add("thunder")
        }
    }
    fun color(kind: String, night: Boolean): Int = Color.parseColor(when {
        kind == "rain" || kind == "storm" -> "#3A4652"
        kind in listOf("cloud", "fog", "snow") -> "#2C465E"
        night -> "#111F38"
        else -> "#205A85"
    })
    fun clearNight(data: JSONObject, now: Long) = data.optString("kind") == "sun" && sun(data, now).night(now)
    fun times(data: JSONObject, now: Long): String {
        val sun = sun(data, now)
        val fmt = SimpleDateFormat("h:mma", Locale.US).apply { timeZone = TimeZone.getTimeZone(data.optString("timeZone", "UTC")) }
        fun time(value: Long?) = value?.let { fmt.format(it).lowercase(Locale.US) } ?: "—"
        return if (sun.rise == null && sun.set == null) {
            if (!data.has("latitude")) "Sunrise — · Sunset —" else if (sun.polarDay) "Midnight sun" else "Polar night"
        } else "↑ ${time(sun.rise)}  ↓ ${time(sun.set)}"
    }
    fun moon(now: Long, southern: Boolean): Bitmap {
        val bitmap = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.translate(48f, 48f)
        if (southern) canvas.rotate(180f)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#41617F") }
        canvas.drawCircle(0f, 0f, 44f, paint)
        val phase = phase(now)
        val side = if (phase < .5) 1 else -1
        val terminator = cos(2*PI*phase)
        val path = Path()
        for (i in 0..80) {
            val y = -44.0 + 88.0*i/80
            val x = side * sqrt(max(0.0, 44.0*44-y*y))
            if (i == 0) path.moveTo(x.toFloat(), y.toFloat()) else path.lineTo(x.toFloat(), y.toFloat())
        }
        for (i in 80 downTo 0) {
            val y = -44.0 + 88.0*i/80
            path.lineTo((side*terminator*sqrt(max(0.0, 44.0*44-y*y))).toFloat(), y.toFloat())
        }
        path.close(); paint.color = Color.parseColor("#F1F5FF"); canvas.drawPath(path, paint)
        paint.color = Color.parseColor("#8CAAC6"); paint.style = Paint.Style.STROKE; paint.strokeWidth = 1.5f
        canvas.drawCircle(0f, 0f, 44f, paint)
        return bitmap
    }
    fun background(data: JSONObject, now: Long, wide: Boolean): Bitmap {
        val width = 320; val height = if (wide) 140 else 320
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val color = color(data.optString("kind"), sun(data, now).night(now))
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(0f, 0f, 0f, height.toFloat(), color,
            Color.rgb((Color.red(color)*.75).toInt(), (Color.green(color)*.75).toInt(), (Color.blue(color)*.75).toInt()), Shader.TileMode.CLAMP)
        canvas.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), 24f, 24f, paint)
        canvas.save(); val clip = Path().apply { addRoundRect(0f, 0f, width.toFloat(), height.toFloat(), 24f, 24f, Path.Direction.CW) }; canvas.clipPath(clip)
        val hazards = hazards(data.optJSONArray("alerts"), now).sorted()
        for (side in 0..1) {
            canvas.save()
            if (side == 1) { canvas.translate(width.toFloat(), height.toFloat()); canvas.rotate(180f) }
            for ((index, hazard) in hazards.withIndex()) {
                val edge = Color.parseColor(if (hazard == "thunder") "#D6B8FF" else "#A0DDFA")
                paint.shader = LinearGradient(0f, 0f, 20f, 0f, (edge and 0x00ffffff) or 0x70000000, Color.TRANSPARENT, Shader.TileMode.CLAMP)
                paint.style = Paint.Style.FILL; canvas.drawRect(0f, 0f, 20f, height.toFloat(), paint)
                paint.shader = null; paint.color = edge; paint.style = Paint.Style.STROKE; paint.strokeWidth = 1.8f; paint.strokeCap = Paint.Cap.ROUND
                var y = 24f + index * 32
                while (y < height) {
                    when (hazard) {
                        "frost" -> for (angle in 0..2) {
                            val dx = (cos(angle*PI/3)*7).toFloat(); val dy = (sin(angle*PI/3)*7).toFloat()
                            canvas.drawLine(9-dx, y-dy, 9+dx, y+dy, paint)
                        }
                        "wind" -> canvas.drawPath(Path().apply {
                            moveTo(0f,y); quadTo(22f,y-10,12f,y-14); moveTo(0f,y+5); quadTo(24f,y,17f,y+12)
                        }, paint)
                        else -> canvas.drawPath(Path().apply {
                            moveTo(14f,y-10); lineTo(4f,y+2); lineTo(13f,y+1); lineTo(5f,y+13)
                        }, paint)
                    }
                    y += 96
                }
            }
            canvas.restore()
        }
        canvas.restore()
        return bitmap
    }
}
