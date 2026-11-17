import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  Widget _kpi(String t, String v, Color c) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: muted),
              const SizedBox(height: 6),
              Text(v, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final cat = <String, double>{};
          for (final s in app.sales.where((x) => !x.refunded)) {
            for (final l in s.lines) {
              cat[l.p.cat] = (cat[l.p.cat] ?? 0) + l.total;
            }
          }
          final catTotal = cat.values.fold(0.0, (a, b) => a + b);
          final stockValue = app.products.fold(0.0, (a, p) => a + p.stock * p.price);
          final debt = app.customers.fold(0.0, (a, c) => a + c.debt);
          final refunds = app.sales.where((s) => s.refunded).length;
          final clients = [...app.customers]..sort((a, b) => b.spent.compareTo(a.spent));
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _kpi('Chiffre d’affaires net', usd(app.todayTotal), C.blue),
                _kpi('Valeur du stock (prix de vente)', usd(stockValue), C.text),
                _kpi('Dettes clients', usd(debt), C.red),
                _kpi('Retours', '$refunds', C.amber),
              ]),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Panel(
                      title: 'Ventes par catégorie',
                      child: Column(children: [
                        for (final e in cat.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(children: [
                              SizedBox(width: 100, child: Text(e.key, style: muted)),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(value: catTotal == 0 ? 0 : e.value / catTotal, minHeight: 10, color: C.blue, backgroundColor: C.blueSoft),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(usd(e.value), style: bold),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                ),
                Expanded(
                  child: Panel(
                    title: 'Meilleurs clients',
                    child: Column(children: [
                      for (final c in clients.take(5)) kv(c.name, usd(c.spent)),
                      const SizedBox(height: 8),
                      const Text('La marge réelle demande le prix d’achat de chaque article, à ajouter à la fiche article.', style: muted),
                    ]),
                  ),
                ),
              ]),
            ]),
          );
        },
      );
}
