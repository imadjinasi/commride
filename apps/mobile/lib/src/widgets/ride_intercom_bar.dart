import 'dart:async';

import 'package:flutter/material.dart';

import '../active_ride/voice_intercom.dart';
import '../theme/commride_theme.dart';

/// Interkom row under the group summary on the riding map. One 48 dp row:
/// state or current speaker, a settings button (mode and Riders) and one
/// large microphone button that works with a gloved thumb at a stop.
class RideIntercomBar extends StatelessWidget {
  const RideIntercomBar({
    required this.voiceIntercomEnabled,
    required this.controller,
    super.key,
  });

  /// Build flag; false keeps the row visibly "coming soon".
  final bool voiceIntercomEnabled;

  /// Null when this device has no intercom transport.
  final RideVoiceController? controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final RideVoiceController? voice = controller;

    if (!voiceIntercomEnabled || voice == null) {
      return _Shell(
        children: <Widget>[
          Icon(Icons.headset_mic_outlined, color: colors.outline),
          const SizedBox(width: 10),
          Expanded(
            child: _Label(
              voiceIntercomEnabled
                  ? 'Interkom belum tersedia di HP ini'
                  : 'Interkom segera tersedia',
              color: colors.outline,
            ),
          ),
        ],
      );
    }

    final RideVoiceState state = voice.state;
    final _Status status = _status(state, colors);

    return _Shell(
      children: <Widget>[
        Icon(status.icon, color: status.color),
        const SizedBox(width: 10),
        Expanded(child: _Label(status.text, color: status.color)),
        if (state.connected)
          IconButton(
            key: const ValueKey<String>('intercom-settings'),
            tooltip: 'Pengaturan interkom',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => unawaited(_openSheet(context, voice)),
            icon: const Icon(Icons.tune),
          ),
        _ActionButton(state: state, controller: voice),
      ],
    );
  }

  static _Status _status(RideVoiceState state, ColorScheme colors) {
    final String? speaker = _speakerName(state);
    switch (state.connectionPhase) {
      case RideVoiceConnectionPhase.disconnected:
        return _Status(
          Icons.headset_off_outlined,
          state.message ?? 'Interkom belum tersambung',
          colors.outline,
        );
      case RideVoiceConnectionPhase.connecting:
        return _Status(
          Icons.headset_mic_outlined,
          'Menyambung interkom…',
          colors.outline,
        );
      case RideVoiceConnectionPhase.degraded:
        return _Status(
          Icons.signal_cellular_connected_no_internet_4_bar,
          state.message ?? 'Sinyal lemah, menyambung ulang…',
          CommRideColors.signalOrange,
        );
      case RideVoiceConnectionPhase.connected:
        break;
    }

    // The Rider's own muted state outranks who is speaking: they need to
    // know nobody hears them until they tap the mic again.
    if (state.moderatorMuted) {
      return const _Status(
        Icons.mic_off,
        'Mic dimatikan Ketua',
        CommRideColors.criticalRed,
      );
    }
    if (speaker != null) {
      return _Status(Icons.graphic_eq, '$speaker bicara', colors.primary);
    }
    final int others = state.participants.length;
    final String count = others == 0 ? 'belum ada rider lain' : '$others rider';
    return switch (state.mode) {
      RideVoiceMode.groupIntercom when state.microphoneEnabled => _Status(
        Icons.mic,
        'Mic menyala · $count',
        colors.primary,
      ),
      RideVoiceMode.groupIntercom => _Status(
        Icons.headset_outlined,
        'Mendengar · $count',
        null,
      ),
      RideVoiceMode.pushToTalk when state.pushToTalkActive => _Status(
        Icons.mic,
        'Bicara… tap lagi untuk selesai',
        colors.primary,
      ),
      RideVoiceMode.pushToTalk => _Status(
        Icons.headset_outlined,
        'Tap mic untuk bicara',
        null,
      ),
      RideVoiceMode.listenOnly => _Status(
        Icons.hearing,
        'Dengar saja · $count',
        null,
      ),
    };
  }

  static String? _speakerName(RideVoiceState state) {
    for (final String riderId in state.activeSpeakerRiderIds) {
      for (final RideVoiceParticipant participant in state.participants) {
        if (participant.riderId == riderId) return participant.name;
      }
      return 'Rider';
    }
    return null;
  }

  static Future<void> _openSheet(
    BuildContext context,
    RideVoiceController voice,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => _IntercomSheet(controller: voice),
    );
  }
}

class _Status {
  const _Status(this.icon, this.text, this.color);

  final IconData icon;
  final String text;
  final Color? color;
}

class _Shell extends StatelessWidget {
  const _Shell({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(CommRideRadii.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 4),
          child: Row(children: children),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontWeight: FontWeight.w700, color: color),
    );
  }
}

