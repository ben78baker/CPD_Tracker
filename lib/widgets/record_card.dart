import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models.dart';

/// A reusable card for rendering a single CPD entry.
///
/// Usage in a list:
/// ```dart
/// RecordCard(
///   entry: e,
///   dateFormat: _fmt, // e.g. from settings
///   onEdit: () => _edit(e),
///   onDelete: () => _delete(e),
///   onViewAttachments: () => _showAttachments(e),
///   onShareAll: () => shareAllAttachments(context, e.attachments),
/// )
/// ```
class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.entry,
    required this.dateFormat,
    this.onEdit,
    this.onDelete,
    this.onViewAttachments,
    this.onShareAll,
    this.elevation,
    this.margin,
    this.showAttachmentsButton = true,
  });

  final CpdEntry entry;
  final String dateFormat;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onViewAttachments;
  final VoidCallback? onShareAll;
  final double? elevation;
  final EdgeInsetsGeometry? margin;
  final bool showAttachmentsButton;

  String _formatDate(DateTime d) {
    try {
      return DateFormat(dateFormat).format(d);
    } catch (_) {
      // Fallback to a locale-aware short date instead of a hard-coded pattern
      return DateFormat.yMd().format(d);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _formatDate(entry.date);
    final hasAttachments = entry.attachments.isNotEmpty;

    return Card(
      elevation: elevation ?? 1.5,
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row + overflow menu
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    entry.title.isEmpty
                        ? AppLocalizations.of(context)!.noTitle
                        : entry.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) {
                      if (v == 'edit') {
                        onEdit?.call();
                      } else if (v == 'delete') {
                        onDelete?.call();
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(AppLocalizations.of(ctx)!.edit),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: const Icon(Icons.delete_outline),
                          title: Text(AppLocalizations.of(ctx)!.delete),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Date + Duration
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _Chip(icon: Icons.event, label: dateStr),
                _Chip(
                  icon: Icons.timer_outlined,
                  label: _formatDuration(context, entry.hours, entry.minutes),
                ),
              ],
            ),

            if (entry.details.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                entry.details,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],

            if (showAttachmentsButton && hasAttachments) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: onViewAttachments,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      AppLocalizations.of(
                        context,
                      )!.attachmentsCount(entry.attachments.length),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (onShareAll != null)
                    IconButton(
                      tooltip: AppLocalizations.of(
                        context,
                      )!.shareAllAttachments,
                      icon: const Icon(Icons.ios_share),
                      onPressed: onShareAll,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatDuration(BuildContext context, int h, int m) {
    final loc = AppLocalizations.of(context)!;

    if (h == 0 && m == 0) {
      return loc.zeroMinutes;
    }

    final parts = <String>[];
    if (h > 0) {
      parts.add(loc.hoursPlural(h));
    }
    if (m > 0) {
      parts.add(loc.minutesPlural(m));
    }

    return parts.join(' ');
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 6), Text(label)],
      ),
    );
  }
}
