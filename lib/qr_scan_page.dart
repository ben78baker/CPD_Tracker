import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'utils/attachment_io.dart';
import 'settings_store.dart';
import 'l10n/app_localizations.dart';

class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key, required this.profession});
  final String profession;

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  bool _handled = false;
  bool _showPrompt = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${AppLocalizations.of(context)!.scanQr} – ${widget.profession}',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            tooltip: AppLocalizations.of(context)!.cancel,
          ),
        ],
      ),
      body: MobileScanner(
        onDetect: (capture) async {
          if (_handled) return;
          final code = capture.barcodes.isNotEmpty
              ? capture.barcodes.first.rawValue
              : null;
          if (code != null && code.isNotEmpty) {
            _handled = true;

            // If the QR looks like a direct file link (e.g., PDF/image/doc),
            // offer to attach the file or open the link.
            if (isLikelyFileUrl(code)) {
              if (!mounted) return;
              final action = await showModalBottomSheet<String>(
                context: context,
                showDragHandle: true,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: Text(
                          AppLocalizations.of(ctx)!.detectedDownloadableFile,
                        ),
                        subtitle: Text(
                          AppLocalizations.of(ctx)!.whatWouldYouLikeToDo,
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.download),
                        title: Text(AppLocalizations.of(ctx)!.attachToEntry),
                        subtitle: Text(
                          AppLocalizations.of(ctx)!.downloadAndSave,
                        ),
                        onTap: () => Navigator.pop(ctx, 'attach'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.open_in_new),
                        title: Text(AppLocalizations.of(ctx)!.openLink),
                        onTap: () => Navigator.pop(ctx, 'open'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.link),
                        title: Text(AppLocalizations.of(ctx)!.keepAsUrlOnly),
                        onTap: () => Navigator.pop(ctx, 'keep'),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );

              if (!context.mounted) return;
              switch (action) {
                case 'attach':
                  final saved = await downloadToAppDir(context, code);
                  if (!context.mounted) return; // guard after await
                  if (saved != null) {
                    Navigator.pop(
                      context,
                      saved,
                    ); // return file path to add as attachment
                    return;
                  }
                  // If download failed, fall back to returning the URL
                  Navigator.pop(context, code);
                  return;
                case 'open':
                  await openUrl(context, code);
                  if (!context.mounted) return;
                  Navigator.pop(
                    context,
                    code,
                  ); // also return URL so it's kept with the entry
                  return;
                case 'keep':
                default:
                  if (context.mounted) Navigator.pop(context, code);
                  return;
              }
            }

            // Non-file URL or plain text: show reminder only if user hasn't dismissed it.
            final dismissed = await SettingsStore.instance.isQrHintDismissed();
            if (!context.mounted) return;
            if (!dismissed && _showPrompt) {
              bool dontShowAgain = false;
              final res = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (ctx) {
                  return StatefulBuilder(
                    builder: (ctx, setSt) => AlertDialog(
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(AppLocalizations.of(ctx)!.qrCertificateReminder),
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              AppLocalizations.of(ctx)!.dontShowAgain,
                            ),
                            value: dontShowAgain,
                            onChanged: (val) {
                              setSt(() {
                                dontShowAgain = val ?? false;
                              });
                            },
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(
                              ctx,
                            ).pop(dontShowAgain); // return checkbox state
                          },
                          child: Text(AppLocalizations.of(ctx)!.ok),
                        ),
                      ],
                    ),
                  );
                },
              );
              if (!context.mounted) return;
              if (res == true) {
                setState(() {
                  _showPrompt = false;
                });
                await SettingsStore.instance.setQrHintDismissed(true);
                if (!context.mounted) return;
              }
            }
            Navigator.pop(context, code);
          }
        },
      ),
    );
  }
}
