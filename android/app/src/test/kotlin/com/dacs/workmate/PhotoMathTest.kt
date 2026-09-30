package com.dacs.workmate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PhotoMathTest {
    private val budget = 1600

    private fun measurer(charWidthAt1pt: Float, text: String): (Float) -> Float =
        { size -> text.length * charWidthAt1pt * size }

    @Test fun `text that already fits is left alone`() {
        assertEquals(40f, fitTextSize(40f, 1000f, measurer(0.5f, "short")), 0.01f)
    }

    @Test fun `text that overflows is shrunk until it fits`() {
        val caption = "ABC Building Project · 25 Aug 2026 · 8:45 PM"
        val measure = measurer(0.6f, caption)
        val size = fitTextSize(40f, 600f, measure)
        assertTrue(size < 40f)
        assertTrue(measure(size) <= 600f)
    }

    @Test fun `shrinking stops at a floor rather than becoming unreadable`() {
        val size = fitTextSize(40f, 10f, measurer(1f, "an extremely long caption that cannot fit"))
        assertEquals(MIN_CAPTION_TEXT_SIZE_RATIO * 40f, size, 0.01f)
    }

    @Test fun `a capture already inside the budget is decoded whole`() {
        assertEquals(1, photoSampleSize(1600, 1200, budget))
        assertEquals(1, photoSampleSize(800, 600, budget))
    }

    @Test fun `orientation does not matter`() {
        assertEquals(photoSampleSize(4000, 3000, budget), photoSampleSize(3000, 4000, budget))
    }

    @Test fun `a 12 MP capture halves once and a 32 MP capture quarters`() {
        assertEquals(2, photoSampleSize(4000, 3000, budget))
        assertEquals(4, photoSampleSize(6528, 4896, budget))
    }

    @Test fun `sampling never takes a capture below the budget and is a power of two`() {
        for (longest in listOf(1600, 1601, 2400, 3200, 4000, 6528, 9000, 12000, 20000)) {
            val sample = photoSampleSize(longest, longest / 2, budget)
            assertTrue(longest / sample >= budget)
            assertTrue(sample > 0 && sample and (sample - 1) == 0)
        }
    }

    @Test fun `a bitmap that could not be measured decodes whole`() {
        assertEquals(1, photoSampleSize(-1, -1, budget))
        assertEquals(1, photoSampleSize(0, 0, budget))
    }
}
