package com.dacs.workmate

/** Below this the caption is unreadable on a phone, no better than cut off. */
const val MIN_CAPTION_TEXT_SIZE_RATIO = 0.55f

/**
 * The largest text size at or below [preferred] whose width fits [maxWidth].
 * The timestamp ("PM") is the part that must never be lost off the edge.
 */
fun fitTextSize(preferred: Float, maxWidth: Float, measure: (Float) -> Float): Float {
    if (measure(preferred) <= maxWidth) return preferred
    val floor = preferred * MIN_CAPTION_TEXT_SIZE_RATIO
    var size = preferred
    while (size > floor) {
        size -= preferred * 0.05f
        if (measure(size) <= maxWidth) return size
    }
    return floor
}

/**
 * How far down to sample while decoding, so a 13 MP selfie (52 MB as ARGB_8888)
 * never exists at full size on a phone capped at 96 MB. Powers of two only,
 * and never below [maxEdge]; an unmeasurable file decodes whole.
 */
fun photoSampleSize(width: Int, height: Int, maxEdge: Int): Int {
    val longest = maxOf(width, height)
    if (longest <= 0 || maxEdge <= 0) return 1
    var sample = 1
    while (longest / (sample * 2) >= maxEdge) sample *= 2
    return sample
}
