// android/app/src/test/kotlin/com/dacs/workmate/widget/WidgetTypeScaleTest.kt
package com.dacs.workmate.widget

import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ported from DACS Attendance WidgetTypeScaleTest. Widget text does not shrink
 * to fit and the title is one line, so a title too big for the cell is
 * ellipsised. These pin the geometry: the longest title must fit.
 */
class WidgetTypeScaleTest {

    private val cardPadding = 32f
    /** Deliberately tighter than the implementation's 0.58em: production may be more cautious, never less. */
    private val perCharEm = 0.55f
    /** The longest title in widget_strings.xml. */
    private val longestTitle = "DAC'S WorkMate"

    private fun drawnWidth(fontSizeSp: Float, title: String) = fontSizeSp * title.length * perCharEm

    @Test
    fun `the longest title fits the card at the default widget size`() {
        val type = typeScale(250f, 110f, longestTitle.length)
        val available = 250f - cardPadding
        val drawn = drawnWidth(type.title, longestTitle)
        assertTrue("\"$longestTitle\" at ${type.title}sp draws ${drawn}dp in ${available}dp", drawn <= available)
    }

    @Test
    fun `a short title is allowed to grow larger than a long one on the same card`() {
        val short = typeScale(250f, 110f, "Time In".length).title
        val long = typeScale(250f, 110f, longestTitle.length).title
        assertTrue("7 chars got ${short}sp, 14 chars got ${long}sp", short > long)
    }

    @Test
    fun `a long title on a narrow card still stops at the legibility floor`() {
        assertTrue(typeScale(100f, 110f, 40).title >= 18f)
    }
}
