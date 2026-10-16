import 'package:flutter/material.dart';

import '../../api/account_api.dart';
import '../../auth/auth_gateway.dart';
import '../clubs/transfer_ownership_sheet.dart';

/// Explains what account deletion removes and keeps, resolves blockers, and
/// deletes the account after the Rider confirms their password.
/// Rules: docs/account-deletion.md.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    required this.riderId,
    required this.accountDeletionApi,
    required this.authGateway,
    this.clubOwnershipApi,
    super.key,
  });

  final String riderId;
  final AccountDeletionApi accountDeletionApi;
  final AuthGateway authGateway;
  final ClubOwnershipApi? clubOwnershipApi;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final TextEditingController _passwordController = TextEditingController();
  late Future<AccountDeletionPreview> _previewFuture;
  bool _understood = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _reload() {
    _previewFuture = widget.accountDeletionApi.previewDeletion();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hapus akun')),
      body: FutureBuilder<AccountDeletionPreview>(
        future: _previewFuture,
        builder:
            (
              BuildContext context,
              AsyncSnapshot<AccountDeletionPreview> snapshot,
            ) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text('Data akun belum dapat dimuat.'),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () => setState(_reload),
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                );
              }
              return _buildContent(context, snapshot.data!);
            },
      ),
    );
  }

  Widget _buildContent(BuildContext context, AccountDeletionPreview preview) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color error = Theme.of(context).colorScheme.error;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: <Widget>[
        Text('Yang akan dihapus', style: text.titleMedium),
        const SizedBox(height: 6),
        const _Bullet('Profil: nama, callsign, dan area'),
        const _Bullet('Akun login dan email'),
        const _Bullet('Kendaraan'),
        const _Bullet('Riwayat lokasi perjalanan'),
        const _Bullet('Notifikasi dan perangkat terdaftar'),
        const SizedBox(height: 16),
        Text('Yang tetap ada untuk anggota lain', style: text.titleMedium),
        const SizedBox(height: 6),
        const _Bullet(
          'Riwayat Ride bersama, chat, dan SOS — nama Anda diganti '
          'menjadi "Rider terhapus"',
        ),
        const _Bullet('Ride mendatang yang Anda buat akan dibatalkan'),
        if (preview.clubsToClose.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Text('Club yang akan ditutup', style: text.titleMedium),
          const SizedBox(height: 6),
          for (final DeletionClub club in preview.clubsToClose)
            _Bullet('${club.name} — tidak ada anggota aktif lain'),
        ],
        if (preview.clubsRequiringTransfer.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          Text(
            'Serahkan kepemilikan dulu',
            style: text.titleMedium?.copyWith(color: error),
          ),
          const SizedBox(height: 6),
          Text(
            'Anda pemilik Club yang masih punya anggota. Pilih pemilik baru '
            'sebelum menghapus akun.',
            style: text.bodyMedium,
          ),
          for (final DeletionClub club in preview.clubsRequiringTransfer)
            Card(
              child: ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text(club.name),
                trailing: widget.clubOwnershipApi == null
                    ? null
                    : TextButton(
                        onPressed: _deleting ? null : () => _transfer(club),
                        child: const Text('Serahkan'),
                      ),
              ),
            ),
        ],
        if (preview.activeRides.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          Text(
            'Selesaikan Ride aktif dulu',
            style: text.titleMedium?.copyWith(color: error),
          ),
          const SizedBox(height: 6),
          for (final DeletionRide ride in preview.activeRides)
            _Bullet('${ride.title} sedang berlangsung'),
        ],
        const SizedBox(height: 24),
        if (!preview.blocked) ...<Widget>[
          CheckboxListTile(
            value: _understood,
            onChanged: _deleting
                ? null
                : (bool? value) => setState(() => _understood = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'Saya mengerti akun tidak dapat dikembalikan setelah dihapus.',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            obscureText: true,
            enabled: !_deleting,
            decoration: const InputDecoration(
              labelText: 'Kata sandi',
              helperText: 'Masukkan kata sandi untuk konfirmasi.',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: _understood && !_deleting ? _delete : null,
            child: Text(_deleting ? 'Menghapus…' : 'Hapus akun permanen'),
          ),
        ],
      ],
    );
  }

  Future<void> _transfer(DeletionClub club) async {
    final bool transferred = await showTransferOwnershipSheet(
      context: context,
      api: widget.clubOwnershipApi!,
      clubId: club.clubId,
      clubName: club.name,
      currentRiderId: widget.riderId,
    );
    if (transferred && mounted) {
      setState(_reload);
    }
  }

  Future<void> _delete() async {
    final String password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = 'Masukkan kata sandi terlebih dahulu.');
      return;
    }
    final AuthGateway gateway = widget.authGateway;
    if (gateway is! AccountDeletionAuthGateway) {
      setState(
        () => _error = 'Hapus akun belum tersedia pada konfigurasi ini.',
      );
      return;
    }
    final AccountDeletionAuthGateway deletionGateway =
        gateway as AccountDeletionAuthGateway;

    setState(() {
      _deleting = true;
      _error = null;
    });

    try {
      await deletionGateway.reauthenticate(password: password);
    } on AuthFailure catch (failure) {
      _fail(
        failure.reason == AuthFailureReason.wrongCredentials
            ? 'Kata sandi salah.'
            : 'Konfirmasi kata sandi gagal. Periksa koneksi lalu coba lagi.',
      );
      return;
    } catch (_) {
      _fail('Konfirmasi kata sandi gagal. Periksa koneksi lalu coba lagi.');
      return;
    }

    try {
      await widget.accountDeletionApi.deleteAccount();
    } on AccountApiException catch (error) {
      if (error.code == 'account_deletion_blocked') {
        // Something changed meanwhile; show the current blockers.
        final AccountDeletionPreview? preview = error.preview;
        setState(() {
          _deleting = false;
          if (preview == null) {
            _reload();
          } else {
            _previewFuture = Future<AccountDeletionPreview>.value(preview);
          }
        });
        return;
      }
      _fail('Akun belum dapat dihapus. Coba lagi nanti.');
      return;
    } catch (_) {
      _fail('Akun belum dapat dihapus. Periksa koneksi lalu coba lagi.');
      return;
    }

    // Server data is gone. Remove the login account; if that fails the login
    // is already detached from the old Rider, so signing out is enough.
    try {
      await deletionGateway.deleteSignedInAccount();
    } catch (_) {
      await widget.authGateway.signOut();
    }
    if (mounted) {
      Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    }
  }

  void _fail(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _deleting = false;
      _error = message;
    });
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('•  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
