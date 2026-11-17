import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

class MarketingScreen extends StatefulWidget {
  const MarketingScreen({super.key});
  @override
  State<MarketingScreen> createState() => _MarketingState();
}

class _MarketingState extends State<MarketingScreen> {
  late Product prod = app.products.first;
  final pct = TextEditingController(text: '10');
  final name = TextEditingController(text: 'Promo de la semaine');
  final msg = TextEditingController();
  String seg = segments.first;

  void _promo() {
    app.setPromo(prod, double.tryParse(pct.text.replaceAll(',', '.')) ?? 0);
    msg.text = 'Bonjour ! Cette semaine : -${pct.text} % sur ${prod.name}. Passez en magasin ou répondez à ce message pour commander.';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          if (app.products.isEmpty) {
            return const Padding(padding: EdgeInsets.all(16), child: Panel(child: Text('Ajoutez d’abord des articles dans Stock.')));
          }
          if (!app.products.contains(prod)) prod = app.products.first;
          final active = app.products.where((p) => p.promo > 0).toList();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Panel(
                    title: 'Promotions (appliquées automatiquement à la caisse)',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      DropdownButtonFormField<Product>(
                        value: prod,
                        decoration: const InputDecoration(labelText: 'Article', border: OutlineInputBorder()),
                        items: [for (final p in app.products) DropdownMenuItem(value: p, child: Text(p.name))],
                        onChanged: (v) => setState(() => prod = v ?? prod),
                      ),
                      const SizedBox(height: 8),
                      TextField(controller: pct, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Remise en %', border: OutlineInputBorder())),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _promo, child: const Text('Appliquer la promotion')),
                      const SizedBox(height: 12),
                      if (active.isEmpty) const Text('Aucune promotion active.', style: muted),
                      for (final p in active)
                        Row(children: [
                          Expanded(child: Text('${p.name} : -${p.promo.round()} % (${usd(p.sellPrice)})', style: bold)),
                          TextButton(onPressed: () => app.setPromo(p, 0), child: const Text('Retirer')),
                        ]),
                      const Text('Le prix ne descend pas sous le plancher : à vérifier avant d’appliquer.', style: muted),
                    ]),
                  ),
                ),
              ),
              Expanded(
                child: Panel(
                  title: 'Campagne WhatsApp',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom de la campagne', border: OutlineInputBorder())),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: seg,
                      decoration: const InputDecoration(labelText: 'Destinataires', border: OutlineInputBorder()),
                      items: [for (final s in segments) DropdownMenuItem(value: s, child: Text(s))],
                      onChanged: (v) => setState(() => seg = v ?? seg),
                    ),
                    const SizedBox(height: 8),
                    TextField(controller: msg, maxLines: 4, decoration: const InputDecoration(labelText: 'Message (rempli par la promotion)', border: OutlineInputBorder())),
                    const SizedBox(height: 8),
                    Text('${app.segment(seg).length} destinataire(s)', style: muted),
                    const SizedBox(height: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: C.green),
                      onPressed: msg.text.trim().isEmpty
                          ? null
                          : () {
                              final n = app.sendCampaign(name.text, seg, msg.text.trim());
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Campagne simulée : $n message(s) ajouté(s) dans Messages.')));
                            },
                      child: const Text('Envoyer la campagne'),
                    ),
                    const Divider(),
                    for (final c in app.campaigns.take(5)) kv(c.name, '${c.sent} envoi(s) · ${dateFr(c.at)}'),
                  ]),
                ),
              ),
            ]),
          );
        },
      );
}
