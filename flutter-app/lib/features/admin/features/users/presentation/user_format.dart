/// `dd/MM/yyyy`, or [fallback] when [value] is empty or not a date.
String formatAdminDate(String? value, {String fallback = '—'}) {
  final date = DateTime.tryParse(value ?? '')?.toLocal();
  if (date == null) return fallback;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}

/// `dd/MM/yyyy HH:mm`, or [fallback].
String formatAdminDateTime(String? value, {String fallback = '—'}) {
  final date = DateTime.tryParse(value ?? '')?.toLocal();
  if (date == null) return fallback;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${formatAdminDate(value)} ${two(date.hour)}:${two(date.minute)}';
}

/// `+12` / `-3`, so a ledger shows direction at a glance.
String signedAmount(int amount) => amount > 0 ? '+$amount' : '$amount';
