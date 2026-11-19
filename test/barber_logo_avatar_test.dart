import 'package:booking_app/features/client/presentation/widgets/barber_logo_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses the scissors icon for missing or invalid logo URLs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            BarberLogoAvatar(logoUrl: null),
            BarberLogoAvatar(logoUrl: '   '),
            BarberLogoAvatar(logoUrl: 'ftp://example.com/logo.png'),
          ],
        ),
      ),
    );

    expect(find.byIcon(Icons.content_cut), findsNWidgets(3));
  });

  testWidgets('falls back to the scissors icon when the network image fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BarberLogoAvatar(logoUrl: 'https://example.com/logo.png'),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byIcon(Icons.content_cut), findsOneWidget);
  });
}
