import 'package:flutter/material.dart';
import '../core.dart';
import '../printing_service.dart';
import '../state.dart';

/// Clôture et contrôle des caisses (réservé au gérant).
class ClotureScreen extends StatefulWidget {
  const ClotureScreen({super.key});
  @override
  State<ClotureScreen> createState() => _ClotureState();
}

class _ClotureState extends State<ClotureScreen> {
  String? selId;
  final Map<String, TextEditingController> ctl = {};
  final note = TextEditingController();

  TextEditingController _c(String sid, String k) => ctl.putIfAbsent('$sid#$k', () => TextEditingController());
  double? _num(TextEditingController c) => double.tryParse(c.text.replaceAll(' ', '').replaceAll(',', '.'));

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _close(Session s, List<String> keys) async {
    final counted = <String, double>{};
    for (final k in keys) {
      final v = _num(_c(s.id, k));
      if (v == null) {
        _msg('Saisissez le montant compté pour : ${labelOfKey(k)}');
        return;
      }
      counted[k] = v;
    }
    final theory = app.theoryOf(s);
    final preview = Closure(theory, counted, app.rate, app.user!.name, note.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Valider la clôture ?'),
        content: Text('Écart total : ${signed(preview.varianceUsd(), 'USD')}.\nUne clôture validée est verrouillée : toute correction demandera votre autorisation et un motif.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Retour')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clôturer')),
        ],
      ),
    );
    if (ok == true) {
      final e = app.closeSession(s, counted, note.text.trim());
      if (e != null) _msg(e);
      note.clear();
    }
  }

  Future<void> _amend(Session s) async {
    final c = s.closure!;
    final cs = {for (final k in c.theory.keys) k: TextEditingController(text: '${c.counted[k] ?? 0}')};
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Corriger la clôture'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final k in cs.keys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(controller: cs[k], keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Compté : ${labelOfKey(k)}', border: const OutlineInputBorder())),
                ),
              TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motif de la correction (obligatoire)', border: OutlineInputBorder())),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer la correction')),
        ],
      ),
    );
    if (ok == true) {
      final m = <String, double>{for (final k in cs.keys) k: _num(cs[k]!) ?? 0};
      final e = app.amendClosure(s, m, reason.text);
      if (e != null) _msg(e);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final list = [...app.sessions]..sort((a, b) {
              if (a.open != b.open) return a.open ? -1 : 1;
              return b.openedAt.compareTo(a.openedAt);
            });
          Session? sel;
          for (final s in list) {
            if (s.id == selId) sel = s;
          }
          sel ??= list.isEmpty ? null : list.first;
          final byCashier = <String, double>{};
          for (final s in app.sales.where((x) => !x.refunded)) {
            byCashier[s.cashier] = (byCashier[s.cashier] ?? 0) + s.total;
          }
          final rank = byCashier.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          final closed = list.where((s) => !s.open && s.closure != null).toList();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 320,
                  child: Panel(
                    title: 'Sessions de caisse',
                    child: Column(children: [
                      if (list.isEmpty) const Text('Aucune session. Elles s’ouvrent à la connexion des caissiers.', style: muted),
                      for (final s in list)
                        ListTile(
                          dense: true,
                          selected: sel != null && s.id == sel.id,
                          title: Text('${s.caisseName} · ${s.cashier}', style: bold),
                          subtitle: Text('${dateFr(s.openedAt)} ${timeFr(s.openedAt)}'),
                          trailing: s.open ? const Pill('Ouverte', C.green, C.greenSoft) : const Pill('Clôturée', C.muted, C.bg),
                          onTap: () => setState(() => selId = s.id),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: sel == null ? const Panel(child: Text('Sélectionnez une session.')) : _detail(sel)),
              ]),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Panel(
                      title: 'Classement des caissiers (ventes valides)',
                      child: Column(children: [
                        if (rank.isEmpty) const Text('Aucune vente.', style: muted),
                        for (var i = 0; i < rank.length; i++) kv('${i + 1}. ${rank[i].key.isEmpty ? '-' : rank[i].key}', usd(rank[i].value)),
                      ]),
                    ),
                  ),
                ),
                Expanded(
                  child: Panel(
                    title: 'Écarts de caisse par clôture',
                    child: Column(children: [
                      if (closed.isEmpty) const Text('Aucune clôture.', style: muted),
                      for (final s in closed.take(12)) kv('${s.caisseName} · ${s.cashier} · ${dateFr(s.closedAt!)}', signed(s.closure!.varianceUsd(), 'USD')),
                    ]),
                  ),
                ),
              ]),
            ]),
          );
        },
      );

  Widget _detail(Session s) {
    final c = s.closure;
    final theory = c?.theory ?? app.theoryOf(s);
    final keys = theory.keys.toList()..sort();
    return Panel(
      title: s.open ? 'Clôture : ${s.caisseName} · ${s.cashier}' : 'Rapport de clôture : ${s.caisseName} · ${s.cashier}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        kv('Caissier', s.cashier),
        kv('Caisse', s.caisseName),
        kv('Nombre de factures', '${app.salesOf(s).length}'),
        kv('Ouverture', '${dateFr(s.openedAt)} ${timeFr(s.openedAt)}'),
        kv('Fermeture', s.closedAt == null ? 'en cours' : '${dateFr(s.closedAt!)} ${timeFr(s.closedAt!)}'),
        kv('Ventes à l’ardoise (non encaissées)', usd(app.creditOf(s))),
        const Divider(),
        if (s.open) ...[
          const Text('Comptez les fonds réellement disponibles pour chaque moyen de paiement. Chaque ligne reste dans sa devise.', style: muted),
          const SizedBox(height: 8),
          for (final k in keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: Text(labelOfKey(k), style: bold)),
                SizedBox(width: 150, child: Text('Théorique : ${money(theory[k] ?? 0, currencyOfKey(k))}')),
                SizedBox(
                  width: 130,
                  child: TextField(controller: _c(s.id, k), keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(isDense: true, labelText: 'Compté', border: OutlineInputBorder())),
                ),
                SizedBox(
                  width: 120,
                  child: Text(_num(_c(s.id, k)) == null ? '' : 'Écart ${signed(_num(_c(s.id, k))! - (theory[k] ?? 0), currencyOfKey(k))}', textAlign: TextAlign.right, style: bold),
                ),
              ]),
            ),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Remarques (facultatif)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          FilledButton(onPressed: () => _close(s, keys), child: const Text('Valider la clôture')),
        ] else ...[
          SelectableText(closureReport(s), style: mono),
          const SizedBox(height: 10),
          Row(children: [
            OutlinedButton.icon(onPressed: () => printText(closureReport(s), 'Clôture ${s.caisseName}'), icon: const Icon(Icons.print), label: const Text('Imprimer le rapport')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: () => _amend(s), child: const Text('Corriger (avec motif)')),
          ]),
        ],
      ]),
    );
  }
}
