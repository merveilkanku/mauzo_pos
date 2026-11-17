import 'dart:io';
import 'package:flutter/material.dart';
import '../core.dart';
import '../printing_service.dart';
import '../state.dart';

/// Factures et ventes : recherche, filtres, détails, réimpression, annulation tracée, export CSV.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesState();
}

class _SalesState extends State<SalesScreen> {
  final q = TextEditingController();
  DateTime? from, to;
  String caisse = 'Toutes';
  String pay = 'Tous';

  List<Sale> _list() {
    final t = q.text.trim().toLowerCase();
    final mineOnly = app.user?.role == Role.caissier;
    final f = from;
    final e = to;
    return app.sales.where((s) {
      if (mineOnly && s.cashier != app.user!.name) return false;
      if (t.isNotEmpty && !('${s.no}'.contains(t) || s.client.toLowerCase().contains(t) || s.cashier.toLowerCase().contains(t))) return false;
      if (f != null && s.at.isBefore(DateTime(f.year, f.month, f.day))) return false;
      if (e != null && s.at.isAfter(DateTime(e.year, e.month, e.day, 23, 59, 59))) return false;
      if (caisse != 'Toutes' && s.caisse != caisse) return false;
      if (pay == 'Paiement mixte') return s.mixed;
      if (pay != 'Tous' && !s.payments.any((p) => p.method.label == pay)) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  Future<void> _pickDate(bool isFrom) async {
    final d = await showDatePicker(context: context, initialDate: (isFrom ? from : to) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d != null) setState(() => isFrom ? from = d : to = d);
  }

  String _csv(Object v) {
    final t = '$v'.replaceAll('"', '""');
    return t.contains(';') || t.contains('"') || t.contains('\n') ? '"$t"' : t;
  }

  Future<void> _export(List<Sale> list) async {
    try {
      final dir = Directory('${app.dataDir}${Platform.pathSeparator}exports');
      await dir.create(recursive: true);
      final n = DateTime.now();
      String two(int x) => x.toString().padLeft(2, '0');
      final f = File('${dir.path}${Platform.pathSeparator}factures_${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}.csv');
      final b = StringBuffer('\uFEFF');
      b.writeln('Ticket;Date;Heure;Caisse;Caissier;Client;Paiement;Total USD;Statut;Motif annulation;Annulé par');
      for (final s in list) {
        b.writeln([s.no, dateFr(s.at), timeFr(s.at), s.caisse, s.cashier, s.client, s.methodLabel, s.total.toStringAsFixed(2).replaceAll('.', ','), s.refunded ? 'Annulée' : 'Valide', s.cancelReason, s.cancelledBy].map(_csv).join(';'));
      }
      await f.writeAsString(b.toString());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export enregistré (s’ouvre dans Excel) : ${f.path}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export impossible : $e')));
    }
  }

  Future<void> _detail(Sale s) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Ticket n° ${s.no}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: SelectableText('${receipt(s)}${s.refunded ? '\n\nAnnulée le ${dateFr(s.cancelledAt ?? s.at)} par ${s.cancelledBy}\nMotif : ${s.cancelReason}' : ''}', style: mono),
            ),
          ),
          actions: [
            if (app.can('reprint')) TextButton(onPressed: () => printSale(s), child: const Text('Réimprimer')),
            if (app.can('reprint')) TextButton(onPressed: () => printSale(s, a4: true), child: const Text('Facture A4')),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
          ],
        ),
      );

  Future<void> _cancel(Sale s) async {
    final reason = TextEditingController();
    final pin = TextEditingController();
    final needPin = !app.isManager;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Annuler le ticket n° ${s.no} ?'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${usd(s.total)} · les articles seront remis en stock. La facture reste visible dans l’historique.', style: muted),
            const SizedBox(height: 10),
            TextField(controller: reason, autofocus: true, decoration: const InputDecoration(labelText: 'Motif (obligatoire)', border: OutlineInputBorder())),
            if (needPin) ...[
              const SizedBox(height: 8),
              TextField(controller: pin, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de sécurité du gérant', border: OutlineInputBorder())),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Retour')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Annuler la facture')),
        ],
      ),
    );
    if (ok == true) {
      final e = app.cancelSale(s, reason.text, secret: pin.text.trim());
      if (e != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e)));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final list = _list();
          final total = list.where((s) => !s.refunded).fold(0.0, (a, s) => a + s.total);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Panel(
              title: 'Factures et ventes',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: q,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'N° de facture, client ou caissier', border: OutlineInputBorder()),
                    ),
                  ),
                  OutlinedButton(onPressed: () => _pickDate(true), child: Text(from == null ? 'Du…' : 'Du ${dateFr(from!)}')),
                  OutlinedButton(onPressed: () => _pickDate(false), child: Text(to == null ? 'Au…' : 'Au ${dateFr(to!)}')),
                  if (from != null || to != null) TextButton(onPressed: () => setState(() => from = to = null), child: const Text('Toutes les dates')),
                  DropdownButton<String>(
                    value: caisse,
                    items: [for (final c in ['Toutes', ...app.caisses.map((c) => c.name)]) DropdownMenuItem(value: c, child: Text(c == 'Toutes' ? 'Toutes les caisses' : c))],
                    onChanged: (v) => setState(() => caisse = v ?? caisse),
                  ),
                  DropdownButton<String>(
                    value: pay,
                    items: [for (final c in ['Tous', 'Espèces USD', 'Espèces CDF', 'Mobile money', 'Carte', 'Ardoise', 'Paiement mixte']) DropdownMenuItem(value: c, child: Text(c == 'Tous' ? 'Tous les paiements' : c))],
                    onChanged: (v) => setState(() => pay = v ?? pay),
                  ),
                  if (app.isManager) OutlinedButton.icon(onPressed: () => _export(list), icon: const Icon(Icons.download), label: const Text('Exporter (CSV/Excel)')),
                ]),
                const SizedBox(height: 8),
                Text('${list.length} facture(s) · total valide ${usd(total)}', style: muted),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Ticket')),
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Caisse')),
                        DataColumn(label: Text('Caissier')),
                        DataColumn(label: Text('Client')),
                        DataColumn(label: Text('Paiement')),
                        DataColumn(label: Text('Total')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final s in list.take(300))
                          DataRow(cells: [
                            DataCell(Text('${s.no}', style: bold)),
                            DataCell(Text('${dateFr(s.at)} ${timeFr(s.at)}')),
                            DataCell(Text(s.caisse)),
                            DataCell(Text(s.cashier)),
                            DataCell(Text(s.client)),
                            DataCell(Text(s.methodLabel)),
                            DataCell(Text(usd(s.total))),
                            DataCell(Row(children: [
                              TextButton(onPressed: () => _detail(s), child: const Text('Détails')),
                              if (s.refunded)
                                const Pill('Annulée', C.red, C.redSoft)
                              else if (app.can('refund'))
                                TextButton(onPressed: () => _cancel(s), child: const Text('Annuler')),
                            ])),
                          ]),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      );
}
