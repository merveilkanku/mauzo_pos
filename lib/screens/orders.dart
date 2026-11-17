import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  Future<void> _newOrder(BuildContext context) async {
    final client = TextEditingController();
    final qty = TextEditingController(text: '1');
    if (app.products.isEmpty) return;
    Product p = app.products.first;
    String src = 'WhatsApp';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Nouvelle commande'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: client, decoration: const InputDecoration(labelText: 'Client', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              DropdownButtonFormField<Product>(
                value: p,
                decoration: const InputDecoration(labelText: 'Article', border: OutlineInputBorder()),
                items: [for (final x in app.products) DropdownMenuItem(value: x, child: Text(x.name))],
                onChanged: (v) => setS(() => p = v ?? p),
              ),
              const SizedBox(height: 8),
              TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantité', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: src,
                decoration: const InputDecoration(labelText: 'Origine', border: OutlineInputBorder()),
                items: [for (final x in ['WhatsApp', 'Téléphone', 'Sur place']) DropdownMenuItem(value: x, child: Text(x))],
                onChanged: (v) => setS(() => src = v ?? src),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Créer')),
          ],
        ),
      ),
    );
    if (ok == true && client.text.trim().isNotEmpty) {
      app.createOrder(client.text.trim(), p, int.tryParse(qty.text) ?? 1, src);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Panel(
            title: 'Commandes clients (WhatsApp, téléphone, sur place)',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FilledButton.icon(onPressed: () => _newOrder(context), icon: const Icon(Icons.add), label: const Text('Nouvelle commande')),
              const SizedBox(height: 10),
              for (final o in app.orders)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.line))),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('N° ${o.no} · ${o.client} · ${o.source}', style: bold),
                        Text(o.items.entries.map((e) => '${e.value} × ${e.key.name}').join(', '), style: muted),
                      ]),
                    ),
                    Text(usd(o.total), style: bold),
                    const SizedBox(width: 12),
                    o.status == 'Nouvelle'
                        ? const Pill('Nouvelle', C.amber, C.amberSoft)
                        : o.status == 'Payée'
                            ? const Pill('Payée', C.blue, C.blueSoft)
                            : const Pill('Livrée', C.green, C.greenSoft),
                    const SizedBox(width: 12),
                    if (o.status == 'Nouvelle')
                      PopupMenuButton<PayMethod>(
                        onSelected: (m) {
                          final err = app.payOrder(o, m);
                          if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                        },
                        itemBuilder: (_) => [for (final m in PayMethod.values) PopupMenuItem(value: m, child: Text(m.label))],
                        child: const Chip(label: Text('Encaisser')),
                      ),
                    if (o.status == 'Payée') OutlinedButton(onPressed: () => app.deliver(o), child: const Text('Marquer livrée')),
                  ]),
                ),
            ]),
          ),
        ),
      );
}
