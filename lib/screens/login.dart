import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  User? u;
  Caisse? caisse;
  final secret = TextEditingController();
  String err = '';

  void _go() {
    final x = u;
    if (x == null) return;
    final e = app.login(x, secret.text.trim(), caisse: caisse);
    if (e != null) setState(() => err = e);
  }

  @override
  Widget build(BuildContext context) {
    final list = app.users.where((x) => x.active).toList();
    if (list.isEmpty) return const Scaffold(body: Center(child: Text('Aucun utilisateur actif.')));
    if (u == null || !list.contains(u)) u = list.first;
    final cs = app.caisses.where((c) => c.active && (u!.caisses.isEmpty || u!.caisses.contains(c.id))).toList();
    if (cs.isNotEmpty && (caisse == null || !cs.contains(caisse))) caisse = cs.first;
    return Scaffold(
      backgroundColor: C.navy,
      body: Center(
        child: SizedBox(
          width: 420,
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const MauzoMark(size: 56),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Mauzo', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: C.text)),
                  Text(app.shop, style: muted),
                ]),
              ]),
              const SizedBox(height: 16),
              DropdownButtonFormField<User>(
                value: u,
                decoration: const InputDecoration(labelText: 'Utilisateur', border: OutlineInputBorder()),
                items: [for (final x in list) DropdownMenuItem(value: x, child: Text('${x.name} (${x.roleLabel})'))],
                onChanged: (v) => setState(() {
                  u = v;
                  err = '';
                }),
              ),
              if (u!.role == Role.caissier) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<Caisse>(
                  value: caisse,
                  decoration: const InputDecoration(labelText: 'Caisse', border: OutlineInputBorder()),
                  items: [for (final c in cs) DropdownMenuItem(value: c, child: Text(c.name))],
                  onChanged: (v) => setState(() => caisse = v),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: secret,
                obscureText: true,
                autofocus: true,
                onSubmitted: (_) => _go(),
                decoration: InputDecoration(
                  labelText: u!.login == 'pin' ? 'Code PIN' : (u!.login == 'password' ? 'Mot de passe' : 'Code PIN ou mot de passe'),
                  border: const OutlineInputBorder(),
                  errorText: err.isEmpty ? null : err,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: _go, child: const Text('Ouvrir la session'))),
              const SizedBox(height: 10),
              const Text('Démo : PIN 1234 (caissier), 2222 (employé), 0000 (gérant). À changer avant tout usage réel.', style: muted),
            ]),
          ),
        ),
      ),
    );
  }
}
