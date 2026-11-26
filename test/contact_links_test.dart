import 'package:booking_app/core/utils/contact_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppContactLinks.normalizeColombianPhone', () {
    test('adds the 57 country code to a 10-digit mobile number', () {
      expect(
        AppContactLinks.normalizeColombianPhone('3001234567'),
        '573001234567',
      );
    });

    test('strips spaces, dashes, parentheses and the plus sign', () {
      expect(
        AppContactLinks.normalizeColombianPhone('+57 300-123 45 67'),
        '573001234567',
      );
      expect(
        AppContactLinks.normalizeColombianPhone('(300) 123 4567'),
        '573001234567',
      );
    });

    test('accepts the 00 international prefix', () {
      expect(
        AppContactLinks.normalizeColombianPhone('0057 300 123 4567'),
        '573001234567',
      );
    });

    test('returns null for empty, missing or unusable numbers', () {
      expect(AppContactLinks.normalizeColombianPhone(null), isNull);
      expect(AppContactLinks.normalizeColombianPhone('   '), isNull);
      expect(AppContactLinks.normalizeColombianPhone('sin teléfono'), isNull);
      expect(AppContactLinks.normalizeColombianPhone('12345'), isNull);
    });
  });

  test('builds a tel: link with the normalized number', () {
    expect(
      AppContactLinks.telUri('573001234567').toString(),
      'tel:+573001234567',
    );
  });

  test('builds a wa.me link with the encoded initial message', () {
    final uri = AppContactLinks.whatsAppUri(
      '573001234567',
      message: 'Hola Ismael, ¿confirmas tu cita?',
    );

    expect(uri.host, 'wa.me');
    expect(uri.pathSegments.single, '573001234567');
    // El texto viaja codificado para que los espacios y signos no rompan el
    // enlace (`%20` en lugar de `+`).
    expect(uri.query, contains('%20'));
    expect(uri.queryParameters['text'], 'Hola Ismael, ¿confirmas tu cita?');
  });

  test('omits the query string when there is no message', () {
    final uri = AppContactLinks.whatsAppUri('573001234567', message: '  ');

    expect(uri.toString(), 'https://wa.me/573001234567');
  });
}
