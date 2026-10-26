package dev.jeeth.local_weather

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import org.json.JSONArray
import kotlin.math.max

internal data class TemperaturePoint(val time: Long, val value: Double, val label: String, val temperature: String)

internal object TemperatureGraph {
    fun high(points: List<TemperaturePoint>): String =
        points.maxByOrNull { it.value }?.temperature?.takeIf { it.isNotBlank() } ?: "—"

    fun low(points: List<TemperaturePoint>): String =
        points.minByOrNull { it.value }?.temperature?.takeIf { it.isNotBlank() } ?: "—"

    fun points(hours: JSONArray?, now: Long): List<TemperaturePoint> =
        (0 until (hours?.length() ?: 0)).mapNotNull { index ->
            val hour = hours?.optJSONObject(index) ?: return@mapNotNull null
            val value = hour.optDouble("temperature", Double.NaN)
            val time = hour.optLong("timestamp")
            if (!value.isFinite() || time <= now - 1800000 || time > now + 43200000) null
            else TemperaturePoint(time, value, hour.optString("time"), hour.optString("temperatureText"))
        }.sortedBy { it.time }.distinctBy { it.time }.take(13)

    fun draw(points: List<TemperaturePoint>, stale: Boolean, fahrenheit: Boolean): Bitmap {
        // One small bitmap per update, shared by all 2×2 instances (~57 KB).
        val bitmap = Bitmap.createBitmap(240, 60, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        if (points.size < 2) return bitmap
        val left = 5f
        val right = 235f
        val top = 6f
        val bottom = 54f
        val minimum = points.minOf { it.value }
        val maximum = points.maxOf { it.value }
        // Fixed minimum vertical range keeps tiny changes from looking dramatic.
        val span = max(if (fahrenheit) 7.2 else 4.0, maximum - minimum)
        val middle = (maximum + minimum) / 2
        val timeSpan = max(1L, points.last().time - points.first().time)
        fun x(point: TemperaturePoint) = left +
            ((point.time - points.first().time).toDouble() / timeSpan * (right - left)).toFloat()
        fun y(point: TemperaturePoint) =
            (top + (middle + span / 2 - point.value) / span * (bottom - top)).toFloat()
        paint.color = Color.parseColor("#527369")
        paint.strokeWidth = 1f
        canvas.drawLine(left, bottom, right, bottom, paint)
        val segments = mutableListOf<MutableList<TemperaturePoint>>()
        for (point in points) {
            // Missing hours remain gaps, rather than implying a continuous forecast.
            if (segments.isEmpty() || point.time - segments.last().last().time > 5400000) {
                segments.add(mutableListOf())
            }
            segments.last().add(point)
        }
        for (segment in segments) {
            val line = Path().apply {
                moveTo(x(segment.first()), y(segment.first()))
                segment.drop(1).forEach { lineTo(x(it), y(it)) }
            }
            if (segment.size > 1) {
                val fill = Path(line).apply {
                    lineTo(x(segment.last()), bottom)
                    lineTo(x(segment.first()), bottom)
                    close()
                }
                paint.style = Paint.Style.FILL
                paint.shader = LinearGradient(0f, top, 0f, bottom,
                    Color.parseColor(if (stale) "#30FFD29C" else "#30F7C78C"),
                    Color.TRANSPARENT, Shader.TileMode.CLAMP)
                canvas.drawPath(fill, paint)
                paint.shader = null
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = 3.5f
                paint.strokeCap = Paint.Cap.ROUND
                paint.strokeJoin = Paint.Join.ROUND
                paint.color = Color.parseColor(if (stale) "#FFD29C" else "#F7C78C")
                canvas.drawPath(line, paint)
            }
            paint.style = Paint.Style.FILL
            paint.color = Color.parseColor("#F7C78C")
            canvas.drawCircle(x(segment.first()), y(segment.first()), 3f, paint)
            canvas.drawCircle(x(segment.last()), y(segment.last()), 3f, paint)
        }
        return bitmap
    }
}
