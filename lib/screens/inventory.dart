import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryState();
}

class _InventoryState extends State<InventoryScreen> {
  final Map<String, TextEditingController> ctl = {};

  TextEditingController _c(Product p) => ctl.putIfAbsent(p.id, () => TextEditingController());
  int? _counted(Product p) => int.tryParse(_c(p).text.trim());

  void _apply() {
    var gap = 0.0;
    for (final p in app.products) {
      final n = _counted(p);
      if (n != null) {
        gap += (n - p.stock) * p.price;
        if (n != p.stock) app.queueOp('stock', 'Inventaire : ${p.name}', {'sku': p.sku, 'delta': n - p.stock});
        p.stock = n;
        _c(p).clear();
      }
    }
    app.touch();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Inventaire appliqué. Écart de valeur : ${usd(gap)}.')));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Panel(
            title: 'Inventaire physique',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Comptez les articles en rayon, saisissez les quantités, puis appliquez. Les lignes vides sont ignorées.', style: muted),
              const SizedBox(height: 8),
              for (final p in app.products)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: Text(p.name, style: bold)),
                    SizedBox(width: 110, child: Text('Théorique : ${p.stock}', style: muted)),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _c(p),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(isDense: true, labelText: 'Compté', border: OutlineInputBorder()),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        _counted(p) == null ? '' : 'Écart ${_counted(p)! - p.stock}',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w700, color: (_counted(p) ?? p.stock) == p.stock ? C.muted : C.red),
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _apply, child: const Text('Appliquer l’inventaire')),
            ]),
          ),
        ),
      );
}
