package com.dacs.workmate.widget

import androidx.annotation.StringRes
import com.dacs.workmate.R
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.max
import kotlin.math.min

/*
 * The home-screen widget's rules, pure on purpose: no Context, no RemoteViews,
 * so every phrase and colour the home screen can show is settled by a JUnit
 * test. Ported from DACS Attendance domain/WidgetState.kt and
 * widget/WidgetCard.kt. No java.time: minSdk 24 without desugaring.
 */

/** What the app last pushed (lib/widget/widget_snapshot.dart). Never names who. */
data class WidgetSnapshot(
    val signedIn: Boolean,
    val workDate: String?,
    val status: String?,
    val timeInAt: Long?,
    val timeOutAt: Long?,
    val notSentYet: Boolean,
    val readFailed: Boolean
)

enum class TimeDirection { IN, OUT }

sealed interface WidgetState {
    /** This worker still has a submission queued on the phone. */
    val notSentYet: Boolean

    data object SignedOut : WidgetState {
        override val notSentYet: Boolean = false
    }

    data class NotTimedIn(override val notSentYet: Boolean = false) : WidgetState

    /** [timeInAt] is null only for a record that lost it; no live count then. */
    data class Working(val timeInAt: Long?, override val notSentYet: Boolean = false) : WidgetState

    data class Complete(val timeInAt: Long?, val timeOutAt: Long?, override val notSentYet: Boolean = false) : WidgetState

    data class Abandoned(override val notSentYet: Boolean = false) : WidgetState

    /** A status this build cannot name, or nothing readable. No button: guessing IN or OUT costs a refused photo. */
    data class Unknown(override val notSentYet: Boolean = false) : WidgetState

    /** The one action the widget offers. Same rule as Home's. */
    val action: TimeDirection?
        get() = when (this) {
            is NotTimedIn -> TimeDirection.IN
            is Working -> TimeDirection.OUT
            else -> null
        }
}

private const val MANILA_OFFSET_MS = 8L * 60 * 60 * 1000

/** "2026-09-11": the Manila calendar date of an instant (UTC+8 all year, no DST since 1978). */
fun manilaIsoDate(epochMillis: Long): String =
    SimpleDateFormat("yyyy-MM-dd", Locale.US)
        .apply { timeZone = TimeZone.getTimeZone("UTC") }
        .format(Date(epochMillis + MANILA_OFFSET_MS))

/**
 * Today's widget. [today] is decided HERE at every redraw, not by the app, so a
 * snapshot from yesterday rolls over at Manila midnight with nothing running.
 */
fun widgetStateFor(snapshot: WidgetSnapshot?, today: String): WidgetState {
    if (snapshot == null) return WidgetState.Unknown()
    if (!snapshot.signedIn) return WidgetState.SignedOut
    val pending = snapshot.notSentYet
    if (snapshot.readFailed) return WidgetState.Unknown(pending)
    val status = snapshot.status
    if (snapshot.workDate != today || status == null) return WidgetState.NotTimedIn(pending)
    return when (status.lowercase(Locale.US)) {
        "working" -> WidgetState.Working(snapshot.timeInAt, pending)
        "complete" -> WidgetState.Complete(snapshot.timeInAt, snapshot.timeOutAt, pending)
        "abandoned" -> WidgetState.Abandoned(pending)
        else -> WidgetState.Unknown(pending)
    }
}

/** The card's colour, carrying the app's usual meaning. */
enum class WidgetTone {
    /** Green: nothing recorded yet, the day is ahead. */
    START,
    /** Deep green: on site, the stamp accepted. */
    WORKING,
    /** Deepest green: the day is closed and correct. */
    COMPLETE,
    /** Brown: a day closed without a Time Out needs a person. */
    ATTENTION,
    /** Grey-green: the widget cannot say, and will not guess. */
    NEUTRAL
}

sealed interface WidgetPill {
    data object None : WidgetPill
    data class Label(@StringRes val text: Int) : WidgetPill
    /** A live count since [since] (epoch ms), drawn by a system Chronometer. */
    data class Elapsed(val since: Long) : WidgetPill
}

sealed interface WidgetSubtitle {
    data class Label(@StringRes val text: Int) : WidgetSubtitle
    /** Today's two stamps (epoch ms). */
    data class DaySpan(val timeIn: Long, val timeOut: Long) : WidgetSubtitle
}

data class WidgetCard(
    val tone: WidgetTone,
    val pill: WidgetPill,
    @StringRes val title: Int,
    val subtitle: WidgetSubtitle,
    /** The flow's step list, or null where tapping starts no flow. */
    @StringRes val breadcrumb: Int?,
    /** A stamp is still on the phone; the footer says so instead. */
    val queued: Boolean,
    /** Draw a tick rather than an arrow. */
    val done: Boolean,
    /** What the tap starts. Null opens the app instead. */
    val action: TimeDirection?
)

