import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// The production Home chrome. Hosts supply the navigation and data actions.
class HomeShell extends StatelessWidget {
  const HomeShell({
    super.key,
    required this.onSearch,
    required this.onMenuSelected,
    required this.body,
  });

  final VoidCallback onSearch;
  final ValueChanged<String> onMenuSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final brand = context.brandColors;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        backgroundColor: AppColors.canvas,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: brand.outlineVariant),
        ),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/icon/1024x1024_app_icon.png',
                key: const ValueKey('home-brand-logo'),
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  AppLocalizations.of(context)!.appTitle,
                  key: const ValueKey('home-app-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: brand.onAccentLight,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('home-search-action'),
            tooltip: 'Search all records',
            style: _homeHeaderActionStyle(context),
            icon: const Icon(Icons.search_rounded),
            onPressed: onSearch,
          ),
          PopupMenuButton<String>(
            key: const ValueKey('home-menu-action'),
            tooltip: AppLocalizations.of(context)!.menuTooltip,
            icon: const Icon(Icons.more_vert_rounded),
            style: _homeHeaderActionStyle(context),
            onSelected: onMenuSelected,
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'add_profession',
                child: Text(AppLocalizations.of(ctx)!.addProfession),
              ),
              PopupMenuItem(
                value: 'edit_details',
                child: Text(AppLocalizations.of(ctx)!.editPersonalDetails),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Text(AppLocalizations.of(ctx)!.settings),
              ),
              PopupMenuItem(
                value: 'deleted_records',
                child: Text(AppLocalizations.of(ctx)!.deletedRecordsTitle),
              ),
              PopupMenuItem(
                value: 'view_deleted',
                child: Text(AppLocalizations.of(ctx)!.viewDeletedProfessions),
              ),
            ],
          ),
        ],
      ),
      body: body,
    );
  }
}

class HomeProfessionList extends StatelessWidget {
  const HomeProfessionList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => itemCount == 0
      ? Center(child: Text(AppLocalizations.of(context)!.noProfessionsYet))
      : ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          itemCount: itemCount,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: itemBuilder,
        );
}

ButtonStyle _homeHeaderActionStyle(BuildContext context) {
  final brand = context.brandColors;
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size.square(48)),
    maximumSize: const WidgetStatePropertyAll(Size.square(48)),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    foregroundColor: WidgetStatePropertyAll(brand.accentDark),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return brand.accentLight;
      }
      return Colors.transparent;
    }),
    overlayColor: WidgetStatePropertyAll(brand.accent.withValues(alpha: 0.08)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
