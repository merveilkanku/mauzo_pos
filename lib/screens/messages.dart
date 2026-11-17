import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override
  State<MessagesScreen> createState() => _MessagesState();
}

class _MessagesState extends State<MessagesScreen> {
  final ctrl = TextEditingController();

  // Suggestion basée sur le stock réel (règles simples, pas encore une IA).
  String _suggest(Conv c) {
    var last = '';
    for (final m in c.msgs.reversed) {
      if (!m.mine) {
        last = m.text.toLowerCase();
        break;
      }
    }
    for (final p in app.products) {
      final k = p.name.split(' ').first.toLowerCase();
      if (k.length >= 4 && last.contains(k)) {
        return p.stock > 0
            ? '${p.name} : ${usd(p.sellPrice)}, ${p.stock} en stock (donnée de la caisse).'
            : '${p.name} est en rupture. Je vérifie avec le responsable et je vous réponds.';
      }
    }
    return 'Je vérifie avec le responsable et je vous réponds.';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final i = app.convIndex.clamp(0, app.convs.length - 1);
          final c = app.convs[i];
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              SizedBox(
                width: 300,
                child: Panel(
                  title: 'Conversations',
                  child: Column(children: [
                    for (var k = 0; k < app.convs.length; k++)
                      ListTile(
                        dense: true,
                        selected: k == i,
                        title: Text(app.convs[k].name, style: bold),
                        subtitle: Text(app.convs[k].msgs.isEmpty ? '' : app.convs[k].msgs.last.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text(app.convs[k].kind, style: muted),
                        onTap: () {
                          app.convIndex = k;
                          app.touch();
                        },
                      ),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c.name} · ${c.kind}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const Divider(),
                    Expanded(
                      child: ListView(children: [
                        for (final m in c.msgs)
                          Align(
                            alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.all(10),
                              constraints: const BoxConstraints(maxWidth: 420),
                              decoration: BoxDecoration(color: m.mine ? C.blueSoft : C.bg, borderRadius: BorderRadius.circular(10)),
                              child: Text(m.text),
                            ),
                          ),
                      ]),
                    ),
                    if (c.kind == 'Client')
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() => ctrl.text = _suggest(c)),
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Msaidizi : suggérer une réponse'),
                        ),
                      ),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: ctrl,
                          onSubmitted: (v) {
                            app.post(c, v);
                            ctrl.clear();
                          },
                          decoration: const InputDecoration(hintText: 'Votre message', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          app.post(c, ctrl.text);
                          ctrl.clear();
                        },
                        child: const Text('Envoyer'),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    const Text('Pour l’instant les messages restent dans l’application. L’envoi réel passera par l’API WhatsApp Business.', style: muted),
                  ]),
                ),
              ),
            ]),
          );
        },
      );
}
