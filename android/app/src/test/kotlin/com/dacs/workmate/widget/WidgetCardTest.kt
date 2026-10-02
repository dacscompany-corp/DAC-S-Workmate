// android/app/src/test/kotlin/com/dacs/workmate/widget/WidgetCardTest.kt
package com.dacs.workmate.widget

import com.dacs.workmate.R
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ported from DACS Attendance WidgetCardTest. The card is the whole widget,
 * so these pin every phrase the home screen can show.
 */
class WidgetCardTest {

    /** 7:52 AM in Manila. */
    private val timeIn = Instant.parse("2026-09-14T23:52:00Z").toEpochMilli()
    /** 4:56 PM in Manila. */
    private val timeOut = Instant.parse("2026-09-15T08:56:00Z").toEpochMilli()

    @Test
    fun `nothing recorded yet offers Time In and warns of four steps`() {
        val card = widgetCardFor(WidgetState.NotTimedIn())
        assertEquals(WidgetTone.START, card.tone)
        assertEquals(WidgetPill.Label(R.string.widget_pill_step_one), card.pill)
        assertEquals(R.string.widget_card_time_in, card.title)
        assertEquals(WidgetSubtitle.Label(R.string.widget_sub_start_day), card.subtitle)
        assertEquals(R.string.widget_flow_in, card.breadcrumb)
        assertEquals(TimeDirection.IN, card.action)
        assertFalse(card.done)
    }

    @Test
    fun `on site counts up from the recorded time in`() {
        val card = widgetCardFor(WidgetState.Working(timeIn))
        assertEquals(WidgetTone.WORKING, card.tone)
        assertEquals(WidgetPill.Elapsed(timeIn), card.pill)
        assertEquals(R.string.widget_card_time_out, card.title)
        assertEquals(WidgetSubtitle.Label(R.string.widget_sub_close_day), card.subtitle)
        assertEquals(R.string.widget_flow_out, card.breadcrumb)
        assertEquals(TimeDirection.OUT, card.action)
    }

    @Test
    fun `on site without a recorded time in shows no live count`() {
        val card = widgetCardFor(WidgetState.Working(timeInAt = null))
        assertEquals(WidgetPill.Label(R.string.widget_pill_on_site), card.pill)
        assertEquals(TimeDirection.OUT, card.action)
    }

    @Test
    fun `a closed day shows both stamps and a tick`() {
        val card = widgetCardFor(WidgetState.Complete(timeIn, timeOut))
        assertEquals(WidgetTone.COMPLETE, card.tone)
        assertEquals(WidgetPill.Label(R.string.widget_pill_all_done), card.pill)
        assertEquals(R.string.widget_card_complete, card.title)
        assertEquals(WidgetSubtitle.DaySpan(timeIn, timeOut), card.subtitle)
        assertTrue(card.done)
        assertNull(card.breadcrumb)
        assertNull(card.action)
    }

    @Test
    fun `a closed day missing a stamp says so rather than printing a gap`() {
        val card = widgetCardFor(WidgetState.Complete(timeIn, timeOutAt = null))
        assertEquals(WidgetSubtitle.Label(R.string.widget_done_no_times), card.subtitle)
        assertTrue(card.done)
    }

    @Test
    fun `a day closed without a Time Out asks for a person`() {
        val card = widgetCardFor(WidgetState.Abandoned())
        assertEquals(WidgetTone.ATTENTION, card.tone)
        assertEquals(WidgetPill.Label(R.string.widget_pill_no_time_out), card.pill)
        assertEquals(R.string.widget_card_day_closed, card.title)
        assertEquals(WidgetSubtitle.Label(R.string.widget_sub_sort_out), card.subtitle)
        assertNull(card.action)
        assertFalse(card.done)
    }

    @Test
    fun `a status this build cannot name guesses nothing`() {
        val card = widgetCardFor(WidgetState.Unknown())
        assertEquals(WidgetTone.NEUTRAL, card.tone)
        assertEquals(WidgetPill.None, card.pill)
        assertEquals(R.string.widget_card_open_app, card.title)
        assertEquals(WidgetSubtitle.Label(R.string.widget_sub_unavailable), card.subtitle)
        assertNull(card.breadcrumb)
        assertNull(card.action)
    }

    @Test
    fun `signed out invites a sign-in and starts no flow`() {
        val card = widgetCardFor(WidgetState.SignedOut)
        assertEquals(WidgetPill.Label(R.string.widget_pill_sign_in), card.pill)
        assertEquals(R.string.widget_card_sign_in, card.title)
        assertEquals(WidgetSubtitle.Label(R.string.widget_sub_sign_in), card.subtitle)
        assertNull(card.action)
        assertFalse(card.queued)
    }

    @Test
    fun `a queued stamp still leaves Time Out reachable`() {
        val card = widgetCardFor(WidgetState.Working(timeIn, notSentYet = true))
        assertTrue(card.queued)
        assertEquals(WidgetTone.WORKING, card.tone)
        assertEquals(TimeDirection.OUT, card.action)
        assertEquals(WidgetPill.Elapsed(timeIn), card.pill)
    }

    @Test
    fun `a queued stamp before timing in keeps the Time In card`() {
        val card = widgetCardFor(WidgetState.NotTimedIn(notSentYet = true))
        assertTrue(card.queued)
        assertEquals(TimeDirection.IN, card.action)
    }

    @Test
    fun `nothing queued leaves the breadcrumb alone`() {
        assertFalse(widgetCardFor(WidgetState.Working(timeIn)).queued)
    }
}
