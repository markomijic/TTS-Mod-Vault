import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Bytes in a mebibyte.
const int _mib = 1024 * 1024;

/// Bytes in a gibibyte.
const int _gib = 1024 * _mib;

/// [bytes] as "12.3 MB", or "1.25 GB" from one gibibyte up.
String formatByteSize(AppLocalizations l10n, int bytes) {
  if (bytes >= _gib) {
    return l10n.sizeGigabytes((bytes / _gib).toStringAsFixed(2));
  }
  return l10n.sizeMegabytes((bytes / _mib).toStringAsFixed(1));
}
