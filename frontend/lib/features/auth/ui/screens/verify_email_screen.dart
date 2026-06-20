import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';

/// Dual-purpose screen:
///  • With a [token] (from the verification deep link) it confirms the email.
///  • Without a token it prompts the user to check their inbox and resend.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  final String? token;

  const VerifyEmailScreen({super.key, this.token});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

enum _Phase { prompt, verifying, verified, failed }

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  late _Phase _phase;
  bool _resending = false;
  String? _message;

  bool get _hasToken => widget.token != null && widget.token!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _phase = _hasToken ? _Phase.verifying : _Phase.prompt;
    if (_hasToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
    }
  }

  Future<void> _verify() async {
    setState(() => _phase = _Phase.verifying);
    try {
      await ref.read(authProvider.notifier).verifyEmail(widget.token!);
      if (mounted) setState(() => _phase = _Phase.verified);
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map ? e.response?.data['detail'] as String? : null;
      setState(() {
        _phase = _Phase.failed;
        _message = detail ?? 'This verification link is invalid or has expired.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _message = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _message = null;
    });
    try {
      await ref.read(authProvider.notifier).sendVerificationEmail();
      if (mounted) setState(() => _message = 'Verification email sent. Check your inbox.');
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _message = e.response?.statusCode == 429
          ? 'Please wait a moment before requesting another email.'
          : 'Could not send the email. Check your connection.');
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not send the email. Check your connection.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: _buildContent(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent() {
    switch (_phase) {
      case _Phase.verifying:
        return const [
          Center(child: CircularProgressIndicator(color: AppTheme.brandGreen)),
          SizedBox(height: 24),
          Text('Verifying your email…', textAlign: TextAlign.center),
        ];
      case _Phase.verified:
        return [
          Icon(LucideIcons.checkCircle, size: 56, color: AppTheme.brandGreen),
          const SizedBox(height: 24),
          Text('Email verified', textAlign: TextAlign.center, style: AppTheme.titleLarge.copyWith(fontSize: 28)),
          const SizedBox(height: 12),
          Text("You're all set.", textAlign: TextAlign.center, style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: 32),
          _primaryButton('Continue', () => context.go('/home')),
        ];
      case _Phase.failed:
        return [
          Icon(LucideIcons.alertCircle, size: 56, color: Colors.red),
          const SizedBox(height: 24),
          Text('Verification failed', textAlign: TextAlign.center, style: AppTheme.titleLarge.copyWith(fontSize: 28)),
          const SizedBox(height: 12),
          Text(_message ?? '', textAlign: TextAlign.center, style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: 32),
          _primaryButton(_resending ? 'Sending…' : 'Resend verification email', _resending ? null : _resend),
          const SizedBox(height: 12),
          _textButton('Skip for now', () => context.go('/home')),
        ];
      case _Phase.prompt:
        return [
          Icon(LucideIcons.mailCheck, size: 56, color: AppTheme.brandGreen),
          const SizedBox(height: 24),
          Text('Verify your email', textAlign: TextAlign.center, style: AppTheme.titleLarge.copyWith(fontSize: 28)),
          const SizedBox(height: 12),
          Text(
            "We've sent a verification link to your email. Open it to confirm your address.",
            textAlign: TextAlign.center,
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.brandGreen, fontSize: 13)),
          ],
          const SizedBox(height: 32),
          _primaryButton(_resending ? 'Sending…' : 'Resend email', _resending ? null : _resend),
          const SizedBox(height: 12),
          _textButton('Skip for now', () => context.go('/home')),
        ];
    }
  }

  Widget _primaryButton(String text, VoidCallback? onPressed) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.brandGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _textButton(String text, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      child: Text(text, style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
    );
  }
}
