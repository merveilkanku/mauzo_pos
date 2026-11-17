import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core.dart';
import '../printing_service.dart';
import '../state.dart';

class _Entry {
  _Entry(this.p, this.tendered);
  final Payment p;
  final double tendered; // montant remis par le client, en USD équivalent
}

/// Écran de caisse : scan, ticket, paiement (mixte possible), impression, ventes en attente.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key, this.kiosk = false});
  final bool kiosk; // true : plein écran du caissier, avec son propre bandeau
  @override
  State<PosScreen> createState() => _PosState();
}

class _PosState extends State<PosScreen> {
  final scan = TextEditingController();
  final focus = FocusNode();
  final fUsd = TextEditingController();
  final fCdf = TextEditingController(text: '0');
  Caisse? openCaisse;
  Timer? _t;
  String? selId;
  String msg = '';
  Color msgFg = C.red, msgBg = C.redSoft;
  Product? lastP;
  String query = '';
  bool _askedCustomer = false;
  final Customer _noCustomer = Customer('', '');

  @override
  void initState() {
    super.initState();
    fUsd.text = '${app.openingFloat.round()}';
    _t = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    if (widget.kiosk) WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _notice(String t, {Color fg = C.red, Color bg = C.redSoft}) => setState(() {
        msg = t;
        msgFg = fg;
        msgBg = bg;
      });

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  void _submit(String raw) {
    var v = raw.trim();
    scan.clear();
    setState(() => query = '');
    if (v.isEmpty) {
      focus.requestFocus();
      return;
    }
    var qty = 1;
    final m = RegExp(r'^(\d{1,3})\s*[*xX]\s*(.+)$').firstMatch(v);
    if (m != null) {
      qty = int.parse(m.group(1)!);
      v = m.group(2)!.trim();
    }
    final p = app.find(v);
    if (p == null) {
      app.unknownCode(v);
      _notice('Code inconnu : $v. Le gérant a été prévenu.');
    } else {
      _add(p, qty);
    }
    focus.requestFocus();
  }

  void _add(Product p, int qty) {
    final r = app.addQty(p, qty);
    switch (r) {
      case AddResult.out:
        _notice('ARTICLE EN RUPTURE : ${p.name}. Non ajouté au ticket. Le gérant est prévenu.');
        break;
      case AddResult.notEnough:
        _notice('Stock insuffisant : il ne reste que ${p.stock} × ${p.name}.');
        break;
      case AddResult.low:
        selId = p.id;
        lastP = p;
        _notice('Ajouté. Stock bas : il reste ${p.stock - (app.cart[p.id]?.qty ?? 0)} après ce ticket.', fg: C.amber, bg: C.amberSoft);
        break;
      case AddResult.ok:
        selId = p.id;
        lastP = p;
        setState(() => msg = '');
        break;
    }
  }

  Product? _selProduct() {
    final id = selId;
    if (id == null) return null;
    for (final l in app.cart.values) {
      if (l.p.id == id) return l.p;
    }
    return null;
  }

  // Suppression d'une ligne : le gérant directement, les autres selon la règle (interdite ou validée par le gérant).
  Future<void> _remove(Product p, {int qty = -1}) async {
    if (app.user!.role == Role.gerant) {
      final e = app.removeLine(p, qty: qty);
      if (e != null) _notice(e);
      return;
    }
    if (app.lineDeletePolicy == 'forbidden') {
      _notice('La suppression de lignes est interdite par le gérant.');
      return;
    }
    final reason = TextEditingController();
    final pin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Autorisation du gérant requise'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Retirer ${qty < 0 ? 'la ligne' : '1 unité'} : ${p.name}', style: bold),
            const SizedBox(height: 10),
            TextField(controller: reason, autofocus: true, decoration: const InputDecoration(labelText: 'Motif (obligatoire)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(
              controller: pin,
              obscureText: true,
              onSubmitted: (_) => Navigator.pop(ctx, true),
              decoration: const InputDecoration(labelText: 'Mot de sécurité du gérant', border: OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Autoriser')),
        ],
      ),
    );
    if (ok == true) {
      final e = app.removeLine(p, qty: qty, reason: reason.text, secret: pin.text.trim());
      if (e != null) _notice(e);
    }
    focus.requestFocus();
  }

