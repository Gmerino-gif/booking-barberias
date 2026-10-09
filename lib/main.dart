import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/network/api_config.dart';
import 'features/auth/providers/auth_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ApiConfig.validateConfiguration();
  final authProvider = AuthProvider();
  runApp(
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => authProvider,
      child: const BookingApp(),
    ),
  );
  unawaited(authProvider.restoreSession());
}
