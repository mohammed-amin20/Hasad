import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class HasadLogo extends StatelessWidget {
  const HasadLogo({super.key, this.size = 48, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    onDark ? 'logo/hasad-logo-icon.svg' : 'logo/hasad-logo-icon-navy.svg',
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticsLabel: 'شعار حصاد',
  );
}

class HasadBrandLockup extends StatelessWidget {
  const HasadBrandLockup({
    super.key,
    this.compact = false,
    this.onDark = false,
  });

  final bool compact;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final textColor = onDark ? Colors.white : const Color(0xFF132038);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HasadLogo(size: compact ? 38 : 46, onDark: onDark),
        if (!compact) ...[
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'حصاد',
                style: TextStyle(
                  color: textColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'ERP',
                style: TextStyle(
                  color: textColor.withValues(alpha: .64),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
