import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core.dart';
import '../server_host.dart';
import '../state.dart';

/// Serveur du réseau, intégré à Mauzo POS : le PC principal fait tourner le serveur, les autres caisses s'y connectent.
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});
  @override
  State<ServerScreen> createState() => _ServerState();
}

class _ServerState extends State<ServerScreen> {
  List<String> addresses = [];
  final portCtl = TextEditingController(text: '${server.port}');

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final a = await server.localAddresses();
    if (mounted) setState(() => addresses = a);
  }

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _copy(String t) async {
    await Clipboard.setData(ClipboardData(text: t));
    _msg('Copié.');
  }

  Future<void> _toggle() async {
    if (server.running) {
      await server.stop();
    } else {
      final p = int.tryParse(portCtl.text.trim()) ?? 0;
      if (p < 1024 || p > 65535) {
        _msg('Choisissez un port entre 1024 et 65535 (8080 par défaut).');
        return;
      }
      server.port = p;
      await server.saveConfig();
      final e = await server.start();
      if (e != null) _msg(e);
    }
    if (mounted) setState(() {});
  }

  Future<void> _regen() async {
    if (!await askSecurity(context, 'Création d’une nouvelle clé d’accès.')) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Créer une nouvelle clé d’accès ?'),
        content: const Text('Toutes les caisses seront refusées tant que la nouvelle clé n’y sera pas saisie (Paramètres, Réseau).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Créer la clé')),
        ],
      ),
    );
    if (ok == true) {
      await server.regenerateKey();
      if (app.serverUrl.startsWith('http://127.0.0.1')) {
        app.serverKey = server.key;
        app.touch();
      }
    }
  }

  Future<void> _test() async {
    final r = await server.selfTest();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Test du serveur'),
        content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [for (final l in r) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(l))])),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
      ),
    );
  }

  // Ce PC (le PC principal) se relie à son propre serveur.
  void _useHere() {
    if (!server.running) {
      _msg('Démarrez d’abord le serveur.');
      return;
    }
    app.serverUrl = 'http://127.0.0.1:${server.port}';
    app.serverKey = server.key;
    app.audit('PC relié au serveur intégré', app.serverUrl);
    app.queueSettings();
    app.syncNow();
    _msg('Ce PC est relié au serveur.');
  }

  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([server, app]),
        builder: (context, _) {
          final run = server.running;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Panel(
                title: 'Serveur du réseau : ${run ? 'EN MARCHE' : 'ARRÊTÉ'}',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Le PC principal (celui qui reste allumé) fait tourner le serveur. Les autres caisses saisissent son adresse et sa clé dans Paramètres > Réseau.', style: muted),
                  const SizedBox(height: 10),
                  Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    SizedBox(width: 120, child: TextField(controller: portCtl, enabled: !run, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port', isDense: true, border: OutlineInputBorder()))),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: run ? C.red : C.green),
                      onPressed: _toggle,
                      icon: Icon(run ? Icons.stop : Icons.play_arrow),
                      label: Text(run ? 'Arrêter le serveur' : 'Démarrer le serveur'),
                    ),
                    OutlinedButton(onPressed: run ? _test : null, child: const Text('Tester le serveur')),
                    OutlinedButton(onPressed: run ? _useHere : null, child: const Text('Relier ce PC à ce serveur')),
                  ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Démarrer le serveur automatiquement à l’ouverture de Mauzo'),
                    value: server.autoStart,
                    onChanged: (v) async {
                      server.autoStart = v;
                      await server.saveConfig();
                      if (mounted) setState(() {});
                    },
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Panel(
                title: 'Adresse à saisir dans les autres caisses',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (addresses.isEmpty) const Text('Aucune adresse réseau trouvée. Branchez ce PC au réseau ou au Wi‑Fi, puis actualisez.', style: muted),
                  for (final a in addresses)
                    Row(children: [
                      SelectableText('http://$a:${server.port}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.blue)),
                      IconButton(tooltip: 'Copier', onPressed: () => _copy('http://$a:${server.port}'), icon: const Icon(Icons.copy, size: 18)),
                    ]),
                  TextButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Actualiser')),
                  const Text('Test rapide : ouvrez cette adresse dans le navigateur d’une autre caisse. Si la page « Mauzo Serveur, en marche » s’affiche, le réseau est bon.', style: muted),
                ]),
              ),
              const SizedBox(height: 12),
              Panel(
                title: 'Clé d’accès de la boutique',
                child: Row(children: [
                  SelectableText(server.key, style: const TextStyle(fontFamily: 'Consolas', fontSize: 16, fontWeight: FontWeight.w700)),
                  IconButton(tooltip: 'Copier', onPressed: () => _copy(server.key), icon: const Icon(Icons.copy, size: 18)),
                  const Spacer(),
                  OutlinedButton(onPressed: _regen, child: const Text('Créer une nouvelle clé')),
                ]),
              ),
              const SizedBox(height: 12),
              Panel(
                title: 'Caisses connectées (${server.onlineCount} en ligne sur ${server.devices.length})',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (server.devices.isEmpty) const Text('Aucune caisse ne s’est encore connectée.', style: muted),
                  for (final d in server.devices.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Icon(Icons.circle, size: 10, color: d.online ? C.green : C.muted),
                        const SizedBox(width: 8),
                        Text(d.name, style: bold),
                        const SizedBox(width: 8),
                        Text('(${d.id})', style: muted),
                        const Spacer(),
                        Text('vue à ${_hm(d.lastSeen)}', style: muted),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              Panel(
                title: 'Données et sécurité du serveur',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${server.opCount} opération(s) enregistrée(s) · ${server.counts['sale'] ?? 0} vente(s) · ${server.counts['refund'] ?? 0} annulation(s)', style: bold),
                  const SizedBox(height: 4),
                  Text('Dossier : ${server.path}', style: muted),
                  Text(server.lastBackup == null ? 'Une sauvegarde automatique est faite chaque jour.' : 'Dernière sauvegarde : ${_hm(server.lastBackup!)}', style: muted),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(onPressed: () async => _msg(await server.backupNow()), icon: const Icon(Icons.save), label: const Text('Sauvegarder maintenant')),
                    OutlinedButton.icon(onPressed: server.openFolder, icon: const Icon(Icons.folder_open), label: const Text('Ouvrir le dossier')),
                    OutlinedButton.icon(onPressed: () async => _msg(await server.openFirewall()), icon: const Icon(Icons.shield), label: const Text('Autoriser dans le pare-feu')),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              Panel(
                title: 'Journal du serveur',
                child: Container(
                  width: double.infinity,
                  height: 180,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(8)),
                  child: ListView(children: [for (final l in server.logs.take(120)) Text(l, style: const TextStyle(fontFamily: 'Consolas', fontSize: 12))]),
                ),
              ),
            ]),
          );
        },
      );
}
