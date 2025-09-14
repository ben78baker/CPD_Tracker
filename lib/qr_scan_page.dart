import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'utils/attachment_io.dart';

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
        title: Text('Scan QR – ${widget.profession}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Cancel',
          ),
        ],
      ),
      body: MobileScanner(
        onDetect: (capture) async {
          if (_handled) return;
          final code = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
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
                      const ListTile(
                        title: Text('Detected a downloadable file link'),
                        subtitle: Text('What would you like to do?'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.download),
                        title: const Text('Attach to this entry'),
                        subtitle: Text('Download and save to Attachments'),
                        onTap: () => Navigator.pop(ctx, 'attach'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.open_in_new),
                        title: const Text('Open link'),
                        onTap: () => Navigator.pop(ctx, 'open'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.link),
                        title: const Text('Keep as URL only'),
                        onTap: () => Navigator.pop(ctx, 'keep'),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );

              if (!mounted) return;
              switch (action) {
                case 'attach':
                  final saved = await downloadToAppDir(context, code);
                  if (saved != null && mounted) {
                    Navigator.pop(context, saved); // return file path to add as attachment
                    return;
                  }
                  // If download failed, fall back to returning the URL
                  if (mounted) Navigator.pop(context, code);
                  return;
                case 'open':
                  await openUrl(context, code);
                  if (mounted) Navigator.pop(context, code); // also return URL so it's kept with the entry
                  return;
                case 'keep':
                default:
                  if (mounted) Navigator.pop(context, code);
                  return;
              }
            }

            // Non-file URL or plain text: show reminder (once), then return the code.
            if (_showPrompt) {
              bool dontShowAgain = false;
              await showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) {
                  return StatefulBuilder(
                    builder: (context, setState) => AlertDialog(
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "To receive any CPD certificate please follow the link from the scanned QR code at your leisure and add the certificate to this record."
                          ),
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text("Don't show this message again"),
                            value: dontShowAgain,
                            onChanged: (val) {
                              setState(() {
                                dontShowAgain = val ?? false;
                              });
                            },
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            if (dontShowAgain) {
                              setState(() { _showPrompt = false; });
                            }
                            Navigator.of(context).pop();
                          },
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              );
            }
            if (mounted) Navigator.pop(context, code);
          }
        },
      ),
    );
  }
}