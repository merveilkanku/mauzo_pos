import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutState();
}

class _CheckoutState extends State<CheckoutScreen> {
  PayMethod m = PayMethod.cashUsd;
  final recv = TextEditingController();
  final client = TextEditingController(text: 'Client comptant');

  bool get cash => m == PayMethod.cashUsd || m == PayMethod.cashCdf;

  double get received {
    final v = double.tryParse(recv.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
    return m == PayMethod.cashCdf ? v / app.rate : v;
  }

  Future<void> _confirm() async {
    final name = client.text.trim().isEmpty ? 'Client comptant' : client.text.trim();
    final sale = app.checkout(m, name);
    recv.clear();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paiement confirmé'),
        content: SelectableText(receipt(sale), style: const TextStyle(fontFamily: 'Consolas', fontSize: 13)),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nouvelle vente'))],
      ),
    );
    app.go(0);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final lines = app.cart.values.toList();
          final change = received - app.total;
          final ok = lines.isNotEmpty && (!cash || received >= app.total);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Panel(
                  title: 'Récapitulatif',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (lines.isEmpty) const Text('Le ticket est vide. Retournez au Terminal.', style: muted),
                    for (final l in lines) kv('${l.qty} × ${l.p.name}', usd(l.total)),
                    const Divider(),
                    kv('Client', app.customer?.name ?? 'Client comptant'),
                    kv('Sous-total', usd(app.subtotal)),
                    kv('TVA ${(app.vatRate * 100).round()} %', usd(app.tax)),
                    const SizedBox(height: 8),
                    Text(usd(app.total), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: C.blue)),
                    Text(cdf(app.total * app.rate), style: const TextStyle(fontSize: 20, color: C.muted)),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 430,
                child: Panel(
                  title: 'Mode de paiement',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final x in PayMethod.values)
                        ChoiceChip(
                          avatar: Icon(x.icon, size: 18),
                          label: Text(x.label),
                          selected: m == x,
                          onSelected: (_) => setState(() => m = x),
                        ),
                    ]),
                    const SizedBox(height: 14),
                    if (cash) ...[
                      TextField(
                        controller: recv,
                        onChanged: (_) => setState(() {}),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: m == PayMethod.cashCdf ? 'Montant reçu (FC)' : 'Montant reçu (\$)',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      kv('Monnaie à rendre', change > 0 ? (m == PayMethod.cashCdf ? cdf(change * app.rate) : usd(change)) : '-', strong: true),
                    ],
                    if (m == PayMethod.credit)
                      TextField(controller: client, decoration: const InputDecoration(labelText: 'Client (ardoise)', border: OutlineInputBorder())),
                    if (m == PayMethod.mobile)
                      const Text('Le client règle par M-Pesa, Airtel Money ou Orange Money. Branchement à un agrégateur de paiement à prévoir.', style: muted),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: C.green),
                        onPressed: ok ? _confirm : null,
                        child: const Text('Confirmer l’encaissement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          );
        },
      );
}
