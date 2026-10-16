// Copied into the generated Android project by tool/configure_platforms.py,
// which prepends the app package line. Edit this file, not the copy.

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground service of type microphone so Ride voice (LiveKit, in Dart)
 * keeps working with the screen locked. Dart starts it only after the Rider
 * turned the microphone on, and stops it when leaving the intercom.
 */
class IntercomService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Interkom Ride",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val content = launch?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE)
        }
        val notification = builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("Interkom Ride aktif")
            .setContentText("Mikrofon interkom bisa dipakai saat layar terkunci.")
            .setOngoing(true)
            .setContentIntent(content)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    companion object {
        private const val CHANNEL_ID = "commride_intercom"
        private const val NOTIFICATION_ID = 4107

        /** Method channel `commride/intercom_service`: start / stop. */
        fun register(activity: Activity, messenger: BinaryMessenger) {
            MethodChannel(messenger, "commride/intercom_service")
                .setMethodCallHandler { call, result ->
                    val intent = Intent(activity, IntercomService::class.java)
                    when (call.method) {
                        "start" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                activity.startForegroundService(intent)
                            } else {
                                activity.startService(intent)
                            }
                            result.success(null)
                        }
                        "stop" -> {
                            activity.stopService(intent)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
        }
    }
}
