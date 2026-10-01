package com.dacs.workmate

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Wait at most this long for a fix: no fix flags the record, it never refuses it. */
private const val FIX_TIMEOUT_MS = 15_000L

/** A fix older than this is treated as no fix (a stale fix could verify the wrong place). */
private const val FIX_MAX_AGE_MS = 2 * 60 * 1000L

/**
 * The attendance channel. Ported from DACS Attendance ClockAnchorStore,
 * Connectivity, LocationProvider and PhotoStore — same rules, same order.
 */
class AttendanceBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "clock" -> result.success(mapOf("uptimeMillis" to SystemClock.elapsedRealtime(), "bootCount" to bootCount()))
            "isOnline" -> result.success(isOnline())
            "currentFix" -> currentFix { result.success(it) }
            "preparePhoto" -> {
                val source = call.argument<String>("source")
                val target = call.argument<String>("target")
                val caption = call.argument<String>("caption")
                val mirror = call.argument<Boolean>("mirror") ?: false
                if (source == null || target == null || caption == null) {
                    result.error("BAD_ARGS", "source, target and caption are required", null)
                    return
                }
                io.execute {
                    try {
                        PhotoPreparer.prepare(File(source), File(target), caption, mirror)
                        main.post { result.success(target) }
                    } catch (e: Throwable) {
                        // Includes OutOfMemoryError: Dart must always be answered.
                        main.post { result.error("PHOTO_FAILED", e.message, null) }
                    }
                }
            }
            "openLocationSettings" -> {
                try {
                    context.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                } catch (e: Exception) {
                    result.error("NO_SETTINGS", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Global since API 24 (our minSdk); some OEM builds still omit it. */
    private fun bootCount(): Int? =
        runCatching { Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT) }.getOrNull()

    private fun isOnline(): Boolean {
        val manager = ContextCompat.getSystemService(context, ConnectivityManager::class.java) ?: return false
        val caps = manager.getNetworkCapabilities(manager.activeNetwork) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }

    private fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** A missing LocationManager answers TRUE: being unable to ask must not become an accusation. */
    private fun isLocationEnabled(): Boolean {
        val manager = ContextCompat.getSystemService(context, LocationManager::class.java) ?: return true
        return LocationManagerCompat.isLocationEnabled(manager)
    }

    /** Every failure path answers with a map, never an exception. Runs its callback once, on the main thread. */
    private fun currentFix(callback: (Map<String, Any?>) -> Unit) {
        if (!hasPermission()) return callback(mapOf("permissionDenied" to true))
        // Switched off is somebody's decision; checked BEFORE asking for a fix.
        if (!isLocationEnabled()) return callback(mapOf("locationDisabled" to true))

        var done = false
        fun finish(fix: Map<String, Any?>) {
            if (done) return
            done = true
            callback(fix)
        }

        val cancel = CancellationTokenSource()
        main.postDelayed({
            cancel.cancel()
            finish(emptyMap())
        }, FIX_TIMEOUT_MS)

        try {
            LocationServices.getFusedLocationProviderClient(context)
                .getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, cancel.token)
                .addOnSuccessListener { location -> finish(location?.let(::toFix) ?: emptyMap()) }
                .addOnFailureListener { finish(emptyMap()) }
        } catch (e: SecurityException) {
            // Revoked between the check and the request: a denial, which is what it is.
            finish(mapOf("permissionDenied" to true))
        } catch (e: Exception) {
            // Play Services missing or broken: an unverified record, not a lockout.
            finish(emptyMap())
        }
    }

    private fun toFix(location: Location): Map<String, Any?> {
        val ageMs = (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1_000_000
        if (ageMs > FIX_MAX_AGE_MS) return emptyMap()
        val isMock = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            location.isMock
        } else {
            @Suppress("DEPRECATION")
            location.isFromMockProvider
        }
        return mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            // No accuracy is a location we cannot place: left null so it reads as low accuracy.
            "accuracyMetres" to if (location.hasAccuracy()) location.accuracy.toDouble() else null,
            "isMock" to isMock
        )
    }
}
