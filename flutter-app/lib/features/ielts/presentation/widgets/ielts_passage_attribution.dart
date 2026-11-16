import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/ielts_entities.dart';

typedef IeltsLinkOpener = Future<bool> Function(Uri uri);

Future<bool> _openExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// The credit a CC BY-SA passage requires wherever it is shown to a learner.
class IeltsPassageAttribution extends StatelessWidget {
  final IeltsPart part;
  final IeltsLinkOpener openLink;

  const IeltsPassageAttribution({
    super.key,
    required this.part,
    this.openLink = _openExternally,
  });

  static String licenseName(String id) {
    if (id.startsWith('LicenseRef-') && id.contains('Public-Domain')) {
      return 'ielts.publicDomain'.tr();
    }
    return id.replaceAll('-', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final linkStyle = TextButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: theme.textTheme.bodySmall,
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    final attribution = part.attribution?.trim();
    final licenseId = part.licenseId;
    final licenseLink = Uri.tryParse(part.licenseUrl ?? '');
    final sourceLink = Uri.tryParse(part.sourceUrl ?? '');

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (attribution != null && attribution.isNotEmpty)
            Text('${'ielts.sourceLine'.tr()} $attribution.', style: style),
          if (licenseId != null) ...[
            const SizedBox(width: 4),
            Text('ielts.licensedUnder'.tr(), style: style),
            if (licenseLink != null && licenseLink.hasScheme)
              TextButton(
                style: linkStyle,
                onPressed: () => openLink(licenseLink),
                child: Text(licenseName(licenseId)),
              )
            else
              Text(' ${licenseName(licenseId)}.', style: style),
          ],
          if (sourceLink != null && sourceLink.hasScheme)
            TextButton(
              style: linkStyle,
              onPressed: () => openLink(sourceLink),
              child: Text('ielts.viewSource'.tr()),
            ),
          if (part.adapted) Text('ielts.adaptedNotice'.tr(), style: style),
        ],
      ),
    );
  }
}
