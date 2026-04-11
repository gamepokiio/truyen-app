import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authProvider);

    authAsync.whenData((auth) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.go('/home');
      });
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_rounded, size: 72, color: Color(0xFF22D3EE)),
            const SizedBox(height: 16),
            const Text(
              'TruyenCV',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 40),
            if (authAsync.isLoading)
              const CircularProgressIndicator(color: Color(0xFF22D3EE)),
          ],
        ),
      ),
    );
  }
}