  Future<void> _editPrice(Line l) async {
    if (!app.can('price')) return;
    final c = TextEditingController(text: l.unit.toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Prix de ${l.p.name}'),
        content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Prix unitaire (\$)', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Appliquer')),
        ],
      ),
    );
    if (ok == true) {
      final e = app.setLinePrice(l.p, double.tryParse(c.text.replaceAll(',', '.')) ?? 0);
      if (e != null) _notice(e);
    }
    focus.requestFocus();
  }

  void _hold() {
    if (app.cart.isEmpty) return;
    app.hold();
    _askedCustomer = false;
    setState(() {
      selId = null;
      lastP = null;
      msg = '';
    });
  }

  Future<void> _resume() async {
    if (app.held.isEmpty) return;
    if (app.cart.isNotEmpty) {
      _notice('Terminez ou mettez en attente le ticket en cours avant de reprendre.', fg: C.amber, bg: C.amberSoft);
      return;
    }
    final i = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(title: const Text('Tickets en attente'), children: [
        for (var k = 0; k < app.held.length; k++)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, k),
            child: Text('Ticket ${k + 1} · ${app.held[k].values.fold(0, (a, l) => a + l.qty)} article(s) · ${usd(app.held[k].values.fold(0.0, (a, l) => a + l.total))}'),
          ),
      ]),
    );
    if (i != null) app.resume(i);
    focus.requestFocus();
  }

  // Cherche un client par numéro WhatsApp. Si le numéro n'est pas enregistré, propose de créer le client.
  Future<Customer?> _customerDialog(String title, {bool allowClear = false}) {
    final phone = TextEditingController();
    final name = TextEditingController();
    Customer? found;
    var searched = false;
    var err = '';
    return showDialog<Customer>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        void lookup() {
          setS(() {
            searched = normPhone(phone.text).replaceAll('+', '').length >= 9;
            found = searched ? app.findByPhone(phone.text) : null;
            err = '';
          });
        }

        final f = found;
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: phone,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => lookup(),
                  onSubmitted: (_) {
                    final x = found;
                    if (x != null) Navigator.pop(ctx, x);
                  },
                  decoration: const InputDecoration(labelText: 'Numéro WhatsApp (ex. 0970000000 ou +243970000000)', prefixIcon: Icon(Icons.chat), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                if (f != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: C.greenSoft, borderRadius: BorderRadius.circular(10)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(f.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      Text('Niveau ${app.tierOf(f)} · ${f.points} points · ${f.visits} visite(s)'),
                      if (f.debt > 0) Text('Ardoise : ${usd(f.debt)}', style: const TextStyle(color: C.red, fontWeight: FontWeight.w700)),
                      if (app.rewards.any((r) => f.points >= r.cost)) const Text('Une récompense est disponible.', style: TextStyle(color: C.green, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: () => Navigator.pop(ctx, f), child: const Text('Choisir ce client')),
                    ]),
                  )
                else if (searched)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: C.amberSoft, borderRadius: BorderRadius.circular(10)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Ce numéro n’est pas encore enregistré. Créer un nouveau client ?', style: bold),
                      const SizedBox(height: 8),
                      TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom du client', border: OutlineInputBorder())),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () {
                          final c = app.createCustomer(name.text, phone.text);
                          if (c == null) {
                            setS(() => err = 'Indiquez le nom du client.');
                          } else {
                            Navigator.pop(ctx, c);
                          }
                        },
                        child: Text('Créer le client${app.welcomePoints > 0 ? ' (+${app.welcomePoints} points offerts)' : ''}'),
                      ),
                    ]),
                  ),
                if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err, style: const TextStyle(color: C.red, fontWeight: FontWeight.w700))),
                const Divider(),
                const Text('Clients enregistrés', style: muted),
                SizedBox(
                  height: 150,
                  child: ListView(children: [
                    for (final c in app.customers.take(40))
                      ListTile(dense: true, title: Text(c.name, style: bold), subtitle: Text('${c.phone} · ${c.points} pts · ${app.tierOf(c)}'), onTap: () => Navigator.pop(ctx, c)),
                  ]),
                ),
              ]),
            ),
          ),
          actions: [
            if (allowClear) TextButton(onPressed: () => Navigator.pop(ctx, _noCustomer), child: const Text('Retirer le client')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ],
        );
      }),
    );
  }

  Future<void> _pickCustomer() async {
    final before = app.customers.length;
    final c = await _customerDialog('Client : numéro WhatsApp', allowClear: app.customer != null);
    if (c != null) {
      if (identical(c, _noCustomer)) {
        app.setCustomer(null);
      } else {
        app.setCustomer(c);
        if (app.customers.length > before) {
          _notice('Client créé : ${c.name}. Bonus de bienvenue : ${app.welcomePoints} points.', fg: C.green, bg: C.greenSoft);
        }
      }
    }
    focus.requestFocus();
  }

  Future<void> _rewards() async {
    final c = app.customer;
    if (c == null) return;
    final picked = await showDialog<Reward>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${c.name} : ${c.points} points'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (app.rewards.isEmpty) const Text('Aucune récompense définie.', style: muted),
            for (final rw in app.rewards)
              ListTile(
                title: Text(rw.name, style: bold),
                subtitle: Text('${rw.cost} points'),
                trailing: FilledButton(onPressed: c.points >= rw.cost ? () => Navigator.pop(ctx, rw) : null, child: const Text('Utiliser')),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
      ),
    );
    if (picked != null) {
      final e = app.applyReward(picked);
      if (e != null) _notice(e);
    }
    focus.requestFocus();
  }

  // Facture nominative : si aucun client n'est rattaché, on propose de le choisir ou de le créer (numéro WhatsApp).
  Future<void> _invoiceFor(Sale s) async {
    if (s.customerKey.isEmpty) {
      final c = await _customerDialog('Facture : client à rattacher');
      if (c == null) return;
      final e = app.attachCustomer(s, c);
      if (e != null) {
        _snack(e);
        return;
      }
    }
    await _print(s, a4: true);
  }

  Future<void> _cancel() async {
    if (app.cart.isEmpty) return;
    if (app.user!.role != Role.gerant && app.lineDeletePolicy == 'forbidden') {
      _notice('L’annulation du ticket est interdite par le gérant. Mettez-le en attente (F2).');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler le ticket ?'),
        content: const Text('Tous les articles du ticket en cours seront retirés. Pour garder le ticket, utilisez « En attente ».'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui, annuler')),
        ],
      ),
    );
    if (ok == true) {
      app.audit('ticket annulé avant paiement', '${app.cart.length} ligne(s), ${usd(app.total)}');
      app.clear();
      _askedCustomer = false;
      setState(() {
        selId = null;
        lastP = null;
        msg = '';
      });
    }
    focus.requestFocus();
  }

  Future<void> _print(Sale s, {bool a4 = false, bool direct = false}) async {
    final err = await printSale(s, a4: a4, direct: direct);
    if (err != null && mounted) _snack(err);
  }

  // Paiement : un ou plusieurs moyens (espèces USD/CDF, mobile money par opérateur, carte, ardoise).
  Future<void> _pay([PayMethod? start]) async {
    if (app.cart.isEmpty) {
      _notice('Le ticket est vide. Scannez un article.', fg: C.amber, bg: C.amberSoft);
      return;
    }
    // Propose d'ajouter le client (numéro WhatsApp) avant de payer, pour qu'il gagne des points.
    if (app.customer == null && app.askCustomerAtPayment && !_askedCustomer) {
      _askedCustomer = true;
      final add = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Client fidélité ?'),
          content: const Text('Ajoutez le numéro WhatsApp du client : il gagnera des points sur cet achat. Si le numéro n’est pas enregistré, vous pourrez créer le client.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuer sans client')),
            FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Ajouter le client')),
          ],
        ),
      );
      if (add == true) await _pickCustomer();
      if (app.cart.isEmpty) return;
    }
    final total = app.total;
    final entries = <_Entry>[];
    PayMethod m = start ?? PayMethod.cashUsd;
    String op = app.operators.first;
    String cur = 'USD';
    String err = '';
    final amount = TextEditingController();
    final sale = await showDialog<Sale>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final paid = entries.fold(0.0, (a, e) => a + e.p.usd);
        final rem = total - paid < 0.005 ? 0.0 : total - paid;
        final tendered = entries.fold(0.0, (a, e) => a + e.tendered);
        final change = tendered - paid;
        final isCash = m == PayMethod.cashUsd || m == PayMethod.cashCdf;
        final c = m == PayMethod.cashCdf ? 'CDF' : (m == PayMethod.mobile ? cur : 'USD');
        final remC = c == 'CDF' ? rem * app.rate : rem;

        void add() {
          final a = double.tryParse(amount.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
          if (a <= 0 || rem <= 0) return;
          if (m == PayMethod.credit && app.customer == null) {
            setS(() => err = 'Rattachez d’abord un client au ticket (touche F4).');
            return;
          }
          final tUsd = c == 'CDF' ? a / app.rate : a;
          final net = tUsd > rem ? rem : tUsd;
          final netAmt = c == 'CDF' ? net * app.rate : net;
          entries.add(_Entry(Payment(m, c, netAmt, net, operator: m == PayMethod.mobile ? op : ''), isCash ? tUsd : net));
          amount.clear();
          setS(() => err = '');
        }

        return AlertDialog(
          title: Text('Paiement · ${usd(total)}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final x in PayMethod.values)
                    ChoiceChip(
                      avatar: Icon(x.icon, size: 18),
                      label: Text(x.label),
                      selected: m == x,
                      onSelected: (_) => setS(() {
                        m = x;
                        amount.clear();
                        err = '';
                      }),
                    ),
                ]),
                if (m == PayMethod.mobile) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final o in app.operators) ChoiceChip(label: Text(o), selected: op == o, onSelected: (_) => setS(() => op = o)),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    for (final x in ['USD', 'CDF']) ChoiceChip(label: Text(x), selected: cur == x, onSelected: (_) => setS(() => cur = x)),
                  ]),
                ],
                const SizedBox(height: 12),
                Text('Reste à payer : ${usd(rem)}  (${cdf(rem * app.rate)})', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                if (rem > 0) ...[
                  TextField(
                    controller: amount,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => add(),
                    decoration: InputDecoration(labelText: 'Montant ($c)', border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    ActionChip(label: const Text('Reste à payer'), onPressed: () => setS(() => amount.text = c == 'CDF' ? remC.toStringAsFixed(0) : remC.toStringAsFixed(2))),
                    if (isCash)
                      for (final b in (c == 'CDF' ? [5000, 10000, 20000, 50000] : [5, 10, 20, 50, 100]))
                        ActionChip(label: Text('$b'), onPressed: () => setS(() => amount.text = '$b')),
                  ]),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: add, icon: const Icon(Icons.add), label: const Text('Ajouter ce paiement')),
                ],
                if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err, style: const TextStyle(color: C.red, fontWeight: FontWeight.w700))),
                const SizedBox(height: 8),
                for (var i = 0; i < entries.length; i++)
                  Row(children: [
                    Expanded(child: Text('${entries[i].p.label} : ${money(entries[i].p.amount, entries[i].p.currency)}', style: bold)),
                    IconButton(onPressed: () => setS(() => entries.removeAt(i)), icon: const Icon(Icons.close, size: 18)),
                  ]),
                if (change > 0.004)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Monnaie à rendre : ${usd(change)}  (${cdf(change * app.rate)})', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.green)),
                  ),
                if (m == PayMethod.credit)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(app.customer == null ? 'Client requis pour l’ardoise (F4).' : 'Ardoise de ${app.customer!.name} : ${usd(app.customer!.debt)} + ce ticket.', style: muted),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: C.green),
              onPressed: rem <= 0.005 && entries.isNotEmpty
                  ? () {
                      final s = app.checkout([for (final e in entries) e.p], 'Client comptant', received: tendered);
                      if (s == null) {
                        setS(() => err = 'Paiement refusé : session fermée ou client manquant.');
                      } else {
                        Navigator.pop(ctx, s);
                      }
                    }
                  : null,
              child: const Text('Valider la vente'),
            ),
          ],
        );
      }),
    );
    if (sale != null) {
      _askedCustomer = false;
      setState(() {
        selId = null;
        lastP = null;
        msg = '';
      });
      if (app.autoPrint) await _print(sale, direct: true);
      await _done(sale);
    }
    focus.requestFocus();
  }

  // Après la vente : F5 imprime, Entrée démarre une nouvelle facture (panier réinitialisé, nouveau numéro).
  Future<void> _done(Sale s) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.f5): () => _print(s)},
            child: AlertDialog(
              title: Text('Vente validée · ticket n° ${s.no}'),
              content: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (s.customerKey.isNotEmpty && app.loyaltyNote.isNotEmpty && identical(app.lastSale, s))
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: C.greenSoft, borderRadius: BorderRadius.circular(8)),
                      child: Text(app.loyaltyNote, style: const TextStyle(color: C.green, fontWeight: FontWeight.w700)),
                    ),
                  SelectableText(receipt(s), style: mono),
                ]),
              ),
              actions: [
                if (s.customerKey.isEmpty)
                  TextButton(
                    onPressed: () async {
                      final c = await _customerDialog('Ajouter le client à cette vente');
                      if (c != null) {
                        final e = app.attachCustomer(s, c);
                        if (e != null) _snack(e);
                        setS(() {});
                      }
                    },
                    child: const Text('Ajouter le client (points)'),
                  ),
                TextButton(onPressed: () => _print(s), child: const Text('Imprimer (F5)')),
                TextButton(onPressed: () => _invoiceFor(s).then((_) => setS(() {})), child: const Text('Facture client A4')),
                FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Nouvelle vente (Entrée)')),
              ],
            ),
          ),
        ),
      );

  Future<void> _mySales() => showDialog<void>(
        context: context,
        builder: (ctx) {
          final mine = app.sales.where((s) => s.cashier == app.user!.name).toList().reversed.take(60).toList();
          return AlertDialog(
            title: Text('Mes ventes (${mine.length} dernières)'),
            content: SizedBox(
              width: 560,
              height: 420,
              child: mine.isEmpty
                  ? const Text('Aucune vente.')
                  : ListView(children: [
                      for (final s in mine)
                        ListTile(
                          dense: true,
                          title: Text('Ticket ${s.no} · ${dateFr(s.at)} ${timeFr(s.at)} · ${usd(s.total)}${s.refunded ? ' · ANNULÉ' : ''}', style: bold),
                          subtitle: Text('${s.methodLabel} · ${s.client}'),
                          trailing: app.can('reprint') ? TextButton(onPressed: () => _print(s), child: const Text('Réimprimer')) : null,
                        ),
                    ]),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
          );
        },
      );

  // Récapitulatif de session : consultable par le caissier, sans pouvoir clôturer.
  Future<void> _recap() {
    final s = app.session;
    if (s == null) return Future.value();
    final ch = app.channelsOf(s);
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Récapitulatif de ma session'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            kv('Caisse', s.caisseName),
            kv('Caissier', s.cashier),
            kv('Ouverture', '${dateFr(s.openedAt)} ${timeFr(s.openedAt)}'),
            kv('Factures', '${app.salesOf(s).length}', strong: true),
            const Divider(),
            for (final e in ch.entries) kv(labelOfKey(e.key), money(e.value, currencyOfKey(e.key))),
            if (app.creditOf(s) > 0) kv('Ardoise (non encaissé)', usd(app.creditOf(s))),
            const SizedBox(height: 8),
            const Text('La clôture de caisse est faite par le gérant.', style: muted),
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final body = CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.f2): () => _hold(),
              const SingleActivator(LogicalKeyboardKey.f3): () => _resume(),
              const SingleActivator(LogicalKeyboardKey.f4): () => _pickCustomer(),
              const SingleActivator(LogicalKeyboardKey.f5): () {
                final s = app.lastSale;
                if (s != null) _print(s);
              },
              const SingleActivator(LogicalKeyboardKey.f8): () {
                final p = _selProduct();
                if (p != null) _remove(p);
              },
              const SingleActivator(LogicalKeyboardKey.f12): () => _pay(),
            },
            child: Focus(
              child: Column(children: [
                if (widget.kiosk) _header(),
                Expanded(
                  child: app.session == null
                      ? _noSession()
                      : Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: _left()),
                            const SizedBox(width: 12),
                            SizedBox(width: 390, child: _right()),
                          ]),
                        ),
                ),
              ]),
            ),
          );
          return widget.kiosk ? Scaffold(body: body) : body;
        },
      );

  Widget _noSession() {
    if (app.user!.role == Role.caissier) {
      return Center(
        child: SizedBox(
          width: 460,
          child: Panel(
            title: 'Session clôturée',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Votre session de caisse est fermée. Seul le gérant peut clôturer une caisse. Pour commencer une nouvelle session, verrouillez puis reconnectez-vous.', style: muted),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => app.logout(), child: const Text('Verrouiller')),
            ]),
          ),
        ),
      );
    }
    final list = app.caisses.where((c) => c.active).toList();
    if (list.isEmpty) return const Center(child: Text('Aucune caisse active. Créez-en une dans « Utilisateurs et caisses ».'));
    if (openCaisse == null || !list.contains(openCaisse)) openCaisse = list.first;
    return Center(
      child: SizedBox(
        width: 420,
        child: Panel(
          title: 'Ouvrir une session de caisse',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Aucune session ouverte. Les ventes sont liées à une caisse et à une session.', style: muted),
            const SizedBox(height: 10),
            DropdownButtonFormField<Caisse>(
              value: openCaisse,
              decoration: const InputDecoration(labelText: 'Caisse', border: OutlineInputBorder()),
              items: [for (final c in list) DropdownMenuItem(value: c, child: Text(c.name))],
              onChanged: (v) => setState(() => openCaisse = v),
            ),
            const SizedBox(height: 8),
            TextField(controller: fUsd, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fond de caisse USD', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: fCdf, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fond de caisse CDF', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final e = app.openSession(openCaisse!,
                    floatUsd: double.tryParse(fUsd.text.replaceAll(',', '.')) ?? app.openingFloat, floatCdf: double.tryParse(fCdf.text.replaceAll(',', '.')) ?? 0);
                if (e != null) _snack(e);
              },
              child: const Text('Ouvrir la session'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _header() {
    final now = DateTime.now();
    final s = app.session;
    const w = TextStyle(color: Colors.white, fontSize: 14);
    return Container(
      height: 64,
      color: C.navy,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Text(app.shop, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(width: 16),
        Text(s?.caisseName ?? 'Aucune caisse', style: w),
        const SizedBox(width: 16),
        Text('Ticket n° ${app.nextTicket}', style: w),
        if (s != null) ...[
          const SizedBox(width: 16),
          Text('${app.salesOf(s).length} vente(s) en session', style: w),
        ],
        const Spacer(),
        Text('${dateFr(now)}  ${timeFr(now)}', style: w),
        const SizedBox(width: 16),
        Text('${app.user!.name} · ${app.user!.roleLabel}', style: w),
        const SizedBox(width: 12),
        syncPill(),
        const SizedBox(width: 8),
        TextButton(style: TextButton.styleFrom(foregroundColor: Colors.white), onPressed: _mySales, child: const Text('Mes ventes')),
        TextButton(style: TextButton.styleFrom(foregroundColor: Colors.white), onPressed: _recap, child: const Text('Ma session')),
        TextButton(style: TextButton.styleFrom(foregroundColor: Colors.white), onPressed: () => app.logout(), child: const Text('Verrouiller')),
      ]),
    );
  }

  Widget _left() {
    final lines = app.cart.values.toList();
    final q = query.trim().toLowerCase();
    final sugg = q.length >= 2 ? app.products.where((p) => p.name.toLowerCase().contains(q)).take(5).toList() : <Product>[];
    return Column(children: [
      TextField(
        controller: scan,
        focusNode: focus,
        autofocus: widget.kiosk,
        onSubmitted: _submit,
        onChanged: (v) => setState(() => query = v),
        style: const TextStyle(fontSize: 20),
        decoration: InputDecoration(
          hintText: 'Scannez un article, ou tapez un nom. Astuce : 3*code pour une quantité',
          prefixIcon: const Icon(Icons.qr_code_scanner, size: 28),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.blue, width: 2)),
        ),
      ),
      if (sugg.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.line)),
          child: Column(children: [
            for (final p in sugg)
              ListTile(
                dense: true,
                title: Text(p.name),
                subtitle: Text(p.stock <= 0 ? 'En rupture' : '${p.stock} en stock'),
                trailing: Text(usd(p.sellPrice), style: bold),
                onTap: () {
                  scan.clear();
                  setState(() => query = '');
                  _add(p, 1);
                  focus.requestFocus();
                },
              ),
          ]),
        ),
      if (msg.isNotEmpty)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: msgBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: msgFg)),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, color: msgFg),
            const SizedBox(width: 10),
            Expanded(child: Text(msg, style: TextStyle(color: msgFg, fontSize: 17, fontWeight: FontWeight.w800))),
          ]),
        ),
      const SizedBox(height: 10),
      Expanded(
        child: Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                SizedBox(width: 34, child: Text('N°', style: muted)),
                Expanded(child: Text('Désignation', style: muted)),
                SizedBox(width: 120, child: Text('Qté', style: muted, textAlign: TextAlign.center)),
                SizedBox(width: 90, child: Text('P.U.', style: muted, textAlign: TextAlign.right)),
                SizedBox(width: 100, child: Text('Total', style: muted, textAlign: TextAlign.right)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: lines.isEmpty
                  ? const Center(child: Text('Scannez le premier article.', style: TextStyle(color: C.muted, fontSize: 18)))
                  : ListView(children: [for (var i = 0; i < lines.length; i++) _line(i, lines[i])]),
            ),
            if (lastP != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(color: C.blueSoft, borderRadius: BorderRadius.vertical(bottom: Radius.circular(14))),
                child: Row(children: [
                  const Text('Dernier article : ', style: muted),
                  Expanded(child: Text(lastP!.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                  Text(usd(lastP!.sellPrice), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: C.blue)),
                ]),
              ),
          ]),
        ),
      ),
    ]);
  }

  Widget _line(int i, Line l) {
    final sel = selId == l.p.id;
    return InkWell(
      onTap: () => setState(() => selId = l.p.id),
      child: Container(
        color: sel ? C.blueSoft : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(children: [
          SizedBox(width: 34, child: Text('${i + 1}', style: muted)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.p.promo > 0 ? '${l.p.name}  (promo -${l.p.promo.round()} %)' : l.p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              Text('Stock après vente : ${l.p.stock - l.qty}', style: muted),
            ]),
          ),
          SizedBox(
            width: 120,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(visualDensity: VisualDensity.compact, onPressed: () => _remove(l.p, qty: 1), icon: const Icon(Icons.remove_circle_outline)),
              Text('${l.qty}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              IconButton(visualDensity: VisualDensity.compact, onPressed: () => _add(l.p, 1), icon: const Icon(Icons.add_circle_outline)),
            ]),
          ),
          SizedBox(
            width: 90,
            child: InkWell(onTap: app.can('price') ? () => _editPrice(l) : null, child: Text(usd(l.unit), textAlign: TextAlign.right)),
          ),
          SizedBox(width: 100, child: Text(usd(l.total), textAlign: TextAlign.right, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
        ]),
      ),
    );
  }

  Widget _right() {
    final n = app.cart.values.fold(0, (a, l) => a + l.qty);
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: C.navy, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TOTAL À PAYER', style: TextStyle(color: Color(0xFF9FB2D8), fontSize: 13, letterSpacing: 1)),
          Text(usd(app.total), style: const TextStyle(color: Colors.white, fontSize: 46, fontWeight: FontWeight.w800)),
          Text(cdf(app.total * app.rate), style: const TextStyle(color: Color(0xFFC9D6F2), fontSize: 20)),
          const SizedBox(height: 8),
          if (app.discount > 0.004) Text('Remise fidélité : -${usd(app.discount)}', style: const TextStyle(color: Color(0xFF7EE0B0), fontSize: 14, fontWeight: FontWeight.w700)),
          Text('$n article(s) · HT ${usd(app.subtotal)} · TVA ${usd(app.tax)}', style: const TextStyle(color: Color(0xFF9FB2D8), fontSize: 13)),
        ]),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _pickCustomer,
          icon: const Icon(Icons.person),
          label: Text(app.customer == null ? 'Client WhatsApp (F4)' : '${app.customer!.name} · ${app.tierOf(app.customer!)} · ${app.customer!.points} pts'),
        ),
      ),
      if (app.customer != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SizedBox(
            width: double.infinity,
            child: app.appliedReward == null
                ? OutlinedButton.icon(onPressed: _rewards, icon: const Icon(Icons.card_giftcard), label: const Text('Utiliser mes points'))
                : FilledButton.tonalIcon(onPressed: app.removeReward, icon: const Icon(Icons.close), label: Text('${app.appliedReward!.name} (-${usd(app.discount)})')),
          ),
        ),
      const SizedBox(height: 10),
      Expanded(
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.4,
          children: [
            for (final m in PayMethod.values) FilledButton.tonalIcon(onPressed: () => _pay(m), icon: Icon(m.icon), label: Text(m.label)),
          ],
        ),
      ),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: _hold, child: const Text('En attente (F2)'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton(onPressed: app.held.isEmpty ? null : _resume, child: Text('Reprendre (${app.held.length}) F3'))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              final p = _selProduct();
              if (p != null) _remove(p);
            },
            child: const Text('Suppr. ligne (F8)'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: C.red), onPressed: _cancel, child: const Text('Annuler le ticket'))),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: app.lastSale == null ? null : () => _print(app.lastSale!),
          icon: const Icon(Icons.print),
          label: const Text('Réimprimer le dernier ticket (F5)'),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        height: 64,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: C.green),
          onPressed: app.cart.isEmpty ? null : () => _pay(),
          child: const Text('PAYER (F12)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ),
      ),
    ]);
  }
}
