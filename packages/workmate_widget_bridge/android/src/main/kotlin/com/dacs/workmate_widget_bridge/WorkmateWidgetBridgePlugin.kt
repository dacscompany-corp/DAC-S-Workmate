package com.dacs.workmate_widget_bridge

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Hands the home-screen widget its snapshot from ANY Flutter engine: the app's,
 * and WorkManager's background one (which has plugins but no MainActivity).
 *
 * Writes the app's private widget prefs, then asks the provider to redraw.
 * KEEP IN STEP with com.dacs.workmate.widget.TimeWidgetProvider (app module):
 * the file name, the keys and the provider class name below.
 */
class WorkmateWidgetBridgePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.dacs.workmate/widget")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "push") return result.notImplemented()
        try {
            save(call)
            redraw()
            result.success(null)
        } catch (e: Exception) {
            result.error("WIDGET", e.message, null)
        }
    }

    /** Every key, every time: a sign-out must leave nothing of the last worker's day. */
    private fun save(call: MethodCall) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean("present", true)
            .putBoolean("signed_in", call.argument<Boolean>("signedIn") == true)
            .putString("work_date", call.argument<String>("workDate"))
            .putString("status", call.argument<String>("status"))
            .putLong("time_in_at", call.argument<Number>("timeInAt")?.toLong() ?: -1L)
            .putLong("time_out_at", call.argument<Number>("timeOutAt")?.toLong() ?: -1L)
            .putBoolean("not_sent_yet", call.argument<Boolean>("notSentYet") == true)
            .putBoolean("read_failed", call.argument<Boolean>("readFailed") == true)
            .commit()
    }

    private fun redraw() {
        val provider = ComponentName(context.packageName, PROVIDER)
        val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(provider)
        // Most phones never place the widget: nothing to draw.
        if (ids.isEmpty()) return
        context.sendBroadcast(
            Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .setComponent(provider)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        )
    }

    private companion object {
        const val PREFS = "workmate_widget"
        const val PROVIDER = "com.dacs.workmate.widget.TimeWidgetProvider"
    }
}
