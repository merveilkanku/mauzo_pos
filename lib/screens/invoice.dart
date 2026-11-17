import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key});
  @override
  State<InvoiceScreen> createState() => _InvoiceState();
}

class _InvoiceState extends State<InvoiceScreen> {
  final client = TextEditingController();
  PayMethod m = PayMethod.credit;

  void _issue(String no) {
    final name = client.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Indiquez le nom du client.')));
      return;
    }
    app.checkout([Payment(m, app.total.toString(), 0, dateFr(DateTime.now()))], app.total.toString());
    client.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Facture $no émise.')));
    app.go(0);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final lines = app.cart.values.toList();
          final no = 'FAC-${(app.sales.length + 1).toString().padLeft(4, '0')}';
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Panel(
                  title: 'Facture $no · ${dateFr(DateTime.now())}',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(
                      controller: client,
                      decoration: const InputDecoration(labelText: 'Client', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 14),
                    if (lines.isEmpty) const Text('Ajoutez des articles depuis le Terminal pour préparer une facture.', style: muted),
                    if (lines.isNotEmpty)
                      Table(
                        columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(), 2: FlexColumnWidth(1.4), 3: FlexColumnWidth(1.4)},
                        children: [
                          const TableRow(children: [
                            Text('Article', style: muted),
                            Text('Qté', style: muted),
                            Text('Prix unit.', style: muted),
                            Text('Total', style: muted),
                          ]),
                          for (final l in lines)
                            TableRow(children: [
                              Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(l.p.name, style: bold)),
                              Text('${l.qty}'),
                              Text(usd(l.unit)),
                              Text(usd(l.total), style: bold),
                            ]),
                        ],
                      ),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 380,
                child: Panel(
                  title: 'Totaux et émission',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    kv('Total hors taxe', usd(app.subtotal)),
                    kv('TVA ${(app.vatRate * 100).round()} %', usd(app.tax)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: C.blue, borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('TOTAL À PAYER', style: TextStyle(color: Color(0xFFC9D6F2), fontSize: 12)),
                        Text(usd(app.total), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                        Text(cdf(app.total * app.rate), style: const TextStyle(color: Color(0xFFC9D6F2))),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    DropdownButton<PayMethod>(
                      isExpanded: true,
                      value: m,
                      items: [for (final x in PayMethod.values) DropdownMenuItem(value: x, child: Text('Règlement : ${x.label}'))],
                      onChanged: (v) => setState(() => m = v ?? m),
                    ),
                    const SizedBox(height: 6),
                    const Text('Vérification fiscale : numéro et conformité avec l’administration à brancher avec un comptable.', style: muted),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: C.green),
                        onPressed: lines.isEmpty ? null : () => _issue(no),
                        child: const Text('Valider et émettre la facture', style: TextStyle(fontWeight: FontWeight.w700)),
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
