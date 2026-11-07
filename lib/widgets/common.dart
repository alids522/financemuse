import 'package:flutter/material.dart';

import '../services/supabase_client.dart';
import '../theme/app_theme.dart';
import '../utils/money_period.dart';

/// Notice shown when the financemuse schema is not exposed via PostgREST
/// yet. Data is never faked — screens show this instead of empty data.
class SchemaNotice extends StatelessWidget {
  const SchemaNotice({super.key, this.failure});
  final SupabaseFailure? failure;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: context.finance.warning),
                const SizedBox(width: AppSpacing.s8),
                const Expanded(
                  child: Text(
                    'Data belum dapat dimuat dari server',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            const Text(
              'Skema financemuse belum diekspos melalui PostgREST API. '
              'Layanan data sudah terimplementasi, tetapi panggilan API '
              'gagal sampai eksposur skema diputuskan di server. '
              'Tidak ada data contoh yang ditampilkan.',
            ),
            if (failure != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                'Detail teknis: ${failure!.message}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ConfigNotice extends StatelessWidget {
  const ConfigNotice({super.key});

  @override
  Widget build(BuildContext context) {
    if (SupabaseConfig.isConfigured) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Row(
          children: [
            Icon(Icons.settings_outlined,
                color: context.finance.warning),
            const SizedBox(width: AppSpacing.s8),
            const Expanded(
              child: Text(
                'Konfigurasi belum lengkap: SUPABASE_ANON_KEY tidak '
                'disediakan (--dart-define). Login dan data tidak akan '
                'berfungsi sampai kunci disediakan.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MoneyText extends StatelessWidget {
  const MoneyText(this.minor,
      {super.key, this.signed = false, this.style, this.compact = false});
  final int minor;
  final bool signed;
  final TextStyle? style;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = signed
        ? Money.formatSigned(minor)
        : Money.formatIdr(minor, compact: compact);
    final color = minor > 0
        ? context.finance.positive
        : (minor < 0 ? context.finance.negative : null);
    return Text(
      text,
      style: (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
        color: signed ? color : null,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.valueMinor,
    this.signed = false,
    this.subLabel,
  });
  final String label;
  final int valueMinor;
  final bool signed;
  final String? subLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.s4),
            MoneyText(valueMinor,
                signed: signed,
                style: Theme.of(context).textTheme.titleSmall),
            if (subLabel != null) ...[
              const SizedBox(height: AppSpacing.s4),
              Text(subLabel!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// Day / Week / Month / Year period switcher (PRD §5.5).
class PeriodSwitcher extends StatelessWidget {
  const PeriodSwitcher({
    super.key,
    required this.currentKind,
    required this.period,
    required this.onChanged,
  });
  final String currentKind;
  final PeriodRange period;
  final void Function(String kind, PeriodRange range) onChanged;

  @override
  Widget build(BuildContext context) {
    const kinds = ['day', 'week', 'month', 'year'];
    const labels = {'day': 'Hari', 'week': 'Minggu', 'month': 'Bulan', 'year': 'Tahun'};
    final now = JakartaTime.now();
    return Wrap(
      spacing: AppSpacing.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...kinds.map((k) => ChoiceChip(
              label: Text(labels[k]!),
              selected: currentKind == k,
              onSelected: (_) {
                final range = switch (k) {
                  'day' => Periods.day(now),
                  'week' => Periods.week(now),
                  'year' => Periods.year(now.year),
                  _ => Periods.month(now.year, now.month),
                };
                onChanged(k, range);
              },
            )),
        Text(period.label,
            style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

void showSnack(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError
          ? Theme.of(context).colorScheme.error
          : null,
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Ya, lanjutkan',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
