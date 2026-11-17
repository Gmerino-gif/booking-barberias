import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/network/api_config.dart';
import 'core/notifications/push_notification_service.dart';
import 'features/auth/providers/auth_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ApiConfig.validateConfiguration();
  if (PushNotificationService.isSupportedPlatform) {
    await Firebase.initializeApp();
    PushNotificationService.registerBackgroundHandler();
  }

  final authProvider = AuthProvider();
  runApp(
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => authProvider,
      child: const BookingApp(),
    ),
  );
  unawaited(authProvider.restoreSession());
  if (PushNotificationService.isSupportedPlatform) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(PushNotificationService.initialize());
    });
  }
}
