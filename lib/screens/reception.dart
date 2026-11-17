import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

class ReceptionScreen extends StatefulWidget {
  const ReceptionScreen({super.key});
  @override
  State<ReceptionScreen> createState() => _ReceptionState();
}

class _ReceptionState extends State<ReceptionScreen> {
  String sup = app.suppliers.first;
  final scan = TextEditingController();
  final qty = TextEditingController(text: '1');
  final focus = FocusNode();
  final Map<Product, int> lines = {};

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  void _scan(String v) {
    final p = app.find(v.trim());
    if (p == null) {
      _msg('Article inconnu : $v. Créez-le d’abord dans Stock.');
    } else {
      final n = int.tryParse(qty.text) ?? 1;
      setState(() => lines[p] = (lines[p] ?? 0) + n);
    }
    scan.clear();
    focus.requestFocus();
  }

  void _validate() {
    app.receiveMany(lines, sup);
    setState(() => lines.clear());
    _msg('Réception enregistrée, le stock est à jour.');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Panel(
                title: 'Nouvelle réception',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: sup,
                        decoration: const InputDecoration(labelText: 'Fournisseur', border: OutlineInputBorder()),
                        items: [for (final s in app.suppliers) DropdownMenuItem(value: s, child: Text(s))],
                        onChanged: (v) => setState(() => sup = v ?? sup),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 100,
                      child: TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantité', border: OutlineInputBorder())),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: scan,
                    focusNode: focus,
                    autofocus: true,
                    onSubmitted: _scan,
                    decoration: const InputDecoration(
                      labelText: 'Scannez un code-barres (ou tapez un nom puis Entrée)',
                      prefixIcon: Icon(Icons.qr_code_scanner),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (lines.isEmpty) const Text('Aucun article scanné.', style: muted),
                  for (final e in lines.entries) kv(e.key.name, '+ ${e.value}  (stock ${e.key.stock})'),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: C.green),
                    onPressed: lines.isEmpty ? null : _validate,
                    child: const Text('Valider la réception'),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 360,
              child: Panel(
                title: 'Dernières réceptions',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (app.receptions.isEmpty) const Text('Aucune réception enregistrée.', style: muted),
                  for (final r in app.receptions.take(8))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('N° ${r.no} · ${r.supplier} · ${dateFr(r.at)}\n${r.lines.entries.map((e) => '${e.value} × ${e.key}').join(', ')}', style: bold),
                    ),
                ]),
              ),
            ),
          ]),
        ),
      );
}