fun widgetCardFor(state: WidgetState): WidgetCard = when (state) {
    WidgetState.SignedOut -> WidgetCard(
        tone = WidgetTone.START,
        pill = WidgetPill.Label(R.string.widget_pill_sign_in),
        title = R.string.widget_card_sign_in,
        subtitle = WidgetSubtitle.Label(R.string.widget_sub_sign_in),
        breadcrumb = null,
        queued = false,
        done = false,
        action = null
    )

    is WidgetState.NotTimedIn -> WidgetCard(
        tone = WidgetTone.START,
        pill = WidgetPill.Label(R.string.widget_pill_step_one),
        title = R.string.widget_card_time_in,
        subtitle = WidgetSubtitle.Label(R.string.widget_sub_start_day),
        breadcrumb = R.string.widget_flow_in,
        queued = state.notSentYet,
        done = false,
        action = TimeDirection.IN
    )

    is WidgetState.Working -> WidgetCard(
        tone = WidgetTone.WORKING,
        // Without a recorded Time In there is nothing to count from; counting
        // from now would read 00:00:00 in the afternoon.
        pill = state.timeInAt?.let { WidgetPill.Elapsed(it) } ?: WidgetPill.Label(R.string.widget_pill_on_site),
        title = R.string.widget_card_time_out,
        subtitle = WidgetSubtitle.Label(R.string.widget_sub_close_day),
        // Three steps out, not four: the project is already known.
        breadcrumb = R.string.widget_flow_out,
        queued = state.notSentYet,
        done = false,
        action = TimeDirection.OUT
    )

    is WidgetState.Complete -> WidgetCard(
        tone = WidgetTone.COMPLETE,
        pill = WidgetPill.Label(R.string.widget_pill_all_done),
        title = R.string.widget_card_complete,
        subtitle = if (state.timeInAt != null && state.timeOutAt != null) {
            WidgetSubtitle.DaySpan(state.timeInAt, state.timeOutAt)
        } else {
            WidgetSubtitle.Label(R.string.widget_done_no_times)
        },
        breadcrumb = null,
        queued = state.notSentYet,
        done = true,
        action = null
    )

    is WidgetState.Abandoned -> WidgetCard(
        tone = WidgetTone.ATTENTION,
        pill = WidgetPill.Label(R.string.widget_pill_no_time_out),
        title = R.string.widget_card_day_closed,
        subtitle = WidgetSubtitle.Label(R.string.widget_sub_sort_out),
        breadcrumb = null,
        queued = state.notSentYet,
        // Closed, but not correctly.
        done = false,
        action = null
    )

    is WidgetState.Unknown -> WidgetCard(
        tone = WidgetTone.NEUTRAL,
        pill = WidgetPill.None,
        title = R.string.widget_card_open_app,
        subtitle = WidgetSubtitle.Label(R.string.widget_sub_unavailable),
        breadcrumb = null,
        queued = state.notSentYet,
        done = false,
        action = null
    )
}

/** Below this the card drops to one row. */
const val FULL_CARD_MIN_HEIGHT_DP = 100f

/** Below this the subtitle goes, so the title keeps its size. */
const val SUBTITLE_MIN_HEIGHT_DP = 138f

/** The card's type sizes, in sp. */
data class CardType(val title: Float, val subtitle: Float, val pill: Float, val footer: Float, val arrow: Float)

private fun Float.clamp(lo: Float, hi: Float) = max(lo, min(hi, this))

/**
 * Type scaled to the cell, bounded by width as well as height: widget text does
 * not shrink to fit, so the title actually drawn has to survive on one line.
 * 0.58em per character is a little generous for bold sans, erring smaller.
 */
fun typeScale(widthDp: Float, heightDp: Float, titleLength: Int): CardType {
    // A small widget must stay legible at arm's length in sunlight.
    val byHeight = if (heightDp < SUBTITLE_MIN_HEIGHT_DP) heightDp * 0.30f else heightDp * 0.24f
    val perChar = max(titleLength, 1) * 0.58f
    val byWidth = (widthDp - 32f) / perChar
    val title = min(byHeight, byWidth).clamp(18f, 44f)
    return CardType(
        title = title,
        subtitle = (title * 0.52f).clamp(12f, 19f),
        pill = (title * 0.42f).clamp(10f, 14f),
        footer = (title * 0.46f).clamp(11f, 16f),
        arrow = (title * 0.60f).clamp(15f, 26f)
    )
}
