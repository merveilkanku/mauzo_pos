import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

Future<void> showShiftReport(BuildContext context) {
  final counted = TextEditingController();
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final by = app.byMethod;
        final expected = app.openingFloat + (by[PayMethod.cashUsd] ?? 0);
        final c = double.tryParse(counted.text.replaceAll(',', '.'));
        return AlertDialog(
          title: const Text('Clôture de caisse (rapport Z)'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              kv('Tickets', '${app.sales.length}'),
              for (final m in PayMethod.values) kv(m.label, usd(by[m] ?? 0)),
              const Divider(),
              kv('Total des ventes', usd(app.todayTotal), strong: true),
              kv('Fond de caisse', usd(app.openingFloat)),
              kv('Espèces USD attendues', usd(expected), strong: true),
              const SizedBox(height: 10),
              TextField(
                controller: counted,
                onChanged: (_) => setS(() {}),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Espèces USD comptées', border: OutlineInputBorder()),
              ),
              if (c != null) kv('Écart', usd(c - expected), strong: true),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
        );
      },
    ),
  );
}
