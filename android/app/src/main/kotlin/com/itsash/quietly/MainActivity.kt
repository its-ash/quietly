package com.itsash.quietly

import android.Manifest
import android.app.NotificationManager
import android.app.StatusBarManager
import android.bluetooth.BluetoothManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel "com.itsash.quietly/control" (Dart side: lib/rules/rules_platform.dart):
 *   - getConfig() -> {enabled, running, rules (JSON string), active: [ruleId]}
 *   - setEnabled({enabled}): saves the master switch and starts/stops RulesService.
 *   - saveRules({json}): stores the rules JSON; the running service re-evaluates.
 *   - status() -> {notifications, location, backgroundLocation, locationServices, bluetooth,
 *                  dnd, writeSettings, overlay, battery, tileSupported}  (keys = Need names in Dart)
 *   - openPermission({name}): asks for, or opens the settings page of, one of the status keys.
 *   - getLog() -> [{time (ms), rule, active}], clearLog().
 *   - currentSsid() -> String? (needs location permission and Location on).
 *   - bluetoothDevices() -> [{name, address}] of paired devices (needs Bluetooth permission).
 *   - apps() -> [{label, package}] launchable apps.
 *   - addTile() -> asks Android 13+ to add the Quick Settings tile.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.itsash.quietly/control"
    private lateinit var prefs: QuietlyPrefs

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        prefs = QuietlyPrefs(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getConfig" -> result.success(
                        mapOf(
                            "enabled" to prefs.serviceEnabled,
                            "running" to RulesService.running,
                            "rules" to prefs.rulesJson,
                            "active" to prefs.activeIds.toList(),
                        ),
                    )
                    "setEnabled" -> {
                        prefs.serviceEnabled = call.argument<Boolean>("enabled") ?: false
                        RulesService.sync(this)
                        result.success(null)
                    }
                    "saveRules" -> {
                        prefs.rulesJson = call.argument<String>("json") ?: "[]"
                        result.success(null)
                    }
                    "status" -> result.success(status())
                    "openPermission" -> {
                        openPermission(call.argument<String>("name"))
                        result.success(null)
                    }
                    "getLog" -> result.success(
                        prefs.log.map { mapOf("time" to it.time, "rule" to it.rule, "active" to it.active) },
                    )
                    "clearLog" -> {
                        prefs.log = emptyList()
                        result.success(null)
                    }
                    "currentSsid" -> result.success(WifiSsid.current(this))
                    "bluetoothDevices" -> result.success(bluetoothDevices())
                    "apps" -> loadApps(result)
                    "addTile" -> addTile(result)
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                result.error("failed", e.message, null)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // The user may have just granted a permission a rule was waiting for.
        RulesService.refresh()
    }

    private fun status(): Map<String, Any?> {
        val nm = getSystemService(NotificationManager::class.java)
        val power = getSystemService(PowerManager::class.java)
        val location = getSystemService(LocationManager::class.java)
        return mapOf(
            "notifications" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                granted(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                nm.areNotificationsEnabled()
            },
            "location" to granted(Manifest.permission.ACCESS_FINE_LOCATION),
            "backgroundLocation" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || granted(Manifest.permission.ACCESS_BACKGROUND_LOCATION)),
            "locationServices" to location.isLocationEnabled,
            "bluetooth" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || granted(Manifest.permission.BLUETOOTH_CONNECT)),
            "dnd" to nm.isNotificationPolicyAccessGranted,
            "writeSettings" to Settings.System.canWrite(this),
            "overlay" to Settings.canDrawOverlays(this),
            "battery" to power.isIgnoringBatteryOptimizations(packageName),
            "tileSupported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU),
        )
    }

    private fun granted(permission: String) = checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun openPermission(name: String?) {
        val pkg = Uri.parse("package:$packageName")
        when (name) {
            "notifications" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    requestOrSettings(name, Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                }
            }
            "location" -> requestOrSettings(name, Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
            "backgroundLocation" -> when {
                !granted(Manifest.permission.ACCESS_FINE_LOCATION) -> openPermission("location")
                // From Android 11 the "Allow all the time" choice is only offered in the app's settings.
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> openAppSettings()
                else -> requestOrSettings(name, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
            }
            "locationServices" -> startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
            "bluetooth" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) requestOrSettings(name, Manifest.permission.BLUETOOTH_CONNECT)
            }
            "dnd" -> startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
            "writeSettings" -> startActivity(Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, pkg))
            "overlay" -> startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, pkg))
            "battery" -> {
                @Suppress("BatteryLife")
                startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, pkg))
            }
        }
    }

    /** Ask with the system dialog once; after that (it may be blocked) open the app's settings. */
    private fun requestOrSettings(key: String, vararg permissions: String) {
        if (prefs.asked(key)) {
            openAppSettings()
        } else {
            prefs.markAsked(key)
            requestPermissions(arrayOf(*permissions), 1)
        }
    }

    private fun openAppSettings() {
        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
    }

    private fun bluetoothDevices(): List<Map<String, String>> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !granted(Manifest.permission.BLUETOOTH_CONNECT)) return emptyList()
        val adapter = getSystemService(BluetoothManager::class.java)?.adapter ?: return emptyList()
        return adapter.bondedDevices.orEmpty()
            .map { mapOf("name" to (it.name ?: it.address), "address" to it.address.uppercase()) }
            .sortedBy { it["name"]?.lowercase() }
    }

    private fun loadApps(result: MethodChannel.Result) {
        Thread {
            val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            val apps = packageManager.queryIntentActivities(launcher, 0)
                .map { mapOf("label" to it.loadLabel(packageManager).toString(), "package" to it.activityInfo.packageName) }
                .filter { it["package"] != packageName }
                .distinctBy { it["package"] }
                .sortedBy { it["label"]?.lowercase() }
            runOnUiThread { result.success(apps) }
        }.start()
    }

    private fun addTile(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(false)
            return
        }
        getSystemService(StatusBarManager::class.java).requestAddTileService(
            ComponentName(this, RulesTileService::class.java),
            "Quietly",
            Icon.createWithResource(this, R.drawable.ic_stat_quietly),
            mainExecutor,
        ) { code ->
            result.success(
                code == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED ||
                    code == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED,
            )
        }
    }
}
