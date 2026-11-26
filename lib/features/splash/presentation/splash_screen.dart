import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _redirectTimer;

  @override
  void initState() {
    super.initState();
    _redirectTimer = Timer(const Duration(seconds: 1), _check);
  }

  void _check() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.status == AuthStatus.unknown) {
      _redirectTimer = Timer(const Duration(milliseconds: 300), _check);
      return;
    }
    if (auth.isAuthenticated) {
      if (auth.isBusiness) {
        context.go('/business');
      } else {
        context.go('/client');
      }
    } else {
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.content_cut, size: 80, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text('Booking App', style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.xl),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
