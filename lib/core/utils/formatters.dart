/// Shared parsing/formatting helpers so every screen shows dates, times and
/// prices in exactly the same way.
class AppFormatters {
  const AppFormatters._();

  static const List<String> _weekdays = [
    'Lun',
    'Mar',
    'Mié',
    'Jue',
    'Vie',
    'Sáb',
    'Dom',
  ];

  static const List<String> _months = [
    'Ene',
    'Feb',
    'Mar',
    'Abr',
    'May',
    'Jun',
    'Jul',
    'Ago',
    'Sep',
    'Oct',
    'Nov',
    'Dic',
  ];

  /// Parses an ISO-8601 timestamp coming from the API and converts it to the
  /// device's local time zone.
  ///
  /// The backend stores the absolute instant (UTC) plus the client's UTC
  /// offset; without converting to local time a 12:00 PM reservation would be
  /// rendered shifted by the offset difference.
  static DateTime? parseApiDateTime(dynamic raw) {
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw.toString());
    return parsed?.toLocal();
  }

  /// `Lun 3 Mar` or `Lun 3 Mar 2025`.
  static String date(DateTime date, {bool includeYear = true}) {
    final local = date.toLocal();
    final base =
        '${_weekdays[local.weekday - 1]} ${local.day} ${_months[local.month - 1]}';
    return includeYear ? '$base ${local.year}' : base;
  }

  /// `HH:mm` in the device's local time zone.
  static String time(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// `12:00 PM` — etiqueta de hora usada por los selectores de horarios.
  static String hourLabel(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '${hour.toString().padLeft(2, '0')}:$minute '
        '${local.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// Etiqueta en español para el estado de una reserva.
  static String statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pendiente';
      case 'confirmed':
        return 'Confirmada';
      case 'completed':
        return 'Completada';
      case 'cancelled':
      case 'canceled':
        return 'Cancelada';
      case 'no_show':
        return 'No asistió';
      default:
        return status;
    }
  }

  /// `$25.000` (Colombian thousands separator).
  static String currency(int value) {
    final negative = value < 0;
    final raw = value.abs().toString();
    final buffer = StringBuffer();
    for (var index = 0; index < raw.length; index++) {
      if (index > 0 && (raw.length - index) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(raw[index]);
    }
    return '${negative ? '-' : ''}\$$buffer';
  }
}
