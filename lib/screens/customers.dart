import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

/// Clients et fidélité : fiche par numéro WhatsApp, niveau, points, historique des points.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersState();
}

class _CustomersState extends State<CustomersScreen> {
  final q = TextEditingController();

  Pill _tier(String t) {
    if (t == 'Or') return const Pill('Or', C.blue, C.blueSoft);
    if (t == 'Argent') return const Pill('Argent', C.muted, C.bg);
    return const Pill('Bronze', C.amber, C.amberSoft);
  }

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _newCustomer() async {
    final n = TextEditingController();
    final t = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau client'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: n, autofocus: true, decoration: const InputDecoration(labelText: 'Nom', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: t, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Numéro WhatsApp', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            Text(app.welcomePoints > 0 ? 'Bonus de bienvenue : ${app.welcomePoints} points.' : '', style: muted),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ajouter')),
        ],
      ),
    );
    if (ok != true) return;
    if (app.validPhone(t.text) != null) {
      _msg('Numéro WhatsApp invalide.');
      return;
    }
    if (n.text.trim().isEmpty) {
      _msg('Indiquez le nom du client.');
      return;
    }
    if (app.findByPhone(t.text) != null) {
      _msg('Ce numéro est déjà enregistré.');
      return;
    }
    app.createCustomer(n.text, t.text);
  }

  Future<void> _ledger(Customer c) => showDialog<void>(
        context: context,
        builder: (ctx) {
          final list = app.ledger.where((e) => e.key == c.key).take(80).toList();
          return AlertDialog(
            title: Text('Points de ${c.name}'),
            content: SizedBox(
              width: 480,
              height: 380,
              child: list.isEmpty
                  ? const Text('Aucun mouvement.')
                  : ListView(children: [
                      for (final e in list)
                        ListTile(
                          dense: true,
                          title: Text(e.reason, style: bold),
                          subtitle: Text('${dateFr(e.at)} ${timeFr(e.at)}${e.by.isEmpty ? '' : ' · ${e.by}'}'),
                          trailing: Text('${e.delta >= 0 ? '+' : ''}${e.delta}', style: TextStyle(fontWeight: FontWeight.w800, color: e.delta >= 0 ? C.green : C.red)),
                        ),
                    ]),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
          );
        },
      );

  Future<void> _adjust(Customer c) async {
    final pts = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ajuster les points de ${c.name}'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Solde actuel : ${c.points} points', style: muted),
            const SizedBox(height: 8),
            TextField(controller: pts, autofocus: true, keyboardType: const TextInputType.numberWithOptions(signed: true), decoration: const InputDecoration(labelText: 'Points à ajouter (ou à retirer avec -)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motif (obligatoire)', border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Valider')),
        ],
      ),
    );
    if (ok == true) {
      final e = app.adjustPoints(c, int.tryParse(pts.text.trim()) ?? 0, reason.text);
      if (e != null) _msg(e);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final t = q.text.trim().toLowerCase();
          final list = app.customers.where((c) => t.isEmpty || c.name.toLowerCase().contains(t) || c.phone.contains(t) || c.key.contains(t)).toList();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Panel(
              title: 'Clients et fidélité',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  FilledButton.icon(onPressed: _newCustomer, icon: const Icon(Icons.person_add), label: const Text('Nouveau client')),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 280,
                    child: TextField(controller: q, onChanged: (_) => setState(() {}), decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Nom ou numéro WhatsApp', border: OutlineInputBorder())),
                  ),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Client')),
                        DataColumn(label: Text('WhatsApp')),
                        DataColumn(label: Text('Niveau')),
                        DataColumn(label: Text('Points')),
                        DataColumn(label: Text('Cumulés')),
                        DataColumn(label: Text('Visites')),
                        DataColumn(label: Text('Achats')),
                        DataColumn(label: Text('Ardoise')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final c in list)
                          DataRow(cells: [
                            DataCell(Text(c.name, style: bold)),
                            DataCell(Text(c.phone)),
                            DataCell(_tier(app.tierOf(c))),
                            DataCell(Text('${c.points}', style: const TextStyle(fontWeight: FontWeight.w800, color: C.blue))),
                            DataCell(Text('${c.earned > c.points ? c.earned : c.points}')),
                            DataCell(Text('${c.visits}')),
                            DataCell(Text(usd(c.spent))),
                            DataCell(Text(usd(c.debt), style: TextStyle(color: c.debt > 0 ? C.red : C.text, fontWeight: FontWeight.w700))),
                            DataCell(Row(children: [
                              TextButton(
                                onPressed: () {
                                  app.setCustomer(c);
                                  app.go(0);
                                },
                                child: const Text('Au ticket'),
                              ),
                              TextButton(
                                onPressed: () {
                                  app.convIndex = app.convs.indexOf(app.convFor(c));
                                  app.go(6);
                                },
                                child: const Text('Écrire'),
                              ),
                              TextButton(onPressed: () => _ledger(c), child: const Text('Points')),
                              if (app.isManager) TextButton(onPressed: () => _adjust(c), child: const Text('Ajuster')),
                            ])),
                          ]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Points : ${app.pointsPerUsd} par dollar payé (hors ardoise), multiplié selon le niveau (Argent ×1,25, Or ×1,5). Niveaux : Argent dès ${app.silverAt} points cumulés, Or dès ${app.goldAt}.', style: muted),
              ]),
            ),
          );
        },
      );
}
