import 'package:flutter/material.dart';

import '../attendance/ui/formats.dart';
import '../attendance/ui/status_pill.dart';
import '../auth/worker_profile.dart';
import '../ui/terms_screen.dart';
import '../ui/theme.dart';
import '../ui/worker_header.dart';
import 'account_services.dart';
import 'change_password_sheet.dart';

/// Profile: who is signed in, the password, the Terms they accepted, Log out.
/// Ported from DACS Attendance's ProfileScreen.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.worker,
    required this.versionName,
    required this.onSignOut,
    required this.account,
  });

  final WorkerProfile worker;
  final String versionName;
  final Future<void> Function() onSignOut;
  final AccountServices account;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  DateTime? _acceptedAt;

  @override
  void initState() {
    super.initState();
    _loadAcceptedAt();
  }

  Future<void> _loadAcceptedAt() async {
    try {
      final at = await widget.account.termsAcceptedAt();
      if (mounted) setState(() => _acceptedAt = at);
    } catch (_) {
      // The row then simply offers the terms, with no date.
    }
  }

  Future<void> _changePassword() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChangePasswordSheet(onSave: widget.account.changePassword),
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your password has been changed.')));
    }
  }

  void _openTerms() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TermsReaderScreen(acceptedAt: _acceptedAt)));

  @override
  Widget build(BuildContext context) {
    final w = widget.worker;
    final at = _acceptedAt;
    final position = w.position?.trim();
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Profile', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 23)),
      const SizedBox(height: 16),
      WorkerHeader(worker: w),
      const SizedBox(height: 10),
      const Align(alignment: Alignment.centerLeft, child: StatusPill.green('Active account')),
      const SizedBox(height: 18),
      _Card(children: [
        _InfoRow(label: 'Email', value: w.email ?? '--'),
        _InfoRow(label: 'Position', value: position == null || position.isEmpty ? '--' : position),
        _InfoRow(label: 'Worker ID', value: w.workerIdLabel),
      ]),
      const SizedBox(height: 14),
      _Card(children: [
        _ActionRow(
          key: const Key('profile-change-password'),
          icon: Icons.lock_outline,
          title: 'Change password',
          subtitle: 'Update your login',
          onTap: _changePassword,
        ),
        _ActionRow(
          key: const Key('profile-terms'),
          icon: Icons.description_outlined,
          title: 'Terms & Conditions',
          subtitle: at == null ? 'Read the terms you accepted' : 'Accepted ${shortDate(at)}',
          onTap: _openTerms,
        ),
      ]),
      const SizedBox(height: 24),
      OutlinedButton.icon(onPressed: widget.onSignOut, icon: const Icon(Icons.logout), label: const Text('Log out')),
      const SizedBox(height: 16),
      Text("DAC'S WorkMate ${widget.versionName} · By Dacs Building Design Services",
          style: const TextStyle(fontSize: 12.5, color: WmColors.textMeta)),
    ]);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: WmColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: WmColors.hairline),
            children[i],
          ],
        ]),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Text(label, style: const TextStyle(fontSize: 14, color: WmColors.textMuted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
          ),
        ]),
      );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Icon(icon, color: WmColors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: WmColors.textMuted),
          ]),
        ),
      );
}
