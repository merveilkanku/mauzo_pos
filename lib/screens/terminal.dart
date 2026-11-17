import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});
  @override
  State<TerminalScreen> createState() => _TerminalState();
}

class _TerminalState extends State<TerminalScreen> {
  String q = '';
  String cat = 'Tout';
  final focus = FocusNode();
  final ctrl = TextEditingController();

  // Un scanner USB tape le code puis Entrée : si le code existe, l'article est ajouté.
  void _scan(String v) {
    final p = app.byBarcode(v.trim());
    if (p != null) {
      app.add(p);
      ctrl.clear();
      setState(() => q = '');
    } else if (RegExp(r'^\d{8,}$').hasMatch(v.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Code inconnu : $v. Créez l’article dans Stock.')));
    }
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final cats = ['Tout', ...{for (final p in app.products) p.cat}];
        final list = app.products
            .where((p) => (cat == 'Tout' || p.cat == cat) && p.name.toLowerCase().contains(q.toLowerCase()))
            .toList();
        return Row(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                TextField(
                  focusNode: focus,
                  controller: ctrl,
                  autofocus: true,
                  onSubmitted: _scan,
                  onChanged: (v) => setState(() => q = v),
                  decoration: InputDecoration(
                    hintText: 'Scannez un code-barres ou tapez un nom',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: C.line),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final c in cats)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(label: Text(c), selected: cat == c, onSelected: (_) => setState(() => cat = c)),
                      ),
                  ]),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: GridView.builder(
                    itemCount: list.length,
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 210,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.95,
                    ),
                    itemBuilder: (_, i) => _tile(list[i]),
                  ),
                ),
              ]),
            ),
          ),
          _cart(),
        ]);
      },
    );
  }

  Widget _tile(Product p) {
    final out = p.stock <= 0;
    final inCart = app.cart[p.id]?.qty ?? 0;
    return Opacity(
      opacity: out ? 0.5 : 1,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: out ? null : () => app.add(p),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: inCart > 0 ? C.blue : C.line, width: inCart > 0 ? 2 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(color: p.color.withOpacity(0.14), borderRadius: BorderRadius.circular(10)),
                  child: Stack(children: [
                    Center(child: Icon(p.icon, size: 44, color: p.color)),
                    if (p.promo > 0) Positioned(top: 6, left: 6, child: Pill('-${p.promo.round()} %', C.red, C.redSoft)),
                    if (inCart > 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: C.blue,
                          child: Text('$inCart', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: bold),
              const SizedBox(height: 2),
              Row(children: [
                Text(usd(p.sellPrice), style: const TextStyle(color: C.blue, fontWeight: FontWeight.w800)),
                const Spacer(),
                stockPill(p),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _cart() {
    final lines = app.cart.values.toList();
    return Container(
      width: 360,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: Colors.white, border: Border(left: BorderSide(color: C.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Ticket en cours', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (lines.isNotEmpty) TextButton(onPressed: app.clear, child: const Text('Vider')),
        ]),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _pickCustomer,
          icon: const Icon(Icons.person),
          label: Text(app.customer == null ? 'Rattacher un client' : '${app.customer!.name} · ${app.customer!.points} pts'),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: lines.isEmpty
              ? const Center(child: Text('Touchez un article pour l’ajouter.', style: muted))
              : ListView(children: [for (final l in lines) _row(l)]),
        ),
        const Divider(),
        kv('Sous-total', usd(app.subtotal)),
        kv('TVA ${(app.vatRate * 100).round()} %', usd(app.tax)),
        const SizedBox(height: 6),
        Text(usd(app.total), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: C.text)),
        Text('≈ ${cdf(app.total * app.rate)}', style: muted),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.green),
            onPressed: lines.isEmpty ? null : () => app.go(2),
            child: const Text('Encaisser', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Future<void> _pickCustomer() async {
    final c = await showDialog<Customer>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choisir un client'),
        children: [
          for (final c in app.customers) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, c), child: Text('${c.name} · ${c.points} points')),
        ],
      ),
    );
    if (c != null) {
      app.customer = c;
      app.touch();
    }
  }

  Widget _row(Line l) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(l.p.name, style: bold, maxLines: 1, overflow: TextOverflow.ellipsis)),
          IconButton(visualDensity: VisualDensity.compact, onPressed: () => app.dec(l.p), icon: const Icon(Icons.remove_circle_outline)),
          Text('${l.qty}', style: bold),
          IconButton(visualDensity: VisualDensity.compact, onPressed: () => app.add(l.p), icon: const Icon(Icons.add_circle_outline)),
          SizedBox(width: 64, child: Text(usd(l.total), textAlign: TextAlign.right, style: bold)),
        ]),
      );
}
