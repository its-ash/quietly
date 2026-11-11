package com.itsash.quietly

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.time.ZonedDateTime

/** The current Wi-Fi network name, or null. Android hides it without Location permission and Location turned on. */
object WifiSsid {
    @Suppress("DEPRECATION")
    fun current(context: Context): String? {
        val wifi = context.applicationContext.getSystemService(WifiManager::class.java) ?: return null
        if (!wifi.isWifiEnabled) return null
        val info = try {
            wifi.connectionInfo
        } catch (_: SecurityException) {
            null
        } ?: return null
        if (info.networkId == -1) return null
        val ssid = info.ssid?.removeSurrounding("\"") ?: return null
        return ssid.takeIf { it.isNotEmpty() && it != WifiManager.UNKNOWN_SSID }
    }
}

/**
 * Listens for changes in everything a condition looks at (Wi-Fi, headphones, Bluetooth,
 * battery, the clock) and builds a [Snapshot] on demand. [onChange] runs on the main
 * thread, at most once per burst of events.
 */
class ContextWatcher(context: Context, private val onChange: () -> Unit) {

    private val context = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val audio = this.context.getSystemService(AudioManager::class.java)
    private val connectivity = this.context.getSystemService(ConnectivityManager::class.java)
    private val alarms = this.context.getSystemService(AlarmManager::class.java)
    private val connectedBluetooth = mutableSetOf<String>()
    private var started = false

    private val fire = Runnable { onChange() }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_ACL_CONNECTED -> device(intent)?.let { connectedBluetooth += it.address.uppercase() }
                BluetoothDevice.ACTION_ACL_DISCONNECTED -> device(intent)?.let { connectedBluetooth -= it.address.uppercase() }
                BluetoothAdapter.ACTION_STATE_CHANGED -> {
                    connectedBluetooth.clear()
                    if (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1) == BluetoothAdapter.STATE_ON) seedBluetooth()
                }
            }
            changed()
        }
    }

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = changed()
        override fun onLost(network: Network) = changed()
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = changed()
    }

    private val audioCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = changed()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = changed()
    }

    fun start() {
        if (started) return
        started = true
        val filter = IntentFilter().apply {
            addAction(AudioManager.ACTION_HEADSET_PLUG)
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(Intent.ACTION_BATTERY_CHANGED)
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            // Once a minute while the CPU is awake; the alarm covers the rest.
            addAction(Intent.ACTION_TIME_TICK)
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
            addAction(Intent.ACTION_DATE_CHANGED)
            addAction(ACTION_ALARM)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
        runCatching {
            connectivity?.registerNetworkCallback(
                NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build(),
                networkCallback,
                main,
            )
        }
        audio?.registerAudioDeviceCallback(audioCallback, main)
        seedBluetooth()
    }

    fun stop() {
        if (!started) return
        started = false
        main.removeCallbacks(fire)
        runCatching { context.unregisterReceiver(receiver) }
        runCatching { connectivity?.unregisterNetworkCallback(networkCallback) }
        audio?.unregisterAudioDeviceCallback(audioCallback)
        alarms?.cancel(alarmIntent())
    }

    private fun changed() {
        main.removeCallbacks(fire)
        main.postDelayed(fire, DEBOUNCE_MS)
    }

    fun snapshot(now: ZonedDateTime = ZonedDateTime.now()): Snapshot {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val plugged = (battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
        return Snapshot(
            ssid = WifiSsid.current(context),
            minuteOfDay = now.hour * 60 + now.minute,
            isoDay = now.dayOfWeek.value,
            headphones = headphonesConnected(),
            bluetooth = connectedBluetooth.toSet(),
            charging = plugged,
            battery = if (level >= 0 && scale > 0) level * 100 / scale else 100,
        )
    }

    private fun headphonesConnected(): Boolean {
        val devices = audio?.getDevices(AudioManager.GET_DEVICES_OUTPUTS) ?: return false
        return devices.any { it.type in HEADPHONE_TYPES }
    }

    /** Wakes the phone at the next time-window start or end (inexact: Doze may delay it a little). */
    fun scheduleBoundary(rules: List<Rule>) {
        val am = alarms ?: return
        val pending = alarmIntent()
        val next = Schedule.nextBoundary(rules, ZonedDateTime.now())
        if (next == null) {
            am.cancel(pending)
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.toInstant().toEpochMilli(), pending)
        }
    }

    private fun alarmIntent(): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(ACTION_ALARM).setPackage(context.packageName),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    @Suppress("DEPRECATION")
    private fun device(intent: Intent): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }

    /** Devices that were already connected before the service started: ask the audio profiles. */
    private fun seedBluetooth() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val adapter = context.getSystemService(BluetoothManager::class.java)?.adapter ?: return
        for (profile in intArrayOf(BluetoothProfile.A2DP, BluetoothProfile.HEADSET)) {
            runCatching {
                adapter.getProfileProxy(
                    context,
                    object : BluetoothProfile.ServiceListener {
                        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                            runCatching { connectedBluetooth += proxy.connectedDevices.map { it.address.uppercase() } }
                            adapter.closeProfileProxy(profile, proxy)
                            changed()
                        }

                        override fun onServiceDisconnected(profile: Int) = Unit
                    },
                    profile,
                )
            }
        }
    }

    companion object {
        const val ACTION_ALARM = "com.itsash.quietly.ALARM"
        private const val DEBOUNCE_MS = 400L

        private val HEADPHONE_TYPES = setOf(
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_HEARING_AID,
            26, // TYPE_BLE_HEADSET (API 31)
        )
    }
}
