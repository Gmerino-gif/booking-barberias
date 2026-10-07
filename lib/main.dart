import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'features/auth/providers/auth_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authProvider = AuthProvider();
  await authProvider.restoreSession();
  runApp(
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => authProvider,
      child: const BookingApp(),
    ),
  );
}
