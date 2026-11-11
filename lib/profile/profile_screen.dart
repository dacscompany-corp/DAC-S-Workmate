import 'package:flutter/material.dart';

import '../agreements/ui/agreements_controller.dart';
import '../attendance/ui/formats.dart';
import '../attendance/ui/status_pill.dart';
import '../auth/worker_profile.dart';
import '../tools/ui/tools_controller.dart';
import '../ui/terms_screen.dart';
import '../ui/theme.dart';
import '../ui/wm_sheet.dart';
import 'account_services.dart';
import 'change_password_sheet.dart';

/// "2 tools with you · 1 problem reported" (redesign spec §7.2).
String toolsLine(int tools, int problems) {
  final base = tools == 0 ? 'No tools with you' : '$tools tool${tools == 1 ? '' : 's'} with you';
  return problems == 0 ? base : '$base · $problems problem${problems == 1 ? '' : 's'} reported';
}

/// Profile: who is signed in, what is theirs (My tools, My agreements), the
/// password, the Terms they accepted, Log out. A buyer (2A-3b) has no worker
/// ID, accepted no Attendance Terms (Q23) and has no MINE section.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.worker,
    required this.versionName,
    required this.onSignOut,
    required this.account,
    this.buyer = false,
    this.tools,
    this.onOpenTools,
    this.agreements,
    this.onOpenAgreements,
  });

  final WorkerProfile worker;
  final String versionName;
  final Future<void> Function() onSignOut;
  final AccountServices account;
  final bool buyer;

  /// My tools (Stage 3b): its MINE row shows when tools are on for this worker.
  final ToolsController? tools;
  final VoidCallback? onOpenTools;

  /// Linked Labor (0113): its MINE row shows only after this session's read
  /// found an agreement. Never an amount.
  final AgreementsController? agreements;
  final VoidCallback? onOpenAgreements;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  DateTime? _acceptedAt;

  @override
  void initState() {
    super.initState();
    if (!widget.buyer) _loadAcceptedAt();
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
    final changed = await showWmSheet<bool>(context, builder: (_) => ChangePasswordSheet(onSave: widget.account.changePassword));
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
    final mine = <Listenable>[?widget.tools, ?widget.agreements];
    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 28), children: [
      const Text('Profile', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26)),
      const SizedBox(height: 14),
      _ProfileCard(worker: w, subtitle: widget.buyer ? 'Buyer' : w.positionAndId),
      if (!widget.buyer && mine.isNotEmpty) ListenableBuilder(listenable: Listenable.merge(mine), builder: (context, _) => _mineSection()),
      const SizedBox(height: 20),
      const Text('ACCOUNT', style: monoLabel),
      const SizedBox(height: 8),
      _Card(children: [
        _InfoRow(label: 'Email', value: w.email ?? '--'),
        if (widget.buyer) const _InfoRow(label: 'Role', value: 'Buyer'),
        if (!widget.buyer) _InfoRow(label: 'Position', value: position == null || position.isEmpty ? '--' : position),
        if (!widget.buyer) _InfoRow(label: 'Worker ID', value: w.workerIdLabel),
        _ActionRow(
          key: const Key('profile-change-password'),
          icon: Icons.lock_outline,
          title: 'Change password',
          subtitle: 'Update your login',
          onTap: _changePassword,
        ),
        if (!widget.buyer)
          _ActionRow(
            key: const Key('profile-terms'),
            icon: Icons.gavel,
            title: 'Terms & Conditions',
            subtitle: at == null ? 'Read the terms you accepted' : 'Accepted ${shortDate(at)}',
            onTap: _openTerms,
          ),
      ]),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: widget.onSignOut,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: WmColors.green,
          backgroundColor: Colors.white,
          side: const BorderSide(color: WmColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontFamily: 'Barlow', fontSize: 15, fontWeight: FontWeight.w800),
        ),
        icon: const Icon(Icons.logout, size: 20),
        label: const Text('Log out'),
      ),
      const SizedBox(height: 16),
      Text("DAC'S WorkMate ${widget.versionName} · By Dacs Building Design Services",
          style: const TextStyle(fontSize: 12.5, color: WmColors.textMeta)),
    ]);
  }

  Widget _mineSection() {
    final tools = widget.tools;
    final agreements = widget.agreements;
    final rows = <Widget>[
      if (tools != null && tools.showCard)
        _ActionRow(
          key: const Key('profile-tools'),
          icon: Icons.handyman_outlined,
          title: 'My tools',
          subtitle: toolsLine(tools.mine.length, tools.openProblems),
          onTap: widget.onOpenTools ?? () {},
        ),
      if (agreements != null && agreements.showCard)
        _ActionRow(
          key: const Key('profile-agreements'),
          icon: Icons.description_outlined,
          title: 'My agreements',
          subtitle: '${agreements.agreements.length} agreement${agreements.agreements.length == 1 ? '' : 's'}',
          onTap: widget.onOpenAgreements ?? () {},
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 20),
      const Text('MINE', style: monoLabel),
      const SizedBox(height: 8),
      _Card(children: rows),
    ]);
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.worker, required this.subtitle});

  final WorkerProfile worker;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: WmColors.border), borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: WmColors.green,
            child: Text(worker.initials, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(worker.displayName ?? worker.firstName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text(subtitle, style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
              const SizedBox(height: 6),
              const StatusPill.green('Active account'),
            ]),
          ),
        ]),
      );
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