/// The one big control: connect, mic on/off, or tap to talk.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.state, required this.controller});

  final RideVoiceState state;
  final RideVoiceController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    if (state.connectionPhase == RideVoiceConnectionPhase.disconnected) {
      return _button(
        key: 'intercom-connect',
        tooltip: 'Sambungkan interkom',
        icon: Icons.refresh,
        active: false,
        colors: colors,
        onPressed: () => unawaited(controller.join()),
      );
    }
    if (state.connectionPhase == RideVoiceConnectionPhase.connecting) {
      return const SizedBox(
        width: 56,
        height: 48,
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    return switch (state.mode) {
      RideVoiceMode.groupIntercom => _button(
        key: 'intercom-mic',
        tooltip: state.microphoneEnabled ? 'Matikan mic' : 'Nyalakan mic',
        icon: state.microphoneEnabled ? Icons.mic : Icons.mic_off,
        active: state.microphoneEnabled,
        colors: colors,
        onPressed: () => unawaited(controller.toggleMicrophone()),
      ),
      RideVoiceMode.pushToTalk => _button(
        key: 'intercom-ptt',
        tooltip: state.pushToTalkActive ? 'Selesai bicara' : 'Tap untuk bicara',
        icon: state.pushToTalkActive ? Icons.mic : Icons.mic_none,
        active: state.pushToTalkActive,
        colors: colors,
        onPressed: () => unawaited(controller.togglePushToTalk()),
      ),
      RideVoiceMode.listenOnly => _button(
        key: 'intercom-listen',
        tooltip: 'Mode dengar saja',
        icon: Icons.mic_off,
        active: false,
        colors: colors,
        onPressed: null,
      ),
    };
  }

  Widget _button({
    required String key,
    required String tooltip,
    required IconData icon,
    required bool active,
    required ColorScheme colors,
    required VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        width: 56,
        height: 40,
        child: Tooltip(
          message: tooltip,
          child: active
              ? FilledButton(
                  key: ValueKey<String>(key),
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                  child: Icon(icon, size: 26),
                )
              : OutlinedButton(
                  key: ValueKey<String>(key),
                  onPressed: onPressed,
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                  child: Icon(icon, size: 26),
                ),
        ),
      ),
    );
  }
}

/// Mode choice, the Riders in the room, and Leader mute. Rebuilds with the
/// controller so speaking and mic state stay live while it is open.
class _IntercomSheet extends StatelessWidget {
  const _IntercomSheet({required this.controller});

  final RideVoiceController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final RideVoiceState state = controller.state;
        final ThemeData theme = Theme.of(context);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: <Widget>[
                Text('Interkom Ride', style: theme.textTheme.titleLarge),
                const SizedBox(height: CommRideSpacing.sm),
                RadioGroup<RideVoiceMode>(
                  groupValue: state.mode,
                  onChanged: (RideVoiceMode? mode) {
                    if (mode != null) unawaited(controller.setMode(mode));
                  },
                  child: const Column(
                    children: <Widget>[
                      RadioListTile<RideVoiceMode>(
                        key: ValueKey<String>('intercom-mode-open'),
                        value: RideVoiceMode.groupIntercom,
                        title: Text('Mic aktif terus'),
                        subtitle: Text('Cukup bicara, mic tetap menyala.'),
                      ),
                      RadioListTile<RideVoiceMode>(
                        key: ValueKey<String>('intercom-mode-ptt'),
                        value: RideVoiceMode.pushToTalk,
                        title: Text('Tap untuk bicara'),
                        subtitle: Text(
                          'Tap mic, bicara, tap lagi. Mati sendiri '
                          'setelah 30 detik.',
                        ),
                      ),
                      RadioListTile<RideVoiceMode>(
                        key: ValueKey<String>('intercom-mode-listen'),
                        value: RideVoiceMode.listenOnly,
                        title: Text('Dengar saja'),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Text(
                  state.participants.isEmpty
                      ? 'Belum ada rider lain di interkom'
                      : 'Rider di interkom',
                  style: theme.textTheme.titleMedium,
                ),
                if (controller.canModerate && state.participants.isNotEmpty)
                  Text(
                    'Bisukan mematikan mic rider untuk semua orang. '
                    'Rider itu bisa menyalakannya lagi sendiri.',
                    style: theme.textTheme.bodySmall,
                  ),
                for (final RideVoiceParticipant rider in state.participants)
                  _ParticipantTile(
                    rider: rider,
                    speaking: state.activeSpeakerRiderIds.contains(
                      rider.riderId,
                    ),
                    controller: controller,
                  ),
                const SizedBox(height: CommRideSpacing.sm),
                OutlinedButton.icon(
                  key: const ValueKey<String>('intercom-leave'),
                  onPressed: () {
                    unawaited(controller.leave());
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.call_end),
                  label: const Text('Keluar interkom'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.rider,
    required this.speaking,
    required this.controller,
  });

  final RideVoiceParticipant rider;
  final bool speaking;
  final RideVoiceController controller;

  @override
  Widget build(BuildContext context) {
    final bool locallyMuted = controller.state.locallyMutedRiderIds.contains(
      rider.riderId,
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        speaking
            ? Icons.graphic_eq
            : (rider.audioEnabled ? Icons.mic : Icons.mic_off),
      ),
      title: Text(rider.name),
      subtitle: Text(
        speaking
            ? 'Sedang bicara'
            : (rider.audioEnabled ? 'Mic menyala' : 'Mic mati'),
      ),
      trailing: Wrap(
        spacing: 4,
        children: <Widget>[
          if (controller.supportsLocalMute)
            IconButton(
              tooltip: locallyMuted ? 'Dengarkan lagi' : 'Bisukan untuk saya',
              onPressed: () => unawaited(
                controller.setLocalMute(rider.riderId, !locallyMuted),
              ),
              icon: Icon(
                locallyMuted ? Icons.volume_off : Icons.volume_up_outlined,
              ),
            ),
          if (controller.canModerate && rider.audioEnabled)
            TextButton(
              key: ValueKey<String>('intercom-mute-${rider.riderId}'),
              onPressed: () =>
                  unawaited(controller.moderatorMute(rider.riderId)),
              child: const Text('Bisukan'),
            ),
        ],
      ),
    );
  }
}
