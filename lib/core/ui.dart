import 'package:flutter/material.dart';

class Spacing {
  static const xxs = 4.0;
  static const xs = 6.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
}

class R {
  static BorderRadius br8 = BorderRadius.circular(8);
  static BorderRadius br12 = BorderRadius.circular(12);
  static BorderRadius br16 = BorderRadius.circular(16);
}

String relativeTimeString(DateTime when, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(when);
  if (diff.inSeconds < 60) return 'hace ${diff.inSeconds}s';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
  if (diff.inHours < 24) return 'hace ${diff.inHours}h';
  if (diff.inDays == 1) return 'ayer';
  if (diff.inDays < 7) return 'hace ${diff.inDays}d';

  final d = when.toLocal();
  final two = (int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

class MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const MetaChip({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: R.br12,
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: c, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
