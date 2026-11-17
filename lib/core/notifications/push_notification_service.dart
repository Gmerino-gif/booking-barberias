import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!PushNotificationService.isSupportedPlatform) return;
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService._();

  static bool _initialized = false;
  static bool _backgroundHandlerRegistered = false;
  static String? _currentToken;

  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static final StreamController<String> _tokenRefreshes =
      StreamController<String>.broadcast();
  static final StreamController<RemoteMessage> _foregroundMessages =
      StreamController<RemoteMessage>.broadcast();
  static final StreamController<RemoteMessage> _notificationOpens =
      StreamController<RemoteMessage>.broadcast();

  /// The current device token, available for registration with the signed-in user.
  static String? get currentToken => _currentToken;

  static Stream<String> get tokenRefreshes => _tokenRefreshes.stream;
  static Stream<RemoteMessage> get foregroundMessages =>
      _foregroundMessages.stream;
  static Stream<RemoteMessage> get notificationOpens =>
      _notificationOpens.stream;

  static void registerBackgroundHandler() {
    if (!isSupportedPlatform || _backgroundHandlerRegistered) return;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _backgroundHandlerRegistered = true;
  }

  static Future<void> initialize() async {
    if (!isSupportedPlatform || _initialized) return;
    _initialized = true;
    registerBackgroundHandler();

    final messaging = FirebaseMessaging.instance;
    FirebaseMessaging.onMessage.listen(
      _foregroundMessages.add,
      onError: (Object error) =>
          debugPrint('Firebase foreground message listener failed: $error'),
    );
    FirebaseMessaging.onMessageOpenedApp.listen(
      _notificationOpens.add,
      onError: (Object error) =>
          debugPrint('Firebase notification-open listener failed: $error'),
    );
    // Keep the FCM token API for backend registration of this device.
    // ignore: deprecated_member_use
    messaging.onTokenRefresh.listen(
      (token) {
        _currentToken = token;
        _tokenRefreshes.add(token);
      },
      onError: (Object error) =>
          debugPrint('Firebase token refresh listener failed: $error'),
    );

    try {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Firebase notification permission request failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    try {
      // The app stores the FCM token for optional user/business association.
      // ignore: deprecated_member_use
      _currentToken = await messaging.getToken();
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Firebase Messaging token request failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    try {
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _notificationOpens.add(initialMessage);
      }
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Firebase launch message retrieval failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
