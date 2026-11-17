import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

/// Utilisateurs, permissions, caisses et historique des connexions (réservé au gérant).
class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  Future<void> _userDialog(BuildContext context, {User? u}) async {
    final name = TextEditingController(text: u?.name ?? '');
    final pin = TextEditingController();
    final pw = TextEditingController();
    var role = u?.role ?? Role.caissier;
    var login = u?.login ?? 'pin';
    var active = u?.active ?? true;
    final perms = {...(u?.perms ?? <String>{})};
    final cs = {...(u?.caisses ?? <String>[])};
    final self = u != null && u == app.user;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(u == null ? 'Nouvel utilisateur' : 'Modifier ${u.name}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                DropdownButtonFormField<Role>(
                  value: role,
                  decoration: InputDecoration(labelText: self ? 'Rôle (vous ne pouvez pas modifier le vôtre)' : 'Rôle', border: const OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: Role.caissier, child: Text('Caissier')),
                    DropdownMenuItem(value: Role.employe, child: Text('Employé')),
                    DropdownMenuItem(value: Role.gerant, child: Text('Gérant')),
                  ],
                  onChanged: self ? null : (v) => setS(() => role = v ?? role),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: login,
                  decoration: const InputDecoration(labelText: 'Méthode de connexion', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'pin', child: Text('Code PIN uniquement')),
                    DropdownMenuItem(value: 'password', child: Text('Mot de passe uniquement')),
                    DropdownMenuItem(value: 'both', child: Text('PIN ou mot de passe')),
                  ],
                  onChanged: (v) => setS(() => login = v ?? login),
                ),
                const SizedBox(height: 8),
                TextField(controller: pin, obscureText: true, decoration: InputDecoration(labelText: u == null ? 'Code PIN (4 chiffres ou plus)' : 'Nouveau PIN (vide = inchangé)', border: const OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: pw, obscureText: true, decoration: InputDecoration(labelText: u == null ? 'Mot de passe (6 caractères ou plus)' : 'Nouveau mot de passe (vide = inchangé)', border: const OutlineInputBorder())),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Compte actif'), value: active, onChanged: self ? null : (v) => setS(() => active = v)),
                if (role != Role.gerant) ...[
                  const Text('Permissions', style: bold),
                  for (final e in permLabels.entries)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.value),
                      value: perms.contains(e.key),
                      onChanged: (v) => setS(() => v == true ? perms.add(e.key) : perms.remove(e.key)),
                    ),
                ],
                if (role == Role.caissier) ...[
                  const SizedBox(height: 6),
                  const Text('Caisses autorisées (aucune coche = toutes)', style: bold),
                  for (final c in app.caisses)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.name),
                      value: cs.contains(c.id),
                      onChanged: (v) => setS(() => v == true ? cs.add(c.id) : cs.remove(c.id)),
                    ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    String? err;
    final n = name.text.trim();
    if (n.isEmpty) err = 'Indiquez un nom.';
    if (err == null && app.users.any((x) => x != u && x.name.toLowerCase() == n.toLowerCase())) err = 'Ce nom existe déjà.';
    if (err == null && pin.text.isNotEmpty && (pin.text.length < 4 || int.tryParse(pin.text) == null)) err = 'Le PIN doit avoir 4 chiffres ou plus.';
    if (err == null && pw.text.isNotEmpty && pw.text.length < 6) err = 'Le mot de passe doit avoir 6 caractères ou plus.';
    final hasPin = pin.text.isNotEmpty || (u?.pinHash.isNotEmpty ?? false);
    final hasPw = pw.text.isNotEmpty || (u?.pwHash.isNotEmpty ?? false);
    if (err == null && login != 'password' && !hasPin && !(login == 'both' && hasPw)) err = 'Définissez un PIN.';
    if (err == null && login != 'pin' && !hasPw && !(login == 'both' && hasPin)) err = 'Définissez un mot de passe.';
    final othersManager = app.users.any((x) => x != u && x.role == Role.gerant && x.active);
    if (err == null && !(role == Role.gerant && active) && !othersManager && (u == null || u.role == Role.gerant)) err = 'Il doit rester au moins un gérant actif.';
    if (err != null) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final target = u ?? User(n, role);
    target.name = n;
    target.role = role;
    target.login = login;
    target.active = active;
    target.perms = perms;
    target.caisses = cs.toList();
    if (pin.text.isNotEmpty) target.setPin(pin.text);
    if (pw.text.isNotEmpty) target.setPassword(pw.text);
    if (u == null) app.users.add(target);
    app.audit(u == null ? 'utilisateur créé' : 'utilisateur modifié', '${target.name} (${target.roleLabel})${pin.text.isNotEmpty || pw.text.isNotEmpty ? ', identifiants modifiés' : ''}');
    app.queueUser(target);
  }

  // Le gérant peut créer une ou plusieurs caisses d'un coup : Caisse 1, Caisse 2, Caisse 3…
  Future<void> _caisseDialog(BuildContext context) async {
    final n = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter des caisses'),
        content: TextField(controller: n, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nombre de caisses à ajouter (1 à 20)', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Créer')),
        ],
      ),
    );
    if (ok != true) return;
    final count = (int.tryParse(n.text) ?? 1).clamp(1, 20).toInt();
    var next = 1;
    for (final c in app.caisses) {
      final m = RegExp(r'^Caisse (\d+)$').firstMatch(c.name);
      if (m != null) {
        final v = int.parse(m.group(1)!);
        if (v >= next) next = v + 1;
      }
    }
    for (var i = 0; i < count; i++) {
      final c = Caisse('c${DateTime.now().microsecondsSinceEpoch}$i', 'Caisse ${next + i}');
      app.caisses.add(c);
      app.queueCaisse(c);
    }
    app.audit('caisses créées', '$count caisse(s)');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          const loginActions = {'connexion', 'échec de connexion', 'ouverture de caisse', 'clôture de caisse', 'déconnexion', 'déconnexion automatique (inactivité)'};
          final logins = app.audits.where((a) => loginActions.contains(a.action)).take(40).toList();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Panel(
                title: 'Utilisateurs et permissions',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FilledButton.icon(onPressed: () => _userDialog(context), icon: const Icon(Icons.person_add), label: const Text('Nouvel utilisateur')),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Nom')),
                          DataColumn(label: Text('Rôle')),
                          DataColumn(label: Text('Connexion')),
                          DataColumn(label: Text('Permissions')),
                          DataColumn(label: Text('Statut')),
                          DataColumn(label: Text('')),
                        ],
                        rows: [
                          for (final u in app.users)
                            DataRow(cells: [
                              DataCell(Text(u.name, style: bold)),
                              DataCell(Text(u.roleLabel)),
                              DataCell(Text('${u.login == 'pin' ? 'PIN' : (u.login == 'password' ? 'Mot de passe' : 'PIN ou mot de passe')}${u.role == Role.gerant ? (u.hasSecurity ? ' · mot de sécurité défini' : ' · pas de mot de sécurité') : ''}')),
                              DataCell(Text(u.role == Role.gerant ? 'Toutes' : (u.perms.isEmpty ? 'Aucune' : u.perms.map((p) => permLabels[p] ?? p).join(', ')), overflow: TextOverflow.ellipsis)),
                              DataCell(u.active ? const Pill('Actif', C.green, C.greenSoft) : const Pill('Désactivé', C.red, C.redSoft)),
                              DataCell(TextButton(onPressed: () => _userDialog(context, u: u), child: const Text('Modifier'))),
                            ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Les PIN et mots de passe sont enregistrés sous forme hachée. Le caissier ne peut ni clôturer, ni modifier son rôle, ni ouvrir les paramètres.', style: muted),
                ]),
              ),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Panel(
                      title: 'Caisses',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        OutlinedButton.icon(onPressed: () => _caisseDialog(context), icon: const Icon(Icons.add), label: const Text('Ajouter des caisses')),
                        const SizedBox(height: 6),
                        for (final c in app.caisses)
                          SwitchListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(c.name, style: bold),
                            subtitle: Text(app.sessions.any((s) => s.open && s.caisseId == c.id) ? 'Session ouverte' : 'Fermée'),
                            value: c.active,
                            onChanged: (v) {
                              if (!v && app.sessions.any((s) => s.open && s.caisseId == c.id)) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clôturez d’abord la session de cette caisse.')));
                                return;
                              }
                              c.active = v;
                              app.queueCaisse(c);
                            },
                          ),
                      ]),
                    ),
                  ),
                ),
                Expanded(
                  child: Panel(
                    title: 'Historique des connexions et sessions',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (logins.isEmpty) const Text('Aucun événement.', style: muted),
                      for (final a in logins) Text('${dateFr(a.at)} ${timeFr(a.at)} · ${a.by} · ${a.action}${a.detail.isEmpty || a.detail == a.by ? '' : ' (${a.detail})'}', style: const TextStyle(fontSize: 12.5)),
                    ]),
                  ),
                ),
              ]),
            ]),
          );
        },
      );
}
