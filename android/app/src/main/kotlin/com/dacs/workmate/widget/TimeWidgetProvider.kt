package com.dacs.workmate.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.text.format.DateFormat
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.RemoteViews
import com.dacs.workmate.MainActivity
import com.dacs.workmate.R
import java.util.Date
import java.util.TimeZone

/**
 * The home-screen widget: one solid card, tappable anywhere, opening the same
 * flow Home would. It records nothing itself, and reads only the snapshot the
 * app pushed (WorkmateWidgetBridgePlugin) -- never the network.
 */
class TimeWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        appWidgetIds.forEach { draw(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) {
        draw(context, manager, appWidgetId)
    }

    companion object {
        private const val TAG = "TimeWidget"

        /** KEEP IN STEP with WorkmateWidgetBridgePlugin. */
        private const val PREFS = "workmate_widget"

        /** The intent extra a widget tap sets: "IN" or "OUT" (MainActivity reads it). */
        const val EXTRA_START_FLOW = "com.dacs.workmate.extra.START_FLOW"

        private const val ON_CARD_MUTED = 0xD1FFFFFF.toInt()
        /** Gold on a dark card, not the brown tone. */
        private const val QUEUED = 0xFFE9CE9A.toInt()

        fun draw(context: Context, manager: AppWidgetManager, id: Int) {
            try {
                val state = widgetStateFor(readSnapshot(context), manilaIsoDate(System.currentTimeMillis()))
                val card = widgetCardFor(state)
                val options = manager.getAppWidgetOptions(id)
                val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH).takeIf { it > 0 } ?: 250
                val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT).takeIf { it > 0 } ?: 150
                val views = if (height < FULL_CARD_MIN_HEIGHT_DP) {
                    compactViews(context, card)
                } else {
                    fullViews(context, card, width.toFloat(), height.toFloat())
                }
                views.setOnClickPendingIntent(R.id.widget_card, tapIntent(context, card.action))
                manager.updateAppWidget(id, views)
            } catch (e: Exception) {
                // A widget that cannot draw stays as it was; it must never crash the app's process.
                Log.w(TAG, "widget draw failed", e)
            }
        }

        private fun readSnapshot(context: Context): WidgetSnapshot? {
            val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (!p.getBoolean("present", false)) return null
            return WidgetSnapshot(
                signedIn = p.getBoolean("signed_in", false),
                workDate = p.getString("work_date", null),
                status = p.getString("status", null),
                timeInAt = p.getLong("time_in_at", -1L).takeIf { it >= 0 },
                timeOutAt = p.getLong("time_out_at", -1L).takeIf { it >= 0 },
                notSentYet = p.getBoolean("not_sent_yet", false),
                readFailed = p.getBoolean("read_failed", false)
            )
        }

        private fun background(tone: WidgetTone) = when (tone) {
            WidgetTone.START -> R.drawable.widget_bg_start
            WidgetTone.WORKING -> R.drawable.widget_bg_working
            WidgetTone.COMPLETE -> R.drawable.widget_bg_complete
            WidgetTone.ATTENTION -> R.drawable.widget_bg_attention
            WidgetTone.NEUTRAL -> R.drawable.widget_bg_neutral
        }

        private fun fullViews(context: Context, card: WidgetCard, width: Float, height: Float): RemoteViews {
            val title = context.getString(card.title)
            val type = typeScale(width, height, title.length)
            val v = RemoteViews(context.packageName, R.layout.widget_full)
            v.setInt(R.id.widget_card, "setBackgroundResource", background(card.tone))

            when (val pill = card.pill) {
                WidgetPill.None -> v.setViewVisibility(R.id.widget_pill, View.GONE)
                is WidgetPill.Label -> {
                    v.setViewVisibility(R.id.widget_pill, View.VISIBLE)
                    v.setViewVisibility(R.id.widget_elapsed, View.GONE)
                    v.setViewVisibility(R.id.widget_pill_text, View.VISIBLE)
                    v.setTextViewText(R.id.widget_pill_text, context.getString(pill.text))
                    v.setTextViewTextSize(R.id.widget_pill_text, TypedValue.COMPLEX_UNIT_SP, type.pill)
                }
                is WidgetPill.Elapsed -> {
                    v.setViewVisibility(R.id.widget_pill, View.VISIBLE)
                    v.setViewVisibility(R.id.widget_pill_text, View.GONE)
                    setElapsed(context, v, pill.since, type.pill)
                }
            }

            v.setTextViewText(R.id.widget_arrow, if (card.done) "✓" else "→")
            v.setTextViewTextSize(R.id.widget_arrow, TypedValue.COMPLEX_UNIT_SP, type.arrow)
            v.setTextViewText(R.id.widget_title, title)
            v.setTextViewTextSize(R.id.widget_title, TypedValue.COMPLEX_UNIT_SP, type.title)

            // A short card cannot carry every row: the subtitle repeats what the
            // title and arrow already say, so it is the one that goes.
            if (height >= SUBTITLE_MIN_HEIGHT_DP) {
                v.setViewVisibility(R.id.widget_subtitle, View.VISIBLE)
                v.setTextViewText(R.id.widget_subtitle, subtitleText(context, card.subtitle))
                v.setTextViewTextSize(R.id.widget_subtitle, TypedValue.COMPLEX_UNIT_SP, type.subtitle)
            } else {
                v.setViewVisibility(R.id.widget_subtitle, View.GONE)
            }

            // The footer is the flow breadcrumb, unless a stamp still waits on the
            // phone -- then it says so, and the action stays reachable.
            val footer = when {
                card.queued -> context.getString(R.string.widget_pill_queued)
                card.breadcrumb != null -> context.getString(card.breadcrumb)
                else -> null
            }
            if (footer == null) {
                // Nothing to pin to the bottom: centre the block instead of stranding colour under it.
                v.setViewVisibility(R.id.widget_slack, View.GONE)
                v.setViewVisibility(R.id.widget_rule, View.GONE)
                v.setViewVisibility(R.id.widget_footer, View.GONE)
                v.setInt(R.id.widget_card, "setGravity", Gravity.CENTER_VERTICAL)
            } else {
                v.setViewVisibility(R.id.widget_slack, View.VISIBLE)
                v.setViewVisibility(R.id.widget_rule, View.VISIBLE)
                v.setViewVisibility(R.id.widget_footer, View.VISIBLE)
                v.setTextViewText(R.id.widget_footer, footer)
                v.setTextColor(R.id.widget_footer, if (card.queued) QUEUED else ON_CARD_MUTED)
                v.setTextViewTextSize(R.id.widget_footer, TypedValue.COMPLEX_UNIT_SP, type.footer)
                v.setInt(R.id.widget_card, "setGravity", Gravity.TOP)
            }
            return v
        }

        private fun compactViews(context: Context, card: WidgetCard): RemoteViews {
            val v = RemoteViews(context.packageName, R.layout.widget_compact)
            v.setInt(R.id.widget_card, "setBackgroundResource", background(card.tone))
            v.setTextViewText(R.id.widget_title, context.getString(card.title))
            v.setTextViewText(R.id.widget_arrow, if (card.done) "✓" else "→")
            val pill = card.pill
            when {
                card.queued -> {
                    v.setViewVisibility(R.id.widget_elapsed, View.GONE)
                    v.setViewVisibility(R.id.widget_subtitle, View.VISIBLE)
                    v.setTextViewText(R.id.widget_subtitle, context.getString(R.string.widget_pill_queued))
                    v.setTextColor(R.id.widget_subtitle, QUEUED)
                }
                pill is WidgetPill.Elapsed -> {
                    v.setViewVisibility(R.id.widget_subtitle, View.GONE)
                    setElapsed(context, v, pill.since, 11f)
                }
                else -> {
                    v.setViewVisibility(R.id.widget_elapsed, View.GONE)
                    v.setViewVisibility(R.id.widget_subtitle, View.VISIBLE)
                    v.setTextViewText(R.id.widget_subtitle, subtitleText(context, card.subtitle))
                    v.setTextColor(R.id.widget_subtitle, ON_CARD_MUTED)
                }
            }
            return v
        }

        /**
         * A Chronometer counting up from [since]. It measures against
         * elapsedRealtime (uptime) while a Time In is a wall-clock instant, so
         * the base is now's uptime minus how long ago the stamp was.
         */
        private fun setElapsed(context: Context, v: RemoteViews, since: Long, sizeSp: Float) {
            val agoMillis = System.currentTimeMillis() - since
            v.setViewVisibility(R.id.widget_elapsed, View.VISIBLE)
            v.setChronometer(
                R.id.widget_elapsed,
                SystemClock.elapsedRealtime() - agoMillis,
                context.getString(R.string.widget_pill_on_site) + " %s",
                true
            )
            v.setTextViewTextSize(R.id.widget_elapsed, TypedValue.COMPLEX_UNIT_SP, sizeSp)
        }

        private fun subtitleText(context: Context, subtitle: WidgetSubtitle): String = when (subtitle) {
            is WidgetSubtitle.Label -> context.getString(subtitle.text)
            is WidgetSubtitle.DaySpan -> context.getString(
                R.string.widget_sub_day_span,
                clock(context, subtitle.timeIn),
                clock(context, subtitle.timeOut)
            )
        }

        /** Manila time, in the phone's own 12- or 24-hour style. */
        private fun clock(context: Context, epochMillis: Long): String {
            val format = DateFormat.getTimeFormat(context)
            format.timeZone = TimeZone.getTimeZone("Asia/Manila")
            return format.format(Date(epochMillis))
        }

        /**
         * A distinct ACTION and request code per direction: two intents that
         * differ only in extras are the same PendingIntent to Android, and the
         * Time Out tap would be handed the Time In one.
         */
        private fun tapIntent(context: Context, action: TimeDirection?): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (action == null) {
                intent.action = Intent.ACTION_MAIN
            } else {
                intent.action = "com.dacs.workmate.action.START_FLOW_${action.name}"
                intent.putExtra(EXTRA_START_FLOW, action.name)
            }
            val requestCode = action?.let { it.ordinal + 1 } ?: 0
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        }
    }
}
