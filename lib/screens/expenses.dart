import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

/// Dépenses (réservé au gérant). Une dépense payée en espèces diminue le théorique de la caisse choisie.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesState();
}

class _ExpensesState extends State<ExpensesScreen> {
  String cat = 'Transport';
  String cur = 'USD';
  bool fromCash = false;
  Session? sess;
  final amount = TextEditingController();
  final note = TextEditingController();

  void _save() {
    final open = app.sessions.where((s) => s.open).toList();
    final e = app.addExpense(cat, note.text.trim(), double.tryParse(amount.text.replaceAll(',', '.')) ?? 0, cur, fromCash, fromCash ? (sess ?? (open.isEmpty ? null : open.first)) : null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e ?? 'Dépense enregistrée.')));
    if (e == null) {
      amount.clear();
      note.clear();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final open = app.sessions.where((s) => s.open).toList();
          if (sess != null && !open.contains(sess)) sess = null;
          final totals = <String, double>{};
          for (final e in app.expenses) {
            totals[e.currency] = (totals[e.currency] ?? 0) + e.amount;
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 380,
                child: Panel(
                  title: 'Nouvelle dépense',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    DropdownButtonFormField<String>(
                      value: cat,
                      decoration: const InputDecoration(labelText: 'Catégorie', border: OutlineInputBorder()),
                      items: [for (final c in ['Transport', 'Loyer', 'Électricité et eau', 'Salaires', 'Achats divers', 'Autre']) DropdownMenuItem(value: c, child: Text(c))],
                      onChanged: (v) => setState(() => cat = v ?? cat),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Montant', border: OutlineInputBorder()))),
                      const SizedBox(width: 8),
                      DropdownButton<String>(value: cur, items: const [DropdownMenuItem(value: 'USD', child: Text('USD')), DropdownMenuItem(value: 'CDF', child: Text('CDF'))], onChanged: (v) => setState(() => cur = v ?? cur)),
                    ]),
                    const SizedBox(height: 8),
                    TextField(controller: note, decoration: const InputDecoration(labelText: 'Détail (facultatif)', border: OutlineInputBorder())),
                    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Payée avec l’argent d’une caisse'), value: fromCash, onChanged: open.isEmpty ? null : (v) => setState(() => fromCash = v)),
                    if (fromCash && open.isNotEmpty)
                      DropdownButtonFormField<Session>(
                        value: sess ?? open.first,
                        decoration: const InputDecoration(labelText: 'Caisse concernée', border: OutlineInputBorder()),
                        items: [for (final s in open) DropdownMenuItem(value: s, child: Text('${s.caisseName} · ${s.cashier}'))],
                        onChanged: (v) => setState(() => sess = v),
                      ),
                    const SizedBox(height: 10),
                    FilledButton(onPressed: _save, child: const Text('Enregistrer')),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Panel(
                  title: 'Dépenses enregistrées',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final t in totals.entries) kv('Total ${t.key}', money(t.value, t.key), strong: true),
                    const Divider(),
                    if (app.expenses.isEmpty) const Text('Aucune dépense.', style: muted),
                    for (final e in app.expenses.take(60))
                      kv('${dateFr(e.at)} · ${e.category}${e.note.isEmpty ? '' : ' (${e.note})'}${e.fromCash ? ' · caisse' : ''}', money(e.amount, e.currency)),
                  ]),
                ),
              ),
            ]),
          );
        },
      );
}
