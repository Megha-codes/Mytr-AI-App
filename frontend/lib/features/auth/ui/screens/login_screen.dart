import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final String? prefillEmail;
  const LoginScreen({super.key, this.prefillEmail});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  final _passwordFocusNode = FocusNode();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.prefillEmail != null && widget.prefillEmail!.isNotEmpty) {
      _emailController.text = widget.prefillEmail!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _passwordFocusNode.requestFocus();
      });
    }
    _emailController.addListener(_clearError);
    _passwordController.addListener(_clearError);
  }

  void _clearError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authProvider.notifier).login(
        _emailController.text.trim(),
        _passwordController.text,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 401) {
        setState(() => _errorMessage = 'Incorrect email or password');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection failed. Check your internet.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection failed. Check your internet.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              Text(
                'Welcome Back',
                style: AppTheme.titleLarge.copyWith(fontSize: 32),
              ),
              const SizedBox(height: 12),
              Text(
                'Sign in to continue your metabolic journey.',
                style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 48),
              
              _buildField('Email Address', LucideIcons.mail, _emailController),
              const SizedBox(height: 24),
              _buildField('Password', LucideIcons.lock, _passwordController, isPassword: true, focusNode: _passwordFocusNode),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],

              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () {
                    // TODO: Implement forgot password
                  },
                  child: Text(
                    'Forgot password?',
                    style: TextStyle(color: AppTheme.brandGreen, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.brandGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isLoading 
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Sign In', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              
              const SizedBox(height: 24),
              Center(
                child: GestureDetector(
                  onTap: () => context.go('/onboarding/intro'),
                  child: RichText(
                    text: TextSpan(
                      text: "Don't have an account? ",
                      style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                      children: [
                        TextSpan(
                          text: 'Sign up',
                          style: TextStyle(color: AppTheme.brandGreen, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, IconData icon, TextEditingController controller, {bool isPassword = false, FocusNode? focusNode}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.labelSmall),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: isPassword,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 20, color: AppTheme.textSecondary),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
