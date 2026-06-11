import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/providers/auth_provider.dart';

/// Account settings: change password, change email, log out everywhere, and
/// delete account (GDPR / DPDPA erasure). All actions hit the authenticated
/// `/account/*` (and `/auth/logout-all`) endpoints.
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      appBar: AppBar(
        title: const Text('Account & security'),
        backgroundColor: AppTheme.backgroundCream,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsTile(
            title: 'Change password',
            subtitle: 'Update the password you use to sign in',
            icon: Icons.lock_outline,
            onTap: () => _showChangePassword(context, ref),
          ),
          const SizedBox(height: 12),
          _SettingsTile(
            title: 'Change email',
            subtitle: 'Update your email — you\'ll need to verify the new one',
            icon: Icons.alternate_email,
            onTap: () => _showChangeEmail(context, ref),
          ),
          const SizedBox(height: 12),
          _SettingsTile(
            title: 'Log out of all devices',
            subtitle: 'Sign out everywhere, including this device',
            icon: Icons.devices_outlined,
            onTap: () => _confirmLogoutAll(context, ref),
          ),
          const SizedBox(height: 12),
          _SettingsTile(
            title: 'Delete account',
            subtitle: 'Permanently delete your account and all data',
            icon: Icons.delete_outline,
            danger: true,
            onTap: () => _showDeleteAccount(context, ref),
          ),
        ],
      ),
    );
  }

  // ── Change password ─────────────────────────────────────────────────────
  void _showChangePassword(BuildContext context, WidgetRef ref) {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();

    _showActionSheet(
      context: context,
      title: 'Change password',
      builder: (setBusy, busy) => Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PasswordField(controller: current, label: 'Current password'),
            const SizedBox(height: 12),
            _PasswordField(
              controller: next,
              label: 'New password',
              validator: (v) => (v == null || v.length < 8)
                  ? 'At least 8 characters'
                  : null,
            ),
            const SizedBox(height: 12),
            _PasswordField(
              controller: confirm,
              label: 'Confirm new password',
              validator: (v) => v != next.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 20),
            _SubmitButton(
              label: 'Update password',
              busy: busy,
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setBusy(true);
                try {
                  await ref
                      .read(authProvider.notifier)
                      .changePassword(current.text, next.text);
                  if (context.mounted) {
                    Navigator.pop(context);
                    _toast(context, 'Password updated.');
                  }
                } catch (e) {
                  setBusy(false);
                  if (context.mounted) _toast(context, _errorText(e));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Change email ────────────────────────────────────────────────────────
  void _showChangeEmail(BuildContext context, WidgetRef ref) {
    final email = TextEditingController();
    final password = TextEditingController();
    final formKey = GlobalKey<FormState>();

    _showActionSheet(
      context: context,
      title: 'Change email',
      builder: (setBusy, busy) => Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'New email address'),
              validator: (v) =>
                  (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
                      ? 'Enter a valid email'
                      : null,
            ),
            const SizedBox(height: 12),
            _PasswordField(controller: password, label: 'Current password'),
            const SizedBox(height: 20),
            _SubmitButton(
              label: 'Update email',
              busy: busy,
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setBusy(true);
                try {
                  await ref
                      .read(authProvider.notifier)
                      .changeEmail(email.text.trim(), password.text);
                  if (context.mounted) {
                    Navigator.pop(context);
                    _toast(context, 'Email updated. Check your inbox to verify it.');
                  }
                } catch (e) {
                  setBusy(false);
                  if (context.mounted) _toast(context, _errorText(e));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Log out everywhere ──────────────────────────────────────────────────
  void _confirmLogoutAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out of all devices?'),
        content: const Text(
          'You\'ll be signed out everywhere, including this device, and will '
          'need to sign in again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authProvider.notifier).logoutAllDevices();
      if (context.mounted) context.go('/auth/login');
    }
  }

  // ── Delete account ──────────────────────────────────────────────────────
  void _showDeleteAccount(BuildContext context, WidgetRef ref) {
    final password = TextEditingController();
    final formKey = GlobalKey<FormState>();

    _showActionSheet(
      context: context,
      title: 'Delete account',
      builder: (setBusy, busy) => Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This permanently deletes your account and all associated health '
              'data. This cannot be undone.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.glucoseLow),
            ),
            const SizedBox(height: 16),
            _PasswordField(controller: password, label: 'Confirm your password'),
            const SizedBox(height: 20),
            _SubmitButton(
              label: 'Delete my account',
              busy: busy,
              danger: true,
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setBusy(true);
                try {
                  await ref.read(authProvider.notifier).deleteAccount(password.text);
                  if (context.mounted) context.go('/auth/login');
                } catch (e) {
                  setBusy(false);
                  if (context.mounted) _toast(context, _errorText(e));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared helpers ──────────────────────────────────────────────────────
  void _showActionSheet({
    required BuildContext context,
    required String title,
    required Widget Function(void Function(bool) setBusy, bool busy) builder,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        bool busy = false;
        return StatefulBuilder(
          builder: (ctx, setState) => Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.titleLarge),
                const SizedBox(height: 20),
                builder((v) => setState(() => busy = v), busy),
              ],
            ),
          ),
        );
      },
    );
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _errorText(Object e) {
    if (e is DioException) {
      final detail = e.response?.data;
      if (detail is Map && detail['detail'] is String) return detail['detail'] as String;
    }
    return 'Something went wrong. Please try again.';
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppTheme.glucoseLow : AppTheme.textPrimary;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.bodyLarge.copyWith(color: color, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({required this.controller, required this.label, this.validator});

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      decoration: InputDecoration(labelText: label),
      validator: validator ?? (v) => (v == null || v.isEmpty) ? 'Required' : null,
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.label,
    required this.busy,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: danger ? AppTheme.glucoseLow : AppTheme.accentCyan,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: busy
            ? const SizedBox(
                height: 20, width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label),
      ),
    );
  }
}
