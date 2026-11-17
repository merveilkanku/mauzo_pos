import 'package:flutter/material.dart';
import '../core.dart';
import '../printing_service.dart';
import '../state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  final shop = TextEditingController(text: app.shop);
  final rate = TextEditingController(text: '${app.rate.round()}');
  final vat = TextEditingController(text: '${(app.vatRate * 100).round()}');
  final fund = TextEditingController(text: '${app.openingFloat.round()}');
  final idle = TextEditingController(text: '${app.idleMinutes}');
  final ops = TextEditingController(text: app.operators.join(', '));
  final url = TextEditingController(text: app.serverUrl);
  final key = TextEditingController(text: app.serverKey);
  List<String> printers = [];
  List<Map<String, dynamic>> devices = [];
  String testResult = '';

  double _d(TextEditingController c, double d) => double.tryParse(c.text.replaceAll(',', '.')) ?? d;

  Future<void> _save() async {
    final serverChanged = url.text.trim() != app.serverUrl || key.text.trim() != app.serverKey;
    if (serverChanged && !await askSecurity(context, 'Modification de la configuration du serveur.')) return;
    final oldRate = app.rate;
    app.shop = shop.text.trim().isEmpty ? app.shop : shop.text.trim();
    app.rate = _d(rate, app.rate) <= 0 ? app.rate : _d(rate, app.rate);
    app.vatRate = _d(vat, app.vatRate * 100) / 100;
    app.openingFloat = _d(fund, app.openingFloat);
    app.idleMinutes = int.tryParse(idle.text) ?? app.idleMinutes;
    final list = ops.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (list.isNotEmpty) app.operators = list;
    app.serverUrl = url.text.trim();
    app.serverKey = key.text.trim();
    if (oldRate != app.rate) app.audit('taux de change modifié', '${oldRate.round()} → ${app.rate.round()} FC pour 1 \$');
    app.audit('réglages modifiés', serverChanged ? 'dont la configuration du serveur' : '');
    app.queueSettings();
    if (app.serverUrl.isNotEmpty) app.syncNow();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paramètres enregistrés.')));
  }

  Future<void> _wipe() async {
    if (!await askSecurity(context, 'Effacement des données de démonstration.')) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vider les données de démonstration ?'),
        content: const Text('Articles, clients, ventes, sessions et journal de CE PC seront effacés pour repartir à zéro. Les utilisateurs, caisses et réglages sont conservés.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tout effacer')),
        ],
      ),
    );
    if (ok == true) app.wipeDemo();
  }

  // Le gérant définit (ou change) son mot de sécurité, distinct de son code de connexion.
  Future<void> _securityWord() async {
    final u = app.user;
    if (u == null || u.role != Role.gerant) return;
    if (u.hasSecurity && !await askSecurity(context, 'Pour changer votre mot de sécurité, saisissez l’actuel.')) return;
    if (!mounted) return;
    final a = TextEditingController();
    final b = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mon mot de sécurité'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Il sert à autoriser les actions sensibles (suppression de ligne, annulation de facture, serveur). Ne le communiquez pas aux caissiers.', style: muted),
            const SizedBox(height: 10),
            TextField(controller: a, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Nouveau mot de sécurité (6 caractères ou plus)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: b, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmer', border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    String? err;
    if (a.text.length < 6) err = 'Au moins 6 caractères.';
    if (err == null && a.text != b.text) err = 'Les deux saisies sont différentes.';
    if (err == null && u.verify(a.text)) err = 'Choisissez un mot différent de votre code de connexion.';
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    u.setSecurity(a.text);
    app.audit('mot de sécurité modifié', u.name);
    app.queueUser(u);
  }

  Widget _f(String l, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(controller: c, decoration: InputDecoration(labelText: l, border: const OutlineInputBorder())),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(children: [
                  Panel(
                    title: 'Boutique et réglages',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _f('Nom de la boutique (affiché sur les tickets)', shop),
                      _f('Taux : 1 \$ = ... FC (enregistré avec chaque clôture)', rate),
                      _f('TVA en % (0 pour désactiver, à confirmer avec un comptable)', vat),
                      _f('Fond de caisse par défaut (\$)', fund),
                      _f('Opérateurs mobile money (séparés par des virgules)', ops),
                      FilledButton(onPressed: _save, child: const Text('Enregistrer')),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Panel(
                    title: 'Sécurité',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      DropdownButtonFormField<String>(
                        value: app.lineDeletePolicy,
                        decoration: const InputDecoration(labelText: 'Suppression de lignes par le caissier', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'forbidden', child: Text('Interdite')),
                          DropdownMenuItem(value: 'authorized', child: Text('Autorisée après le mot de sécurité du gérant')),
                        ],
                        onChanged: (v) async {
                          if (!await askSecurity(context, 'Modification de la règle de suppression de lignes.')) return;
                          app.lineDeletePolicy = v ?? app.lineDeletePolicy;
                          app.audit('règle de suppression modifiée', app.lineDeletePolicy);
                          app.queueSettings();
                        },
                      ),
                      const SizedBox(height: 10),
                      _f('Déconnexion automatique après … minutes d’inactivité (0 = jamais)', idle),
                      Text(
                        app.user?.role == Role.gerant
                            ? (app.user!.hasSecurity ? 'Votre mot de sécurité est défini.' : 'Vous n’avez pas encore de mot de sécurité : les autorisations utilisent votre code de connexion.')
                            : 'Le mot de sécurité est géré par le gérant.',
                        style: muted,
                      ),
                      const SizedBox(height: 8),
                      if (app.user?.role == Role.gerant) OutlinedButton.icon(onPressed: _securityWord, icon: const Icon(Icons.key), label: Text(app.user!.hasSecurity ? 'Changer mon mot de sécurité' : 'Définir mon mot de sécurité')),
                      const SizedBox(height: 8),
                      const Text('La validation par empreinte digitale n’est pas disponible : elle demande un lecteur compatible et un module spécifique.', style: muted),
                    ]),
                  ),
                ]),
              ),
            ),
            Expanded(
              child: Column(children: [
                Panel(
                  title: 'Réseau : plusieurs PC qui communiquent',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Un PC fait tourner le serveur Mauzo. Chaque caisse y entre la même adresse et la même clé : articles, stock, ventes, sessions, clôtures, utilisateurs et caisses sont alors partagés.', style: muted),
                    const SizedBox(height: 10),
                    _f('Adresse du serveur, ex. http://192.168.1.10:8080 (vide = mode local)', url),
                    _f('Clé d’accès de la boutique', key),
                    Row(children: [
                      OutlinedButton(
                        onPressed: () async {
                          setState(() => testResult = 'Test en cours…');
                          final r = await app.testServer(url.text, key.text);
                          if (mounted) setState(() => testResult = r);
                        },
                        child: const Text('Tester la connexion'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(testResult, style: bold)),
                    ]),
                    const SizedBox(height: 8),
                    Text('Ce PC : ${app.deviceName} (${app.deviceId})', style: muted),
                    Text(app.syncStatus, style: muted),
                    Text('${app.pendingSync.length} opération(s) en attente d’envoi', style: muted),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton(onPressed: app.syncNow, child: const Text('Synchroniser maintenant')),
                      OutlinedButton(
                        onPressed: () async {
                          final l = await app.fetchDevices();
                          if (mounted) setState(() => devices = l);
                        },
                        child: const Text('Voir les PC connectés'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          if (!await askSecurity(context, 'Envoi des données de base au serveur.')) return;
                          app.queueFullState();
                        },
                        child: const Text('Envoyer les données de base'),
                      ),
                    ]),
                    for (final d in devices) kv('${d['name'] ?? '?'} (${d['device']})', 'vu ${d['last_seen']}'),
                    const SizedBox(height: 6),
                    const Text('Premier PC : saisissez l’adresse et la clé, enregistrez, puis « Envoyer les données de base ». Autres PC : installez, videz les données de démonstration, saisissez la même adresse et la même clé.', style: muted),
                  ]),
                ),
                const SizedBox(height: 12),
                Panel(
                  title: 'Impression',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    DropdownButtonFormField<int>(
                      value: app.paperMm,
                      decoration: const InputDecoration(labelText: 'Papier du ticket', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 58, child: Text('Imprimante thermique 58 mm')),
                        DropdownMenuItem(value: 80, child: Text('Imprimante thermique 80 mm')),
                        DropdownMenuItem(value: 210, child: Text('A4')),
                      ],
                      onChanged: (v) {
                        app.paperMm = v ?? app.paperMm;
                        app.touch();
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: Text(app.printerName.isEmpty ? 'Imprimante : aucune choisie (fenêtre d’impression Windows)' : 'Imprimante : ${app.printerName}', style: bold)),
                      OutlinedButton(
                        onPressed: () async {
                          final l = await printerNames();
                          if (mounted) setState(() => printers = l);
                        },
                        child: const Text('Détecter'),
                      ),
                    ]),
                    if (printers.isNotEmpty)
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final p in printers)
                          ChoiceChip(
                            label: Text(p),
                            selected: app.printerName == p,
                            onSelected: (_) {
                              app.printerName = p;
                              app.touch();
                            },
                          ),
                      ]),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Impression automatique après la vente'),
                      subtitle: const Text('Envoie le ticket à l’imprimante choisie, sans aperçu'),
                      value: app.autoPrint,
                      onChanged: (v) {
                        app.autoPrint = v;
                        app.touch();
                      },
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final e = await printTest();
                        if (e != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e)));
                      },
                      icon: const Icon(Icons.print),
                      label: const Text('Test d’impression'),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                Panel(
                  title: 'Données',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Enregistrées sur cet ordinateur : ${app.dataDir}', style: muted),
                    const SizedBox(height: 8),
                    OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: C.red), onPressed: _wipe, child: const Text('Vider les données de démonstration')),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      );
}
