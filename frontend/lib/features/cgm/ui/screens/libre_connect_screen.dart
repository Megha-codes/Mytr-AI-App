import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/email_field.dart';
import '../../../../core/widgets/password_field.dart';
import '../../models/cgm_connection_state.dart';
import '../../providers/cgm_connection_provider.dart';
import '../widgets/libre_setup_guide.dart';
import '../widgets/cgm_error_card.dart';
import '../widgets/cgm_connected_card.dart';

class LibreConnectScreen extends ConsumerStatefulWidget {
  final String redirectTo;

  const LibreConnectScreen({
    super.key,
    this.redirectTo = '/onboarding/acknowledgement',
  });

  @override
  ConsumerState<LibreConnectScreen> createState() => _LibreConnectScreenState();
}

class _LibreConnectScreenState extends ConsumerState<LibreConnectScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  bool _showForm = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cgmConnectionProvider);

    // If failed, focus on form
    ref.listen(cgmConnectionProvider, (_, next) {
      if (next.status == CgmConnectionStatus.connectionFailed) {
        setState(() {
          _showForm = true;
        });
      }
      if (next.status == CgmConnectionStatus.connected && context.mounted) {
        context.go(widget.redirectTo);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (context.canPop())
                    GestureDetector(
                      onTap: () {
                        ref.read(cgmConnectionProvider.notifier).reset();
                        context.pop();
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Icon(LucideIcons.arrowLeft, color: Colors.white, size: 22),
                      ),
                    ),
                  const Text(
                    'FreeStyle Libre',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Connect via LibreLinkUp sharing platform.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────────
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.status == CgmConnectionStatus.connected && state.connectedInfo != null)
                        CgmConnectedCard(info: state.connectedInfo!)
                      else ...[
                        // Collapsible Setup Guide
                        Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            initiallyExpanded: true,
                            title: const Text(
                              'Setup Guide',
                              style: TextStyle(color: AppColors.nearBlack, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            leading: const Icon(LucideIcons.bookOpen, color: AppColors.cyan, size: 20),
                            childrenPadding: const EdgeInsets.only(bottom: 16),
                            children: const [LibreSetupGuide()],
                          ),
                        ),
                        
                        if (!_showForm) ...[
                          const SizedBox(height: 12),
                          PrimaryButton(
                            text: 'I\'m ready →',
                            variant: ButtonVariant.primary,
                            onPressed: () => setState(() => _showForm = true),
                          ),
                        ],

                        if (_showForm) ...[
                          const SizedBox(height: 24),
                          const Text(
                            'ENTER CREDENTIALS',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1),
                          ),
                          const SizedBox(height: 12),
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                EmailField(controller: _emailController),
                                const SizedBox(height: 12),
                                PasswordField(controller: _passwordController),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _PrivacyNote(),
                          const SizedBox(height: 24),
                          PrimaryButton(
                            text: 'Connect Libre account',
                            variant: ButtonVariant.secondary,
                            isLoading: state.isLoading,
                            onPressed: state.isLoading ? null : _submit,
                          ),
                        ],
                      ],

                      if (state.status == CgmConnectionStatus.connectionFailed && state.error != null) ...[
                        const SizedBox(height: 16),
                        CgmErrorCard(
                          error: state.error!,
                          onRetry: _submit,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password.')),
      );
      return;
    }

    ref.read(cgmConnectionProvider.notifier).connectLibre(email, password);
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.shieldCheck, color: AppColors.cyan, size: 14),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your password is never stored. We only store an encrypted token in AWS Secrets Manager.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 8, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
