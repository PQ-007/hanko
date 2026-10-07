package com.hanko.mobile

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the "hanko/app_icon" channel: the home-screen icon follows the app
 * theme (core/app_icon.dart). The icon is one of three launcher entries in
 * AndroidManifest.xml (.IconPaper / .IconDark / .IconBlue, see
 * IconTrampoline.kt), and switching means enabling one and disabling the
 * others.
 *
 * The switch is applied in onStop, not when it's asked for: toggling a
 * launcher component can make some launchers restart the app's task, which
 * mid-use would look like a crash. Leaving the app is a safe moment.
 */
class MainActivity : FlutterActivity() {
    private val aliases = mapOf("paper" to ".IconPaper", "dark" to ".IconDark", "blue" to ".IconBlue")
    private var pendingIcon: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hanko/app_icon")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "set" -> {
                        val name = call.arguments as? String
                        if (name == null || name !in aliases) {
                            result.error("bad_icon", "unknown icon $name", null)
                        } else {
                            pendingIcon = name
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onStop() {
        super.onStop()
        pendingIcon?.let { applyIcon(it) }
        pendingIcon = null
    }

    private fun applyIcon(name: String) {
        val pm = packageManager
        for ((key, alias) in aliases) {
            val component = ComponentName(this, packageName + alias)
            val want = if (key == name) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            // Skip no-op writes: each one makes the launcher re-scan.
            val current = pm.getComponentEnabledSetting(component)
            val effective = if (current == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT) {
                if (key == "paper") PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            } else current
            if (effective != want) {
                pm.setComponentEnabledSetting(component, want, PackageManager.DONT_KILL_APP)
            }
        }
    }
}
