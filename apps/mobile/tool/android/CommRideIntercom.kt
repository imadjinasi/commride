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
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.cloudflare.realtimekit.RealtimeKitClient
import com.cloudflare.realtimekit.RealtimeKitMeetingBuilder
import com.cloudflare.realtimekit.RtkMeetingRoomEventListener
import com.cloudflare.realtimekit.meta.SocketConnectionState
import com.cloudflare.realtimekit.meta.SocketState
import com.cloudflare.realtimekit.models.RtkMeetingInfo
import com.cloudflare.realtimekit.participants.RtkParticipantsEventListener
import com.cloudflare.realtimekit.participants.RtkRemoteParticipant
import com.cloudflare.realtimekit.self.RtkSelfEventListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Ride voice intercom over Cloudflare RealtimeKit. The Worker mints the join
 * token; this bridge only joins, toggles the microphone, applies Leader mute
 * and reports room state back to Dart. It never turns a microphone on by
 * itself.
 */
class CommRideIntercom(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var meeting: RealtimeKitClient? = null

    /** What the Rider asked for; a drop to off without asking is a Leader mute. */
    private var wantMic = false

    init {
        MethodChannel(messenger, "commride/intercom").setMethodCallHandler(this)
        EventChannel(messenger, "commride/intercom/events").setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "join" -> join(
                call.argument<String>("authToken"),
                call.argument<String>("baseDomain"),
                result,
            )
            "leave" -> {
                leave()
                result.success(null)
            }
            "setMicrophoneEnabled" ->
                setMicrophone(call.argument<Boolean>("enabled") == true, result)
            "moderatorMute" -> moderatorMute(call.argument<String>("riderId"), result)
            else -> result.notImplemented()
        }
    }

    private fun join(token: String?, baseDomain: String?, result: MethodChannel.Result) {
        if (token.isNullOrEmpty() || baseDomain.isNullOrEmpty()) {
            result.error("invalid_grant", "Missing intercom token.", null)
            return
        }
        leave()
        val client = RealtimeKitMeetingBuilder.build(activity)
        meeting = client
        client.addMeetingRoomEventListener(roomListener)
        client.addSelfEventListener(selfListener)
        client.addParticipantsEventListener(participantsListener)
        // Listen first: no microphone and no camera at join.
        val info = RtkMeetingInfo(
            authToken = token,
            enableAudio = false,
            enableVideo = false,
            baseDomain = baseDomain,
        )
        client.init(
            info,
            onSuccess = {
                client.joinRoom(
                    onSuccess = {
                        main.post {
                            result.success(null)
                            emitParticipants()
                        }
                    },
                    onFailure = { error ->
                        main.post { result.error("join_failed", error.toString(), null) }
                    },
                )
            },
            onFailure = { error ->
                main.post { result.error("init_failed", error.toString(), null) }
            },
        )
    }

    private fun leave() {
        wantMic = false
        IntercomService.stop(activity)
        val client = meeting ?: return
        meeting = null
        client.removeMeetingRoomEventListener(roomListener)
        client.removeSelfEventListener(selfListener)
        client.removeParticipantsEventListener(participantsListener)
        client.leaveRoom(
            onSuccess = { client.release(onSuccess = {}, onFailure = {}) },
            onFailure = { client.release(onSuccess = {}, onFailure = {}) },
        )
    }

    private fun setMicrophone(enabled: Boolean, result: MethodChannel.Result) {
        val client = meeting
        if (client == null) {
            result.error("not_joined", "Intercom is not connected.", null)
            return
        }
        wantMic = enabled
        if (enabled) {
            client.localUser.enableAudio { error ->
                main.post {
                    if (error == null) {
                        // Keeps the microphone working with the screen locked.
                        IntercomService.start(activity)
                        result.success(null)
                    } else {
                        wantMic = false
                        result.error("mic_failed", error.toString(), null)
                    }
                }
            }
        } else {
            client.localUser.disableAudio { error ->
                main.post {
                    if (error == null) result.success(null)
                    else result.error("mic_failed", error.toString(), null)
                }
            }
        }
    }

    private fun moderatorMute(riderId: String?, result: MethodChannel.Result) {
        val target = meeting?.participants?.joined?.firstOrNull {
            it.customParticipantId == riderId
        }
        if (target == null) {
            result.error("not_found", "Rider is not in the intercom.", null)
            return
        }
        val error = target.disableAudio()
        if (error == null) result.success(null)
        else result.error("not_allowed", error.toString(), null)
    }

    private fun emit(event: Map<String, Any?>) {
        main.post { sink?.success(event) }
    }

    private fun emitParticipants() {
        val joined = meeting?.participants?.joined ?: return
        emit(
            mapOf(
                "type" to "participants",
                "participants" to joined.map { participant ->
                    mapOf(
                        "riderId" to (participant.customParticipantId ?: participant.userId),
                        "name" to participant.name,
                        "audioEnabled" to participant.audioEnabled,
                    )
                },
            ),
        )
    }

    private val roomListener = object : RtkMeetingRoomEventListener {
        override fun onSocketConnectionUpdate(newState: SocketConnectionState) {
            val state = when (newState.socketState) {
                SocketState.CONNECTED -> "connected"
                SocketState.RECONNECTING, SocketState.DISCONNECTED -> "reconnecting"
                SocketState.FAILED -> "failed"
            }
            emit(mapOf("type" to "connection", "state" to state))
        }

        override fun onMeetingEnded() {
            emit(mapOf("type" to "connection", "state" to "ended"))
            main.post { leave() }
        }
    }

    private val selfListener = object : RtkSelfEventListener {
        override fun onAudioUpdate(isEnabled: Boolean) {
            if (!isEnabled && wantMic) {
                wantMic = false
                emit(mapOf("type" to "moderatorMuted"))
            }
        }

        override fun onRemovedFromMeeting() {
            emit(mapOf("type" to "connection", "state" to "ended"))
            main.post { leave() }
        }
    }

    private val participantsListener = object : RtkParticipantsEventListener {
        override fun onParticipantJoin(participant: RtkRemoteParticipant) = emitParticipants()

        override fun onParticipantLeave(participant: RtkRemoteParticipant) = emitParticipants()

        override fun onAudioUpdate(participant: RtkRemoteParticipant, isEnabled: Boolean) =
            emitParticipants()

        override fun onActiveSpeakerChanged(participant: RtkRemoteParticipant?) {
            emit(
                mapOf(
                    "type" to "speaker",
                    "riderId" to (participant?.customParticipantId ?: participant?.userId),
                ),
            )
        }
    }
}

/**
 * Foreground service of type microphone so Ride voice keeps working with the
 * screen locked. Started only after the Rider turned the microphone on.
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

        fun start(context: Context) {
            val intent = Intent(context, IntercomService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, IntercomService::class.java))
        }
    }
}
