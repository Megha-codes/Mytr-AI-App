import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config.dart';
import '../../../core/widgets/connect_explainer_card.dart';
import '../../../core/widgets/primary_button.dart';
import 'cgm_connect_provider.dart';

class DexcomConnectScreen extends ConsumerWidget {
  const DexcomConnectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cgmConnectProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Connect Dexcom')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const ConnectExplainerCard(
                icon: Icon(Icons.monitor_heart, size: 64, color: Colors.teal),
                title: 'Connect your Dexcom',
                points: [
                  'Mytr.AI will read your glucose readings automatically',
                  'We never store your Dexcom password',
                  'You can disconnect at any time from Profile settings',
                  'Requires Dexcom Share to be enabled in your Dexcom app',
                ],
              ),
              const Spacer(),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              PrimaryButton(
                text: 'Connect Dexcom account',
                isLoading: state.isLoading,
                onPressed: () => _launchDexcomOAuth(context, ref),
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

  Future<void> _launchDexcomOAuth(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final authUrl = Uri(
      scheme: 'https',
      host: AppConfig.dexcomApiHost,
      path: AppConfig.dexcomOAuthPath,
      queryParameters: {
        'client_id': AppConfig.dexcomClientId,
        'redirect_uri': AppConfig.dexcomRedirectUri,
        'response_type': 'code',
        'scope': 'offline_access',
      },
    );

    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: AppConfig.dexcomCallbackScheme,
      );
    } catch (_) {
      // User cancelled the OAuth flow
      return;
    }

    final code = Uri.parse(result).queryParameters['code'];
    if (code == null) return;

    final success =
        await ref.read(cgmConnectProvider.notifier).exchangeDexcomCode(code);

    if (success && context.mounted) {
      context.go('/onboarding/lifestyle-baseline');
    }
  }
}
