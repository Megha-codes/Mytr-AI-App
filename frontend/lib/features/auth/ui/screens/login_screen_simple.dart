import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LoginScreenSimple extends StatefulWidget {
  const LoginScreenSimple({super.key});

  @override
  State<LoginScreenSimple> createState() => _LoginScreenSimpleState();
}

class _LoginScreenSimpleState extends State<LoginScreenSimple> {
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Sign In'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                print('Email: ${_emailController.text}');
                print('Password: ${_passwordController.text}');
              },
              child: const Text('Sign In'),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => context.go('/onboarding/intro'),
              child: const Text('Back to Intro'),
            ),
          ],
        ),
      ),
    );
  }
}