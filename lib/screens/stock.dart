import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

/// Fiche article (création ou modification). [code] pré-remplit le code-barres scanné.
Future<void> productForm(BuildContext context, {Product? p, String? code, int? initialQty}) async {
  final name = TextEditingController(text: p?.name ?? '');
  final bar = TextEditingController(text: p?.barcode ?? code ?? '');
  final cat = TextEditingController(text: p?.cat ?? 'Alimentaire');
  final price = TextEditingController(text: p == null ? '' : '${p.price}');
  final floor = TextEditingController(text: p == null ? '' : '${p.floor}');
  final stock = TextEditingController(text: p == null ? '${initialQty ?? 0}' : '${p.stock}');
  final min = TextEditingController(text: p == null ? '5' : '${p.min}');
  Widget f(String l, TextEditingController c, {bool auto = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(controller: c, autofocus: auto, decoration: InputDecoration(labelText: l, border: const OutlineInputBorder())),
      );
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(p != null ? 'Modifier l’article' : (code != null ? 'Nouvel article scanné' : 'Nouvel article')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            f('Nom', name, auto: true), f('Code-barres', bar), f('Catégorie', cat),
            f('Prix de vente (\$)', price), f('Prix plancher (\$)', floor), f('Quantité en stock', stock), f('Seuil d’alerte', min),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
      ],
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return;
  double d(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0;
  if (d(price) <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Indiquez un prix de vente.')));
    return;
  }
  final newCode = bar.text.trim();
  final other = newCode.isEmpty ? null : app.byBarcode(newCode);
  if (other != null && other != p) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ce code-barres existe déjà.')));
    return;
  }
  String? oldSku;
  var oldStock = 0;
  if (p == null) {
    app.products.add(Product('p${DateTime.now().microsecondsSinceEpoch}', newCode, name.text.trim(), cat.text.trim(), d(price), d(floor),
        int.tryParse(stock.text) ?? 0, int.tryParse(min.text) ?? 5, Icons.inventory_2, C.blue));
  } else {
    oldSku = p.sku;
    oldStock = p.stock;
    p.name = name.text.trim();
    p.barcode = newCode;
    p.cat = cat.text.trim();
    p.price = d(price);
    p.floor = d(floor);
    p.stock = int.tryParse(stock.text) ?? p.stock;
    p.min = int.tryParse(min.text) ?? p.min;
  }
  final saved = p ?? app.products.last;
  app.queueProduct(saved, p == null, oldSku: oldSku);
  if (p != null && saved.stock != oldStock) {
    app.queueOp('stock', 'Correction du stock : ${saved.name}', {'sku': saved.sku, 'delta': saved.stock - oldStock});
  }
}

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});
  @override
  State<StockScreen> createState() => _StockState();
}

class _StockState extends State<StockScreen> {
  final scan = TextEditingController();
  final focus = FocusNode();
  final feed = <String>[];

  void _log(String t) => setState(() {
        feed.insert(0, t);
        if (feed.length > 8) feed.removeLast();
      });

  // Gérant : chaque scan d'un article connu ajoute 1 au stock (ou N avec « 10*code »).
  // Un code inconnu ouvre la fiche pour l'enregistrer avec son code-barres.
  Future<void> _scan(String raw) async {
    var v = raw.trim();
    scan.clear();
    if (v.isEmpty) {
      focus.requestFocus();
      return;
    }
    var q = 1;
    final m = RegExp(r'^(\d{1,4})\s*[*xX]\s*(.+)$').firstMatch(v);
    if (m != null) {
      q = int.parse(m.group(1)!);
      v = m.group(2)!.trim();
    }
    final p = app.byBarcode(v);
    if (p != null) {
      app.receive(p, q);
      _log('${p.name} : +$q, stock ${p.stock}');
    } else {
      final before = app.products.length;
      await productForm(context, code: v, initialQty: q);
      if (app.products.length > before) {
        _log('Nouvel article enregistré : ${app.products.last.name} (code $v)');
      } else {
        _log('Code $v non enregistré');
      }
    }
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            if (app.isManager) ...[
              Panel(
                title: 'Enregistrer des articles par scan',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(
                    controller: scan,
                    focusNode: focus,
                    onSubmitted: _scan,
                    style: const TextStyle(fontSize: 18),
                    decoration: InputDecoration(
                      hintText: 'Cliquez ici, puis scannez chaque article (10*code pour une quantité)',
                      prefixIcon: const Icon(Icons.qr_code_scanner),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.blue, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Code connu : +1 au stock. Code inconnu : la fiche s’ouvre avec le code-barres déjà rempli. Le caissier n’aura ensuite qu’à scanner.', style: muted),
                  const SizedBox(height: 6),
                  if (feed.isEmpty) const Text('Aucun scan pour l’instant.', style: muted),
                  for (final line in feed) Text('• $line', style: bold),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            Panel(
              title: 'Articles et niveaux de stock',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (app.isManager) FilledButton.icon(onPressed: () => productForm(context), icon: const Icon(Icons.add), label: const Text('Nouvel article')),
                  if (app.isManager) const SizedBox(width: 10),
                  OutlinedButton.icon(onPressed: () => app.go(3), icon: const Icon(Icons.local_shipping), label: const Text('Réception de marchandise')),
                ]),
                const SizedBox(height: 10),
                if (app.products.isEmpty) const Text('Aucun article. Scannez le premier article pour commencer.', style: muted),
                SizedBox(
                  width: double.infinity,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Article')),
                        DataColumn(label: Text('Code-barres')),
                        DataColumn(label: Text('Catégorie')),
                        DataColumn(label: Text('Prix')),
                        DataColumn(label: Text('Plancher')),
                        DataColumn(label: Text('Stock')),
                        DataColumn(label: Text('Statut')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final p in app.products)
                          DataRow(cells: [
                            DataCell(Text(p.name, style: bold)),
                            DataCell(Text(p.barcode)),
                            DataCell(Text(p.cat)),
                            DataCell(Text(p.promo > 0 ? '${usd(p.sellPrice)} (-${p.promo.round()} %)' : usd(p.price))),
                            DataCell(Text(usd(p.floor))),
                            DataCell(Text('${p.stock}')),
                            DataCell(stockPill(p)),
                            DataCell(app.isManager ? TextButton(onPressed: () => productForm(context, p: p), child: const Text('Modifier')) : const Text('')),
                          ]),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      );
}
