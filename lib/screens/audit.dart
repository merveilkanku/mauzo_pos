import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

/// Journal d'audit : opérations sensibles (qui, quoi, quand, motif, autorisation).
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});
  @override
  State<AuditScreen> createState() => _AuditState();
}

class _AuditState extends State<AuditScreen> {
  final q = TextEditingController();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final t = q.text.trim().toLowerCase();
          final list = app.audits.where((a) => t.isEmpty || '${a.by} ${a.action} ${a.detail} ${a.authorizer}'.toLowerCase().contains(t)).take(300).toList();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Panel(
              title: 'Journal d’audit',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 320,
                  child: TextField(controller: q, onChanged: (_) => setState(() {}), decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Rechercher (utilisateur, action, produit…)', border: OutlineInputBorder())),
                ),
                const SizedBox(height: 8),
                Text('${list.length} événement(s) affiché(s). Ce journal n’est jamais effacé par l’application.', style: muted),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Utilisateur')),
                        DataColumn(label: Text('Action')),
                        DataColumn(label: Text('Détail')),
                        DataColumn(label: Text('Autorisé par')),
                      ],
                      rows: [
                        for (final a in list)
                          DataRow(cells: [
                            DataCell(Text('${dateFr(a.at)} ${timeFr(a.at)}')),
                            DataCell(Text(a.by)),
                            DataCell(Text(a.action, style: bold)),
                            DataCell(SizedBox(width: 420, child: Text(a.detail, overflow: TextOverflow.ellipsis))),
                            DataCell(Text(a.authorizer.isEmpty ? '-' : a.authorizer)),
                          ]),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      );
}
