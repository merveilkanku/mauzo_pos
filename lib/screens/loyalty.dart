import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

/// Programme de fidélité (gérant) : règles des points, récompenses, clients prêts pour une récompense.
class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});
  @override
  State<LoyaltyScreen> createState() => _LoyaltyState();
}

class _LoyaltyState extends State<LoyaltyScreen> {
  final ppu = TextEditingController(text: '${app.pointsPerUsd}');
  final welcome = TextEditingController(text: '${app.welcomePoints}');
  final silver = TextEditingController(text: '${app.silverAt}');
  final gold = TextEditingController(text: '${app.goldAt}');
  final rName = TextEditingController();
  final rCost = TextEditingController();
  final rValue = TextEditingController();
  String rKind = 'amount';

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  void _saveRules() {
    final p = double.tryParse(ppu.text.replaceAll(',', '.')) ?? app.pointsPerUsd;
    app.pointsPerUsd = p <= 0 ? app.pointsPerUsd : p;
    app.welcomePoints = int.tryParse(welcome.text) ?? app.welcomePoints;
    app.silverAt = int.tryParse(silver.text) ?? app.silverAt;
    app.goldAt = int.tryParse(gold.text) ?? app.goldAt;
    if (app.goldAt <= app.silverAt) app.goldAt = app.silverAt + 1;
    app.audit('règles de fidélité modifiées', '${app.pointsPerUsd} pt/\$, bienvenue ${app.welcomePoints}, Argent ${app.silverAt}, Or ${app.goldAt}');
    app.queueSettings();
    _msg('Règles enregistrées et envoyées aux autres PC.');
  }

  void _addReward() {
    final cost = int.tryParse(rCost.text) ?? 0;
    final v = double.tryParse(rValue.text.replaceAll(',', '.')) ?? 0;
    if (rName.text.trim().isEmpty || cost <= 0 || v <= 0) {
      _msg('Indiquez un nom, un nombre de points et une valeur.');
      return;
    }
    if (rKind == 'percent' && v > 50) {
      _msg('Une réduction en pourcentage est limitée à 50 %.');
      return;
    }
    app.rewards.add(Reward('r${DateTime.now().millisecondsSinceEpoch}', rName.text.trim(), cost, rKind, v));
    app.rewards.sort((a, b) => a.cost.compareTo(b.cost));
    app.audit('récompense ajoutée', '${rName.text.trim()} pour $cost points');
    rName.clear();
    rCost.clear();
    rValue.clear();
    app.queueSettings();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final minCost = app.rewards.isEmpty ? 0 : app.rewards.map((r) => r.cost).reduce((a, b) => a < b ? a : b);
          final ready = app.rewards.isEmpty ? <Customer>[] : app.customers.where((c) => c.points >= minCost).toList();
          final top = [...app.customers]..sort((a, b) => b.earned.compareTo(a.earned));
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(children: [
                    Panel(
                      title: 'Règles des points',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _f('Points gagnés par dollar payé', ppu),
                        _f('Bonus de bienvenue (nouveau client)', welcome),
                        _f('Niveau Argent à partir de … points cumulés', silver),
                        _f('Niveau Or à partir de … points cumulés', gold),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Proposer le client avant le paiement'),
                          subtitle: const Text('Le caissier est invité à saisir le numéro WhatsApp'),
                          value: app.askCustomerAtPayment,
                          onChanged: (v) {
                            app.askCustomerAtPayment = v;
                            app.queueSettings();
                          },
                        ),
                        const SizedBox(height: 6),
                        FilledButton(onPressed: _saveRules, child: const Text('Enregistrer les règles')),
                        const SizedBox(height: 6),
                        const Text('Les points sont calculés sur l’argent réellement payé (l’ardoise n’en donne pas). Argent ×1,25 et Or ×1,5 sur les points gagnés.', style: muted),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Panel(
                      title: 'Récompenses',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (app.rewards.isEmpty) const Text('Aucune récompense.', style: muted),
                        for (final r in app.rewards)
                          Row(children: [
                            Expanded(child: Text('${r.name} · ${r.cost} points · ${r.kind == 'percent' ? '${r.value.toStringAsFixed(0)} % de réduction' : usd(r.value)}', style: bold)),
                            IconButton(
                              tooltip: 'Supprimer',
                              onPressed: () {
                                app.rewards.remove(r);
                                app.audit('récompense supprimée', r.name);
                                app.queueSettings();
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ]),
                        const Divider(),
                        _f('Nom (ex. Bon de 5 \$)', rName),
                        Row(children: [
                          Expanded(child: _f('Points demandés', rCost)),
                          const SizedBox(width: 8),
                          Expanded(child: _f(rKind == 'percent' ? 'Réduction (%)' : 'Valeur (\$)', rValue)),
                        ]),
                        DropdownButtonFormField<String>(
                          value: rKind,
                          decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'amount', child: Text('Bon en dollars')),
                            DropdownMenuItem(value: 'percent', child: Text('Réduction en pourcentage')),
                          ],
                          onChanged: (v) => setState(() => rKind = v ?? rKind),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(onPressed: _addReward, icon: const Icon(Icons.add), label: const Text('Ajouter la récompense')),
                      ]),
                    ),
                  ]),
                ),
              ),
              Expanded(
                child: Column(children: [
                  Panel(
                    title: 'Prêts pour une récompense (${ready.length})',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (ready.isEmpty) const Text('Aucun client pour l’instant.', style: muted),
                      for (final c in ready) kv('${c.name} · ${c.phone}', '${c.points} pts'),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: ready.isEmpty
                            ? null
                            : () {
                                final n = app.notifyRewardReady();
                                _msg('$n message(s) ajouté(s) dans Messages (envoi WhatsApp réel à brancher).');
                              },
                        icon: const Icon(Icons.chat),
                        label: const Text('Prévenir par WhatsApp'),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Panel(
                    title: 'Meilleurs clients (points cumulés)',
                    child: Column(children: [
                      if (top.isEmpty) const Text('Aucun client.', style: muted),
                      for (final c in top.take(8)) kv('${c.name} · ${app.tierOf(c)}', '${c.earned > c.points ? c.earned : c.points} pts · ${usd(c.spent)}'),
                    ]),
                  ),
                ]),
              ),
            ]),
          );
        },
      );

  Widget _f(String l, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(controller: c, decoration: InputDecoration(labelText: l, border: const OutlineInputBorder())),
      );
}
