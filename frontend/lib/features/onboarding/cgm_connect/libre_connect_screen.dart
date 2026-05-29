import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/connect_explainer_card.dart';
import '../../../core/widgets/email_field.dart';
import '../../../core/widgets/password_field.dart';
import '../../../core/widgets/primary_button.dart';
import 'cgm_connect_provider.dart';

class LibreConnectScreen extends ConsumerStatefulWidget {
  const LibreConnectScreen({super.key});

  @override
  ConsumerState<LibreConnectScreen> createState() => _LibreConnectScreenState();
}

class _LibreConnectScreenState extends ConsumerState<LibreConnectScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cgmConnectProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Connect FreeStyle Libre')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ConnectExplainerCard(
                icon: Icon(Icons.sensors, size: 64, color: Colors.green),
                title: 'Connect your FreeStyle Libre',
                points: [
                  'Enter your LibreLinkUp account credentials',
                  'Your password is encrypted — we never store it in plain text',
                  'Requires LibreLinkUp Connections to be enabled in your Libre app',
                  'You can disconnect at any time from Profile settings',
                ],
              ),
              const SizedBox(height: 16),
              const _LibreSetupGuideCard(),
              const SizedBox(height: 24),
              EmailField(controller: _emailController),
              const SizedBox(height: 12),
              PasswordField(controller: _passwordController),
              const SizedBox(height: 24),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    state.error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              PrimaryButton(
                text: 'Connect Libre account',
                isLoading: state.isLoading,
                onPressed: () => _connectLibre(context),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/onboarding/cgm-select'),
                child: const Text('Choose a different device'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _connectLibre(BuildContext context) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email and password.')),
      );
      return;
    }

    final result = await ref
        .read(cgmConnectProvider.notifier)
        .connectLibre(email: email, password: password);

    if (result.success && context.mounted) {
      context.go('/onboarding/lifestyle-baseline');
    } else if (!result.success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              result.errorMessage ?? 'Failed to connect. Please try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

// ── Setup guide ──────────────────────────────────────────────────────────────

class _LibreSetupGuideCard extends StatelessWidget {
  const _LibreSetupGuideCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: const ExpansionTile(
        title: Text('How to set up LibreLinkUp (required)'),
        childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _SetupStep(number: 1, text: 'Open your FreeStyle LibreLink app'),
          _SetupStep(
              number: 2, text: 'Go to Menu → Connected Apps → LibreLinkUp'),
          _SetupStep(
              number: 3, text: 'Create a LibreLinkUp account or sign in'),
          _SetupStep(
            number: 4,
            text: 'Enable Connections — this allows Mytr.AI to read your data',
          ),
          _SetupStep(
            number: 5,
            text: 'Come back here and enter your LibreLinkUp credentials',
          ),
        ],
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.green.withValues(alpha: 0.2),
            child: Text(
              '$number',
              style: const TextStyle(fontSize: 12, color: Colors.green),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
