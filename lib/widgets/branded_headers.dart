import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BrandedPageHeader extends StatelessWidget {
  const BrandedPageHeader({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
  }) : showBrandLogo = false;

  const BrandedPageHeader.brand({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  }) : icon = null,
       showBrandLogo = true;

  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;
  final bool showBrandLogo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final brand = context.brandColors;

    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppGradients.pageHeader(brand)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.84),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: brand.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: showBrandLogo
                  ? Image.asset(
                      'assets/icon/1024x1024_app_icon.png',
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    )
                  : Icon(icon, color: brand.accentDark, size: 27),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.headlineSmall?.copyWith(
                        color: brand.onAccentLight,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      subtitle!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: brand.accentDark,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

class BrandedSectionHeader extends StatelessWidget {
  const BrandedSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.trailing,
    this.prominent = false,
  });

  final String title;
  final IconData icon;
  final Widget? trailing;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final brand = context.brandColors;
    final titleStyle = prominent
        ? textTheme.titleLarge?.copyWith(
            color: brand.onAccentLight,
            fontWeight: FontWeight.w800,
            height: 1.15,
          )
        : textTheme.titleMedium?.copyWith(
            color: brand.onAccentLight,
            fontWeight: FontWeight.w700,
            height: 1.2,
          );

    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppGradients.cardHeader(brand)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, prominent ? 16 : 13, 8, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: prominent ? 40 : 34,
              height: prominent ? 40 : 34,
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(prominent ? 12 : 10),
                border: Border.all(color: brand.outlineVariant),
              ),
              child: Icon(
                icon,
                color: brand.accentDark,
                size: prominent ? 23 : 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: prominent ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
