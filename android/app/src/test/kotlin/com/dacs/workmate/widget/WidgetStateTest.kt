// android/app/src/test/kotlin/com/dacs/workmate/widget/WidgetStateTest.kt
package com.dacs.workmate.widget

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Ported from DACS Attendance WidgetStateTest. The widget is a glance at the
 * home screen, so what it claims has to be exactly what the app would say --
 * and nothing about anyone else.
 */
class WidgetStateTest {

    private val today = "2026-09-11"
    /** 8:52 AM in Manila. */
    private val timeIn = Instant.parse("2026-09-11T00:52:00Z").toEpochMilli()
    /** 5:10 PM in Manila. */
    private val timeOut = Instant.parse("2026-09-11T09:10:00Z").toEpochMilli()

    private fun snap(
        status: String?,
        workDate: String? = today,
        signedIn: Boolean = true,
        timeInAt: Long? = timeIn,
        timeOutAt: Long? = null,
        notSentYet: Boolean = false,
        readFailed: Boolean = false
    ) = WidgetSnapshot(signedIn, workDate, status, timeInAt, timeOutAt, notSentYet, readFailed)

    @Test
    fun `nobody signed in shows the sign-in state even when times are lying around`() {
        val state = widgetStateFor(snap("working", signedIn = false, notSentYet = true), today)
        assertEquals(WidgetState.SignedOut, state)
        assertNull(state.action)
    }

    @Test
    fun `a widget the app never told says it cannot say`() {
        assertEquals(WidgetState.Unknown(), widgetStateFor(null, today))
    }

    @Test
    fun `no record today offers Time In`() {
        val state = widgetStateFor(snap(null), today)
        assertEquals(WidgetState.NotTimedIn(notSentYet = false), state)
        assertEquals(TimeDirection.IN, state.action)
    }

    @Test
    fun `yesterday's record is not today's`() {
        // The snapshot is from before midnight. Showing yesterday's "Complete"
        // this morning would hide the Time In button.
        val state = widgetStateFor(snap("complete", workDate = "2026-09-10", timeOutAt = timeOut), today)
        assertEquals(WidgetState.NotTimedIn(notSentYet = false), state)
    }

    @Test
    fun `an open day offers Time Out`() {
        val state = widgetStateFor(snap("working"), today)
        assertEquals(WidgetState.Working(timeInAt = timeIn, notSentYet = false), state)
        assertEquals(TimeDirection.OUT, state.action)
    }

    @Test
    fun `a finished day offers nothing`() {
        val state = widgetStateFor(snap("complete", timeOutAt = timeOut), today)
        assertEquals(WidgetState.Complete(timeIn, timeOut, notSentYet = false), state)
        assertNull(state.action)
    }

    @Test
    fun `an abandoned day offers nothing`() {
        val state = widgetStateFor(snap("abandoned"), today)
        assertEquals(WidgetState.Abandoned(notSentYet = false), state)
        assertNull(state.action)
    }

    @Test
    fun `a status this build does not know offers nothing rather than guessing`() {
        val state = widgetStateFor(snap("excused"), today)
        assertEquals(WidgetState.Unknown(notSentYet = false), state)
        assertNull(state.action)
    }

    @Test
    fun `a queued submission is flagged not sent yet`() {
        assertEquals(
            WidgetState.Working(timeInAt = timeIn, notSentYet = true),
            widgetStateFor(snap("working", notSentYet = true), today)
        )
    }

    @Test
    fun `a queued row with no record today is still flagged`() {
        assertEquals(WidgetState.NotTimedIn(notSentYet = true), widgetStateFor(snap(null, notSentYet = true), today))
    }

    @Test
    fun `an unreadable mirror is not "not timed in"`() {
        assertEquals(WidgetState.Unknown(), widgetStateFor(snap(null, workDate = null, readFailed = true), today))
    }

    @Test
    fun `today is Manila's date, not UTC's`() {
        // 16:30 UTC on the 10th is 00:30 on the 11th in Manila.
        assertEquals("2026-09-11", manilaIsoDate(Instant.parse("2026-09-10T16:30:00Z").toEpochMilli()))
        assertEquals("2026-09-10", manilaIsoDate(Instant.parse("2026-09-10T15:59:00Z").toEpochMilli()))
    }
}
