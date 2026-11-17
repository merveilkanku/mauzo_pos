import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ---------- Sécurité : PIN et mots de passe sont hachés (jamais en clair) ----------
String _newSalt() {
  final r = Random.secure();
  return base64Url.encode(List<int>.generate(12, (_) => r.nextInt(256)));
}

String hashSecret(String secret, String salt) {
  List<int> h = utf8.encode('$salt:$secret');
  for (var i = 0; i < 20000; i++) {
    h = sha256.convert(h).bytes;
  }
  return base64Encode(h);
}

// ---------- Modèles ----------
class Product {
  Product(this.id, this.barcode, this.name, this.cat, this.price, this.floor, this.stock, this.min, this.icon, this.color);
  final String id;
  String barcode, name, cat;
  double price, floor;
  int stock, min;
  double promo = 0; // remise en %
  final IconData icon;
  final Color color;
  bool get low => stock <= min;
  // Identifiant d'article pour le serveur : le code-barres, ou à défaut l'identifiant local.
  String get sku => barcode.isNotEmpty ? barcode : 'id:$id';
  double get sellPrice => price * (1 - promo / 100);
}

class Line {
  Line(this.p, this.qty, {double? unit}) : unit = unit ?? p.sellPrice;
  final Product p;
  double unit;
  int qty;
  double get total => unit * qty;
}

enum PayMethod {
  cashUsd('Espèces USD', Icons.payments),
  cashCdf('Espèces CDF', Icons.money),
  mobile('Mobile money', Icons.phone_android),
  card('Carte', Icons.credit_card),
  credit('Ardoise', Icons.menu_book);

  const PayMethod(this.label, this.icon);
  final String label;
  final IconData icon;
}

String labelOfKey(String k) {
  final p = k.split('|');
  if (p[0] == 'cashUsd') return 'Espèces USD';
  if (p[0] == 'cashCdf') return 'Espèces CDF';
  if (p[0] == 'mm') return '${p[1]} (${p[2]})';
  if (p[0] == 'card') return 'Carte (${p[1]})';
  if (p[0] == 'credit') return 'Ardoise';
  return k;
}

String currencyOfKey(String k) => k.split('|').last;

class Payment {
  Payment(this.method, this.currency, this.amount, this.usd, {this.operator = ''});
  final PayMethod method;
  final String currency, operator; // currency : 'USD' ou 'CDF'
  final double amount; // montant net dans sa devise
  final double usd; // équivalent USD au taux de la vente
  String get key {
    if (method == PayMethod.mobile) return 'mm|$operator|$currency';
    if (method == PayMethod.cashUsd) return 'cashUsd|USD';
    if (method == PayMethod.cashCdf) return 'cashCdf|CDF';
    return '${method.name}|$currency';
  }

  String get label => labelOfKey(key);
}

class Sale {
  Sale(this.no, this.lines, this.subtotal, this.tax, this.method, this.client, this.at) {
    payments = [Payment(method, 'USD', subtotal + tax, subtotal + tax)];
  }
  final int no;
  final List<Line> lines;
  final double subtotal, tax;
  final PayMethod method;
  String client;
  final DateTime at;
  late List<Payment> payments;
  bool refunded = false;
  double received = 0;
  String cashier = '', sessionId = '', caisse = '', device = '';
  String customerKey = '', reward = '';
  int earnedPoints = 0, redeemedPoints = 0;
  double discount = 0;
  String cancelReason = '', cancelledBy = '';
  DateTime? cancelledAt;
  double get total => subtotal + tax;
  bool get mixed => payments.length > 1;
  String get methodLabel => mixed ? 'Paiement mixte' : payments.first.label;
}

// Numéro WhatsApp normalisé (RDC par défaut) : +243970000000.
String normPhone(String s) {
  var d = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return '';
  if (d.startsWith('00')) d = d.substring(2);
  if (d.startsWith('0') && d.length >= 9) d = '243${d.substring(1)}';
  if (d.length == 9) d = '243$d';
  return '+$d';
}

class Customer {
  Customer(this.name, this.phone, {this.points = 0, this.debt = 0, this.spent = 0, this.earned = 0, this.visits = 0});
  String name, phone;
  int points; // solde de points utilisables
  int earned; // points gagnés au total (sert au niveau Bronze, Argent, Or)
  int visits;
  double debt, spent;
  DateTime? last;
  DateTime joined = DateTime.now();
  String get key {
    final p = normPhone(phone);
    return p.isEmpty ? 'n:${name.toLowerCase()}' : p;
  }
}

class PointsEntry {
  PointsEntry(this.at, this.key, this.name, this.delta, this.reason, this.by);
  final DateTime at;
  final String key, name, reason, by;
  final int delta;
}

// Récompense : kind = 'amount' (bon en dollars) ou 'percent' (réduction en %).
class Reward {
  Reward(this.id, this.name, this.cost, this.kind, this.value);
  final String id;
  String name, kind;
  int cost;
  double value;
}

class Msg {
  Msg(this.text, this.mine, this.at);
  final String text;
  final bool mine;
  final DateTime at;
}

class Conv {
  Conv(this.name, this.kind);
  final String name, kind; // Client, Fournisseur, Équipe
  final List<Msg> msgs = [];
}

class Campaign {
  Campaign(this.name, this.segment, this.message, this.sent, this.at);
  final String name, segment, message;
  final int sent;
  final DateTime at;
}

class Reception {
  Reception(this.no, this.supplier, this.lines, this.at);
  final int no;
  final String supplier;
  final Map<String, int> lines;
  final DateTime at;
}

enum AddResult { ok, low, out, notEnough }

enum Role { caissier, employe, gerant }

const permLabels = {
  'hist': 'Consulter ses propres ventes',
  'price': 'Modifier les prix (pas sous le plancher)',
  'reprint': 'Réimprimer d’anciennes factures',
  'refund': 'Demander l’annulation d’une facture (avec le gérant)',
};

class User {
  User(this.name, this.role, {this.login = 'pin'});
  String name;
  Role role;
  bool active = true;
  String login; // 'pin', 'password' ou 'both'
  String pinSalt = '', pinHash = '', pwSalt = '', pwHash = '';
  Set<String> perms = {};
  List<String> caisses = []; // identifiants des caisses autorisées (vide = toutes)
  int fails = 0;
  DateTime? lockUntil;

  void setPin(String v) {
    pinSalt = _newSalt();
    pinHash = hashSecret(v, pinSalt);
  }

  void setPassword(String v) {
    pwSalt = _newSalt();
    pwHash = hashSecret(v, pwSalt);
  }

  bool verify(String s) {
    if (login != 'password' && pinHash.isNotEmpty && hashSecret(s, pinSalt) == pinHash) return true;
    if (login != 'pin' && pwHash.isNotEmpty && hashSecret(s, pwSalt) == pwHash) return true;
    return false;
  }

  String get roleLabel => role == Role.gerant ? 'Gérant' : (role == Role.employe ? 'Employé' : 'Caissier');

  // Mot de sécurité : code distinct du code de connexion, demandé pour autoriser une action sensible.
  String secSalt = '', secHash = '';
  bool get hasSecurity => secHash.isNotEmpty;
  void setSecurity(String v) {
    secSalt = _newSalt();
    secHash = hashSecret(v, secSalt);
  }

  bool checkSecurity(String v) => hasSecurity && hashSecret(v, secSalt) == secHash;
}

class Order {
  Order(this.no, this.client, this.items, this.total, this.source);
  final int no;
  final String client, source;
  final Map<Product, int> items;
  double total;
  String status = 'Nouvelle'; // Nouvelle, Payée, Livrée
}

class Audit {
  Audit(this.at, this.by, this.action, this.detail, {this.authorizer = ''});
  final DateTime at;
  final String by, action, detail, authorizer;
}

class Expense {
  Expense(this.at, this.by, this.category, this.note, this.amount, this.currency, this.fromCash, this.sessionId);
  final DateTime at;
  final String by, category, note, currency, sessionId;
  final double amount;
  final bool fromCash;
}

class Caisse {
  Caisse(this.id, this.name);
  final String id;
  String name;
  bool active = true;
}

class Closure {
  Closure(this.theory, this.counted, this.rate, this.by, this.note);
  final Map<String, double> theory;
  Map<String, double> counted;
  final double rate;
  final String by;
  String note;
  // Écart total converti en USD au taux enregistré lors de la clôture.
  double varianceUsd() {
    var t = 0.0;
    theory.forEach((k, v) {
      final d = (counted[k] ?? 0) - v;
      t += currencyOfKey(k) == 'CDF' ? d / rate : d;
    });
    return t;
  }
}

class Session {
  Session(this.id, this.caisseId, this.caisseName, this.cashier, this.openedAt, this.floatUsd, this.floatCdf);
  final String id, caisseId, caisseName, cashier;
  final DateTime openedAt;
  final double floatUsd, floatCdf;
  DateTime? closedAt;
  Closure? closure;
  bool get open => closedAt == null;
}

const segments = ['Tous les clients', 'Clients fidèles (50 points et plus)', 'Clients à l’ardoise'];

class AppState extends ChangeNotifier {
  AppState() {
    _seed();
  }

  double rate = 2800; // 1 $ = 2 800 FC (à régler chaque jour)
  double vatRate = 0.16; // TVA : à confirmer avec un comptable (0 pour désactiver)
  double openingFloat = 50; // fond de caisse par défaut en USD
  int section = 0;
  int convIndex = 0;
  int _no = 1;
  int _rno = 1;
  Customer? customer; // client rattaché au ticket en cours
  final List<double> week = [310, 420, 380, 510, 470, 620];
  String shop = 'Quincaillerie Démo';
  User? user;
  final List<User> users = [];
  final List<Order> orders = [];
  int _ono = 1;
  final List<String> alerts = []; // signalements pour le gérant
  final List<Map<String, dynamic>> pendingSync = []; // opérations à envoyer au serveur
  final List<Map<String, Line>> held = []; // tickets en attente
  final Set<String> _lowNotified = {};
  DateTime? lastSync;
  String serverUrl = '';
  String serverKey = '';
  String deviceId = DateTime.now().microsecondsSinceEpoch.toRadixString(36); // identifie cette caisse
  bool online = false;
  String syncStatus = 'Mode local : tout est enregistré sur cet ordinateur.';

  // Réglages de sécurité, d'impression et de paiement
  String lineDeletePolicy = 'authorized'; // 'forbidden' ou 'authorized' (validation par le gérant)
  int idleMinutes = 5; // déconnexion automatique (0 = jamais)
  bool autoPrint = false;
  int paperMm = 80; // 58, 80 ou 210 (A4)
  String printerName = '';
  List<String> operators = ['Airtel Money', 'Orange Money', 'M-Pesa', 'Autre'];
  DateTime lastActivity = DateTime.now();
  Sale? lastSale;
  int feedCursor = 0; // dernière opération reçue du serveur
  final List<String> appliedIds = [];
  final Set<String> _applied = {};
  String deviceName = Platform.localHostname;
  bool _syncing = false;

  final List<Caisse> caisses = [];
  final List<Session> sessions = [];
  Session? session; // session de caisse utilisée par l'utilisateur connecté
  final List<Audit> audits = [];
  final List<Expense> expenses = [];

  final List<Product> products = [
    Product('p1', '6001001000011', 'Huile Simba 5 L', 'Alimentaire', 12.5, 11, 40, 10, Icons.opacity, Color(0xFFD97706)),
    Product('p2', '6001001000028', 'Farine de maïs 25 kg', 'Alimentaire', 18, 16, 22, 8, Icons.grain, Color(0xFFB45309)),
    Product('p3', '6001001000035', 'Lait en poudre 400 g', 'Alimentaire', 3.5, 3, 60, 15, Icons.local_drink, Color(0xFF1D4ED8)),
    Product('p4', '6001001000042', 'Sucre blanc 1 kg', 'Alimentaire', 1.8, 1.5, 8, 20, Icons.cookie, Color(0xFF64738B)),
    Product('p5', '6001001000059', 'Riz 25 kg', 'Alimentaire', 22, 20, 15, 6, Icons.rice_bowl, Color(0xFF0E8F4F)),
    Product('p6', '6001001000066', 'Savon de ménage', 'Hygiène', 0.8, 0.6, 120, 30, Icons.clean_hands, Color(0xFF0891B2)),
    Product('p7', '6001001000073', 'Eau minérale 1,5 L', 'Boissons', 1, 0.8, 0, 24, Icons.water_drop, Color(0xFF2563EB)),
    Product('p8', '6001001000080', 'Pâtes 500 g', 'Alimentaire', 1.2, 1, 75, 20, Icons.ramen_dining, Color(0xFFDC2626)),
  ];
  final Map<String, Line> cart = {};
  final List<Sale> sales = [];
  final List<Customer> customers = [
    Customer('Mama Julie', '+243 97 000 0001', points: 120, debt: 45, spent: 310),
    Customer('Chantier Kasapa', '+243 99 000 0002', points: 40, debt: 120, spent: 180),
    Customer('Papa Jean', '+243 81 000 0003', points: 75, spent: 95),
    Customer('Restaurant Le Katanga', '+243 82 000 0004', points: 210, spent: 640),
  ];
  final List<String> suppliers = ['Grossiste Kivu', 'Import Lubumbashi', 'Brasserie locale'];
  final List<Reception> receptions = [];
  final List<Campaign> campaigns = [];
  final List<Conv> convs = [];

  Payment mkPay(PayMethod m, double usd, {String op = ''}) {
    final cdf = m == PayMethod.cashCdf;
    return Payment(m, cdf ? 'CDF' : 'USD', cdf ? usd * rate : usd, usd, operator: op);
  }

  User _mkUser(String name, Role r, String pin, {Set<String> perms = const {}}) {
    final u = User(name, r)..setPin(pin);
    u.perms = {...perms};
    return u;
  }

  void _seed() {
    users.addAll([
      _mkUser('Marie K.', Role.caissier, '1234', perms: {'hist'}),
      _mkUser('Joël T.', Role.employe, '2222', perms: {'hist', 'reprint'}),
      _mkUser('Patrick M.', Role.gerant, '0000'),
    ]);
    caisses.addAll([Caisse('c1', 'Caisse 1'), Caisse('c2', 'Caisse 2')]);
    void s(Product p, int q, PayMethod m) {
      final sub = p.sellPrice * q;
      final sale = Sale(_no++, [Line(p, q)], sub, sub * vatRate, m, 'Client comptant', DateTime.now());
      sale.payments = [mkPay(m, sale.total, op: m == PayMethod.mobile ? operators.first : '')];
      sale.cashier = 'Marie K.';
      sale.caisse = 'Caisse 1';
      sales.add(sale);
    }

    s(products[0], 3, PayMethod.cashUsd);
    s(products[1], 2, PayMethod.mobile);
    s(products[2], 10, PayMethod.cashCdf);
    s(products[4], 1, PayMethod.mobile);
    s(products[3], 6, PayMethod.credit);
    for (final c in customers) {
      convs.add(Conv(c.name, 'Client'));
    }
    convs[0].msgs.add(Msg('Bonjour, vous avez de l’huile Simba ?', false, DateTime.now()));
    final f = Conv('Grossiste Kivu', 'Fournisseur')..msgs.add(Msg('Livraison prévue demain à 10 h.', false, DateTime.now()));
    final e = Conv('Équipe caisse', 'Équipe')..msgs.add(Msg('Marie : fond de caisse vérifié.', false, DateTime.now()));
    convs.addAll([f, e]);
    orders.add(Order(_ono++, 'Mme Ngoy (WhatsApp)', {products[0]: 5}, products[0].sellPrice * 5 * (1 + vatRate), 'WhatsApp'));
    orders.add(Order(_ono++, 'Restaurant Le Katanga', {products[4]: 2, products[1]: 1}, (products[4].sellPrice * 2 + products[1].sellPrice) * (1 + vatRate), 'Téléphone'));
  }

  void touch() => notifyListeners();

  void go(int i) {
    section = i;
    notifyListeners();
  }

  Product? byBarcode(String c) {
    for (final p in products) {
      if (p.barcode == c) return p;
    }
    return null;
  }

  Product? find(String q) {
    final b = byBarcode(q);
    if (b != null) return b;
    final l = q.toLowerCase();
    for (final p in products) {
      if (l.isNotEmpty && p.name.toLowerCase().contains(l)) return p;
    }
    return null;
  }

  // ---------- Permissions (vérifiées ici, dans la logique métier, pas seulement dans l'interface) ----------
  bool get isManager => user?.role == Role.gerant;

  bool can(String perm) {
    final u = user;
    if (u == null) return false;
    return u.role == Role.gerant || u.perms.contains(perm);
  }

  bool canSee(int i) {
    final r = user?.role;
    if (r == Role.gerant) return true;
    if (r == Role.caissier) return i == 0;
    return !const {1, 10, 11, 12, 13, 14, 15, 16, 17}.contains(i);
  }

  // ---------- Journal d'audit ----------
  void audit(String action, String detail, {String authorizer = '', String? by}) {
    final who = by ?? user?.name ?? '-';
    audits.insert(0, Audit(DateTime.now(), who, action, detail, authorizer: authorizer));
    if (audits.length > 3000) audits.removeLast();
    _op('audit', action, {'by': who, 'at': DateTime.now().toIso8601String(), 'action': action, 'detail': detail, 'authorizer': authorizer});
  }

  // ---------- Connexion ----------
  int _authFails = 0;
  DateTime? _authLockUntil;
  bool get authLocked => _authLockUntil != null && DateTime.now().isBefore(_authLockUntil!);
  String authError() => authLocked ? 'Trop d’essais, réessayez dans une minute.' : 'Mot de sécurité du gérant incorrect.';

  String? _authorizer(String secret) {
    if (authLocked) return null;
    for (final x in users) {
      if (x.role != Role.gerant || !x.active) continue;
      // Si le gérant a un mot de sécurité, lui seul sert aux autorisations (son code de connexion ne suffit plus).
      if (x.hasSecurity ? x.checkSecurity(secret) : x.verify(secret)) {
        _authFails = 0;
        return x.name;
      }
    }
    _authFails++;
    if (_authFails >= 5) {
      _authLockUntil = DateTime.now().add(const Duration(seconds: 60));
      _authFails = 0;
    }
    return null;
  }

  String? login(User u, String secret, {Caisse? caisse}) {
    if (!u.active) return 'Ce compte est désactivé.';
    if (u.lockUntil != null && DateTime.now().isBefore(u.lockUntil!)) return 'Compte verrouillé une minute après trop d’essais.';
    if (!u.verify(secret)) {
      u.fails++;
      audit('échec de connexion', u.name, by: u.name);
      if (u.fails >= 5) {
        u.lockUntil = DateTime.now().add(const Duration(seconds: 60));
        u.fails = 0;
      }
      notifyListeners();
      return 'Code incorrect.';
    }
    u.fails = 0;
    user = u;
    if (u.role == Role.caissier) {
      if (caisse == null) {
        user = null;
        return 'Choisissez une caisse.';
      }
      final err = openSession(caisse);
      if (err != null) {
        user = null;
        return err;
      }
    }
    section = u.role == Role.gerant ? 1 : (u.role == Role.employe ? 2 : 0);
    lastActivity = DateTime.now();
    audit('connexion', u.name);
    notifyListeners();
    return null;
  }

  void logout({String reason = 'déconnexion'}) {
    if (user == null) return;
    if (cart.isNotEmpty) hold();
    audit(reason, user!.name);
    user = null;
    session = null;
    customer = null;
    appliedReward = null;
    notifyListeners();
  }

  // ---------- Sessions de caisse ----------
  String? openSession(Caisse c, {double? floatUsd, double? floatCdf}) {
    final u = user;
    if (u == null) return 'Connectez-vous.';
    if (!c.active) return 'Cette caisse est désactivée.';
    if (u.role == Role.caissier && u.caisses.isNotEmpty && !u.caisses.contains(c.id)) return 'Vous n’êtes pas affecté à cette caisse.';
    for (final s in sessions) {
      if (s.open && s.caisseId == c.id) {
        if (s.cashier == u.name) {
          session = s;
          return null;
        }
        return '${c.name} est déjà ouverte par ${s.cashier}.'; // une seule session active par caisse
      }
    }
    final s = Session('$deviceId-${DateTime.now().microsecondsSinceEpoch}', c.id, c.name, u.name, DateTime.now(), floatUsd ?? openingFloat, floatCdf ?? 0);
    sessions.add(s);
    session = s;
    audit('ouverture de caisse', '${c.name}, fond ${floatUsd ?? openingFloat} \$');
    _op('session', 'Ouverture ${c.name}', sessionJson(s));
    notifyListeners();
    return null;
  }

  List<Sale> salesOf(Session s) => sales.where((x) => x.sessionId == s.id && !x.refunded).toList();

  // Montants encaissés par moyen de paiement, chacun dans sa propre devise (jamais additionnés sans conversion).
  Map<String, double> channelsOf(Session s) {
    final m = <String, double>{};
    for (final sale in salesOf(s)) {
      for (final p in sale.payments) {
        if (p.method == PayMethod.credit) continue;
        m[p.key] = (m[p.key] ?? 0) + p.amount;
      }
    }
    return m;
  }

  double creditOf(Session s) {
    var t = 0.0;
    for (final sale in salesOf(s)) {
      for (final p in sale.payments) {
        if (p.method == PayMethod.credit) t += p.usd;
      }
    }
    return t;
  }

  // Théorique en caisse : fond de caisse + encaissements - dépenses payées en espèces.
  Map<String, double> theoryOf(Session s) {
    final m = channelsOf(s);
    m['cashUsd|USD'] = (m['cashUsd|USD'] ?? 0) + s.floatUsd;
    m['cashCdf|CDF'] = (m['cashCdf|CDF'] ?? 0) + s.floatCdf;
    for (final e in expenses) {
      if (e.sessionId == s.id && e.fromCash) {
        final k = e.currency == 'CDF' ? 'cashCdf|CDF' : 'cashUsd|USD';
        m[k] = (m[k] ?? 0) - e.amount;
      }
    }
    return m;
  }

  String? closeSession(Session s, Map<String, double> counted, String note) {
    if (user?.role != Role.gerant) return 'Seul le gérant peut clôturer une caisse.';
    if (!s.open) return 'Cette session est déjà clôturée.';
    s.closure = Closure(theoryOf(s), counted, rate, user!.name, note);
    s.closedAt = DateTime.now();
    if (session?.id == s.id) session = null;
    audit('clôture de caisse', '${s.caisseName} / ${s.cashier}, écart ${s.closure!.varianceUsd().toStringAsFixed(2)} \$ équivalent');
    _op('closure', 'Clôture ${s.caisseName}', sessionJson(s));
    notifyListeners();
    return null;
  }

  // Une clôture validée est verrouillée : toute correction exige le gérant, un motif, et laisse une trace.
  String? amendClosure(Session s, Map<String, double> counted, String reason) {
    if (user?.role != Role.gerant) return 'Seul le gérant peut corriger une clôture.';
    if (s.closure == null) return 'Session non clôturée.';
    if (reason.trim().isEmpty) return 'Le motif est obligatoire.';
    final before = s.closure!.varianceUsd();
    s.closure!.counted = counted;
    s.closure!.note = '${s.closure!.note}\nCorrection : ${reason.trim()}'.trim();
    audit('correction de clôture', '${s.caisseName} / ${s.cashier} : écart ${before.toStringAsFixed(2)} → ${s.closure!.varianceUsd().toStringAsFixed(2)} \$, motif : ${reason.trim()}');
    _op('closure', 'Correction ${s.caisseName}', sessionJson(s));
    notifyListeners();
    return null;
  }

  // ---------- Dépenses ----------
  String? addExpense(String category, String note, double amount, String currency, bool fromCash, Session? s) {
    if (user?.role != Role.gerant) return 'Réservé au gérant.';
    if (amount <= 0) return 'Indiquez un montant.';
    final e = Expense(DateTime.now(), user!.name, category, note, amount, currency, fromCash && s != null, s?.id ?? '');
    expenses.insert(0, e);
    audit('dépense', '$category ${amount.toStringAsFixed(2)} $currency');
    _op('expense', 'Dépense : $category', {'at': e.at.toIso8601String(), 'by': e.by, 'category': category, 'note': note, 'amount': amount, 'currency': currency, 'fromCash': e.fromCash, 'session': e.sessionId});
    notifyListeners();
    return null;
  }

  // ---------- Ticket en cours ----------
  AddResult addQty(Product p, int q) {
    final who = user?.name ?? 'la caisse';
    if (p.stock <= 0) {
      alert('Rupture signalée par $who : ${p.name}');
      return AddResult.out;
    }
    final cur = cart[p.id]?.qty ?? 0;
    if (cur + q > p.stock) {
      alert('Stock insuffisant signalé par $who : ${p.name} (reste ${p.stock})');
      return AddResult.notEnough;
    }
    final l = cart[p.id];
    if (l == null) {
      cart[p.id] = Line(p, q);
    } else {
      l.qty += q;
    }
    notifyListeners();
    final left = p.stock - (cur + q);
    if (left <= p.min) {
      if (_lowNotified.add(p.id)) alert('Stock bas : ${p.name} (reste $left après ce ticket)');
      return AddResult.low;
    }
    return AddResult.ok;
  }

  // Suppression d'une ligne (ou d'une quantité). Le gérant : direct. Les autres : selon la règle du gérant.
  String? removeLine(Product p, {int qty = -1, String reason = '', String secret = ''}) {
    final u = user;
    final l = cart[p.id];
    if (u == null || l == null) return 'Ligne introuvable.';
    var auth = '';
    if (u.role != Role.gerant) {
      if (lineDeletePolicy == 'forbidden') return 'La suppression de lignes est interdite.';
      if (reason.trim().isEmpty) return 'Le motif est obligatoire.';
      final a = _authorizer(secret);
      if (a == null) return authError();
      auth = a;
    }
    final n = (qty < 0 || qty >= l.qty) ? l.qty : qty;
    if (n >= l.qty) {
      cart.remove(p.id);
    } else {
      l.qty -= n;
    }
    audit('ligne supprimée', '${p.name} × $n, motif : ${reason.trim().isEmpty ? '-' : reason.trim()}', authorizer: auth);
    notifyListeners();
    return null;
  }

  String? setLinePrice(Product p, double price) {
    if (!can('price')) return 'Vous n’avez pas la permission de modifier les prix.';
    if (user!.role != Role.gerant && price < p.floor) return 'Prix inférieur au plancher (${p.floor.toStringAsFixed(2)} \$).';
    final l = cart[p.id];
    if (l == null || price <= 0) return 'Prix invalide.';
    final old = l.unit;
    l.unit = price;
    audit('prix modifié', '${p.name} : ${old.toStringAsFixed(2)} → ${price.toStringAsFixed(2)} \$');
    notifyListeners();
    return null;
  }

  void clear() {
    cart.clear();
    customer = null;
    appliedReward = null;
    notifyListeners();
  }

  void hold() {
    if (cart.isEmpty) return;
    held.add(Map<String, Line>.from(cart));
    cart.clear();
    customer = null;
    appliedReward = null;
    notifyListeners();
  }

  bool resume(int i) {
    if (cart.isNotEmpty) return false;
    cart.addAll(held.removeAt(i));
    notifyListeners();
    return true;
  }

  double get subtotal => gross - discount; // HT après remise de fidélité
  double get tax => subtotal * vatRate;
  double get total => subtotal + tax;
  int get nextTicket => _no;
  int get lowCount => products.where((p) => p.low).length;

  List<Sale> get todaySales {
    final n = DateTime.now();
    return sales.where((s) => !s.refunded && s.at.year == n.year && s.at.month == n.month && s.at.day == n.day).toList();
  }

  double get todayTotal => todaySales.fold(0.0, (a, s) => a + s.total);

  Map<PayMethod, double> get byMethod {
    final m = <PayMethod, double>{};
    for (final s in todaySales) {
      for (final p in s.payments) {
        m[p.method] = (m[p.method] ?? 0) + p.usd;
      }
    }
    return m;
  }

  List<MapEntry<String, int>> get topProducts {
    final m = <String, int>{};
    for (final s in sales.where((x) => !x.refunded)) {
      for (final l in s.lines) {
        m[l.p.name] = (m[l.p.name] ?? 0) + l.qty;
      }
    }
    final e = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return e;
  }

  // Valide la vente : liée au caissier, à la caisse et à la session. Retourne null si refusée.
  Sale? checkout(List<Payment> pays, String client, {double received = 0}) {
    final s = session;
    if (s == null || !s.open || cart.isEmpty || user == null || pays.isEmpty) return null;
    final paid = pays.fold(0.0, (a, p) => a + p.usd);
    if (paid + 0.005 < total) return null;
    final credit = pays.where((p) => p.method == PayMethod.credit).fold(0.0, (a, p) => a + p.usd);
    final c = customer;
    if (credit > 0 && c == null) return null;
    final lines = cart.values.map((l) => Line(l.p, l.qty, unit: l.unit)).toList();
    final reward = appliedReward;
    if (reward != null && (c == null || c.points < reward.cost)) {
      appliedReward = null;
      return null;
    }
    final disc = discount;
    final sub = lines.fold(0.0, (a, l) => a + l.total) - disc;
    final sale = Sale(_no++, lines, sub, sub * vatRate, pays.first.method, c?.name ?? client, DateTime.now());
    sale.discount = disc;
    sale.reward = reward?.name ?? '';
    sale.payments = pays;
    sale.received = received;
    sale.cashier = user!.name;
    sale.sessionId = s.id;
    sale.caisse = s.caisseName;
    sale.device = deviceId;
    for (final l in lines) {
      l.p.stock -= l.qty;
    }
    loyaltyNote = '';
    if (c != null) _loyaltyOnSale(sale, c, credit, reward);
    sales.add(sale);
    _op('sale', 'Vente n° ${sale.no}', _saleJson(sale));
    cart.clear();
    customer = null;
    appliedReward = null;
    lastSale = sale;
    notifyListeners();
    return sale;
  }

  // Annulation d'une facture : motif obligatoire, autorisation du gérant, trace conservée dans l'historique.
  String? cancelSale(Sale s, String reason, {String secret = ''}) {
    final u = user;
    if (u == null) return 'Connectez-vous.';
    if (s.refunded) return 'Cette facture est déjà annulée.';
    if (reason.trim().isEmpty) return 'Le motif est obligatoire.';
    var auth = u.name;
    if (u.role != Role.gerant) {
      if (!can('refund')) return 'Vous n’avez pas la permission d’annuler une facture.';
      final a = _authorizer(secret);
      if (a == null) return authError();
      auth = a;
    }
    for (final l in s.lines) {
      l.p.stock += l.qty;
    }
    s.refunded = true;
    s.cancelReason = reason.trim();
    s.cancelledBy = auth;
    s.cancelledAt = DateTime.now();
    _loyaltyOnCancel(s);
    audit('facture annulée', 'Ticket ${s.no} (${s.total.toStringAsFixed(2)} \$), motif : ${reason.trim()}', authorizer: auth);
    _op('refund', 'Annulation du ticket ${s.no}', {'no': s.no, 'sale_device': s.device, 'session': s.sessionId, 'reason': s.cancelReason, 'by': auth});
    notifyListeners();
    return null;
  }

  void receive(Product p, int n) {
    p.stock += n;
    _op('stock', 'Stock +$n : ${p.name}', {'sku': p.sku, 'delta': n});
    notifyListeners();
  }

  void receiveMany(Map<Product, int> lines, String supplier) {
    final rec = <String, int>{};
    lines.forEach((p, n) {
      p.stock += n;
      rec[p.name] = n;
    });
    receptions.insert(0, Reception(_rno++, supplier, rec, DateTime.now()));
    _op('reception', 'Réception n° ${_rno - 1}', {
      'supplier': supplier,
      'lines': [for (final e in lines.entries) {'sku': e.key.sku, 'delta': e.value}],
    });
    notifyListeners();
  }

  void setPromo(Product p, double pct) {
    p.promo = pct.clamp(0, 90).toDouble();
    notifyListeners();
  }

  Conv convFor(Customer c) {
    for (final v in convs) {
      if (v.kind == 'Client' && v.name == c.name) return v;
    }
    final v = Conv(c.name, 'Client');
    convs.add(v);
    return v;
  }

  List<Customer> segment(String s) {
    if (s == segments[1]) return customers.where((c) => c.points >= 50).toList();
    if (s == segments[2]) return customers.where((c) => c.debt > 0).toList();
    return List<Customer>.from(customers);
  }

  int sendCampaign(String name, String seg, String text) {
    final list = segment(seg);
    for (final c in list) {
      convFor(c).msgs.add(Msg(text, true, DateTime.now()));
    }
    campaigns.insert(0, Campaign(name, seg, text, list.length, DateTime.now()));
    notifyListeners();
    return list.length;
  }

  void post(Conv c, String text) {
    if (text.trim().isEmpty) return;
    c.msgs.add(Msg(text.trim(), true, DateTime.now()));
    notifyListeners();
  }

  void createOrder(String client, Product p, int q, String source) {
    orders.insert(0, Order(_ono++, client, {p: q}, p.sellPrice * q * (1 + vatRate), source));
    notifyListeners();
  }

  String? payOrder(Order o, PayMethod m) {
    final s = session;
    if (s == null || !s.open) return 'Ouvrez d’abord une session de caisse (écran Caisse).';
    for (final e in o.items.entries) {
      if (e.key.stock < e.value) return 'Stock insuffisant pour ${e.key.name}.';
    }
    final lines = o.items.entries.map((e) => Line(e.key, e.value)).toList();
    final sub = lines.fold(0.0, (a, l) => a + l.total);
    for (final l in lines) {
      l.p.stock -= l.qty;
    }
    final sale = Sale(_no++, lines, sub, sub * vatRate, m, o.client, DateTime.now());
    sale.payments = [mkPay(m, sale.total, op: m == PayMethod.mobile ? operators.first : '')];
    sale.cashier = user?.name ?? '';
    sale.sessionId = s.id;
    sale.caisse = s.caisseName;
    sale.device = deviceId;
    sales.add(sale);
    _op('sale', 'Vente n° ${sale.no}', _saleJson(sale));
    o.status = 'Payée';
    notifyListeners();
    return null;
  }

  void deliver(Order o) {
    o.status = 'Livrée';
    notifyListeners();
  }

  void alert(String s) {
    if (alerts.isEmpty || alerts.first != s) alerts.insert(0, s);
    notifyListeners();
  }

  void unknownCode(String c) => alert('Code inconnu scanné par ${user?.name ?? 'la caisse'} : $c (à créer par le gérant)');

  // ---------- Fidélité : clients (numéro WhatsApp), points, niveaux, récompenses ----------
  double pointsPerUsd = 1; // points gagnés par dollar réellement payé
  int welcomePoints = 10; // bonus à l'inscription d'un client
  int silverAt = 500, goldAt = 2000; // points cumulés pour passer Argent, puis Or
  bool askCustomerAtPayment = true; // propose d'ajouter le client avant le paiement
  final List<Reward> rewards = [
    Reward('r1', 'Bon de 2 \$', 100, 'amount', 2),
    Reward('r2', '5 % de réduction', 250, 'percent', 5),
    Reward('r3', 'Bon de 15 \$', 500, 'amount', 15),
  ];
  final List<PointsEntry> ledger = [];
  Reward? appliedReward;
  String loyaltyNote = '';

  Customer? customerByKey(String k) {
    for (final c in customers) {
      if (c.key == k) return c;
    }
    return null;
  }

  Customer? findByPhone(String p) {
    final k = normPhone(p);
    return k.isEmpty ? null : customerByKey(k);
  }

  String? validPhone(String p) => normPhone(p).replaceAll('+', '').length >= 9 ? null : 'Numéro WhatsApp invalide.';

  String tierOf(Customer c) {
    final life = max(c.earned, c.points);
    if (life >= goldAt) return 'Or';
    if (life >= silverAt) return 'Argent';
    return 'Bronze';
  }

  double tierMult(String t) => t == 'Or' ? 1.5 : (t == 'Argent' ? 1.25 : 1.0);

  void setCustomer(Customer? c) {
    if (customer != c) appliedReward = null;
    customer = c;
    notifyListeners();
  }

  double get gross => cart.values.fold(0.0, (a, l) => a + l.total);

  // Remise de fidélité appliquée au ticket (avant TVA).
  double get discount {
    final r = appliedReward;
    if (r == null || customer == null) return 0;
    final g = gross;
    final d = r.kind == 'percent' ? g * r.value / 100 : r.value;
    return d > g ? g : d;
  }

  String? applyReward(Reward r) {
    final c = customer;
    if (c == null) return 'Rattachez d’abord un client.';
    if (cart.isEmpty) return 'Le ticket est vide.';
    if (c.points < r.cost) return 'Points insuffisants (${c.points} sur ${r.cost}).';
    appliedReward = r;
    notifyListeners();
    return null;
  }

  void removeReward() {
    appliedReward = null;
    notifyListeners();
  }

  void _addPoints(Customer c, int pts, int earnedDelta, String reason, {String ref = ''}) {
    c.points += pts;
    c.earned += earnedDelta;
    ledger.insert(0, PointsEntry(DateTime.now(), c.key, c.name, pts, reason, user?.name ?? ''));
    if (ledger.length > 5000) ledger.removeLast();
    _op('cust_delta', 'Points ${pts >= 0 ? '+' : ''}$pts : ${c.name}', {
      'key': c.key, 'name': c.name, 'phone': c.phone, 'points': pts, 'earned': earnedDelta,
      'entries': [{'d': pts, 'r': reason}], 'ref': ref, 'by': user?.name ?? '',
    });
  }

  // Création d'un client depuis la caisse : numéro WhatsApp unique, bonus de bienvenue.
  Customer? createCustomer(String name, String phone) {
    final n = name.trim();
    if (n.isEmpty || validPhone(phone) != null) return null;
    final key = normPhone(phone);
    final existing = customerByKey(key);
    if (existing != null) return existing;
    final c = Customer(n, key);
    customers.add(c);
    _op('customer', 'Nouveau client : $n', {'key': key, 'name': n, 'phone': key, 'joined': c.joined.toIso8601String()});
    if (welcomePoints > 0) _addPoints(c, welcomePoints, welcomePoints, 'Bonus de bienvenue', ref: 'welcome:$key');
    convFor(c).msgs.add(Msg('Bienvenue chez $shop, $n ! Vous gagnez des points à chaque achat et vous recevez ${welcomePoints > 0 ? '$welcomePoints points offerts' : 'des récompenses'}.', true, DateTime.now()));
    audit('client créé', '$n ($key)');
    notifyListeners();
    return c;
  }

  // Points, niveau et messages après une vente avec client. Les points sont calculés sur l'argent réellement payé (hors ardoise).
  void _loyaltyOnSale(Sale sale, Customer c, double credit, Reward? reward) {
    final oldTier = tierOf(c);
    final base = (sale.total - credit) * pointsPerUsd * tierMult(oldTier);
    final earned = base > 0 ? base.floor() : 0;
    final redeemed = reward?.cost ?? 0;
    final before = c.points - redeemed;
    sale.customerKey = c.key;
    sale.earnedPoints = earned;
    sale.redeemedPoints = redeemed;
    c.spent += sale.total;
    c.visits += 1;
    c.last = sale.at;
    c.debt += credit;
    final entries = <Map<String, dynamic>>[];
    if (earned > 0) {
      entries.add({'d': earned, 'r': 'Achat ticket n° ${sale.no}'});
      ledger.insert(0, PointsEntry(sale.at, c.key, c.name, earned, 'Achat ticket n° ${sale.no}', sale.cashier));
    }
    if (redeemed > 0) {
      entries.add({'d': -redeemed, 'r': 'Récompense : ${reward!.name}'});
      ledger.insert(0, PointsEntry(sale.at, c.key, c.name, -redeemed, 'Récompense : ${reward.name}', sale.cashier));
    }
    c.points += earned - redeemed;
    c.earned += earned;
    _op('cust_delta', 'Vente n° ${sale.no} : ${c.name}', {
      'key': c.key, 'name': c.name, 'phone': c.phone, 'points': earned - redeemed, 'earned': earned, 'spent': sale.total,
      'debt': credit, 'visits': 1, 'last': sale.at.toIso8601String(), 'entries': entries, 'ref': '$deviceId:${sale.no}', 'by': sale.cashier,
    });
    final notes = <String>['${c.name} gagne $earned point(s). Solde : ${c.points}.'];
    final newTier = tierOf(c);
    if (newTier != oldTier) {
      notes.add('${c.name} passe au niveau $newTier (points ×${tierMult(newTier)}).');
      convFor(c).msgs.add(Msg('Félicitations ${c.name} ! Vous passez au niveau $newTier : vos points sont multipliés par ${tierMult(newTier)} sur vos prochains achats.', true, DateTime.now()));
    }
    for (final r in rewards) {
      if (before < r.cost && c.points >= r.cost) {
        notes.add('${c.name} peut maintenant obtenir : ${r.name}.');
        convFor(c).msgs.add(Msg('Bonjour ${c.name}, vous avez ${c.points} points : vous pouvez obtenir « ${r.name} » à votre prochain achat chez $shop.', true, DateTime.now()));
      }
    }
    loyaltyNote = notes.join('\n');
  }

  // Annulation d'une facture : les points gagnés sont retirés, les points utilisés sont rendus.
  void _loyaltyOnCancel(Sale s) {
    if (s.customerKey.isEmpty) return;
    final c = customerByKey(s.customerKey);
    if (c == null) return;
    final credit = s.payments.where((p) => p.method == PayMethod.credit).fold(0.0, (a, p) => a + p.usd);
    final delta = -s.earnedPoints + s.redeemedPoints;
    c.points = max(0, c.points + delta);
    c.earned = max(0, c.earned - s.earnedPoints);
    c.spent = max(0.0, c.spent - s.total);
    c.debt = max(0.0, c.debt - credit);
    c.visits = max(0, c.visits - 1);
    ledger.insert(0, PointsEntry(DateTime.now(), c.key, c.name, delta, 'Annulation du ticket n° ${s.no}', user?.name ?? ''));
    _op('cust_delta', 'Annulation ticket ${s.no} : ${c.name}', {
      'key': c.key, 'name': c.name, 'phone': c.phone, 'points': delta, 'earned': -s.earnedPoints, 'spent': -s.total, 'debt': -credit, 'visits': -1,
      'entries': [{'d': delta, 'r': 'Annulation du ticket n° ${s.no}'}], 'ref': '$deviceId:cancel:${s.no}', 'by': user?.name ?? '',
    });
  }

  // Rattache un client à une facture déjà faite (facture nominative) : les points sont ajoutés à ce moment.
  String? attachCustomer(Sale s, Customer c) {
    if (s.refunded) return 'Cette facture est annulée.';
    if (s.customerKey.isNotEmpty) return 'Un client est déjà rattaché à cette facture.';
    if (user?.role == Role.caissier && s.cashier != user!.name) return 'Vous ne pouvez rattacher un client qu’à vos propres ventes.';
    final base = s.total * pointsPerUsd * tierMult(tierOf(c));
    final earned = base > 0 ? base.floor() : 0;
    s.client = c.name;
    s.customerKey = c.key;
    s.earnedPoints = earned;
    c.spent += s.total;
    c.visits += 1;
    c.last = s.at;
    final entries = <Map<String, dynamic>>[];
    if (earned > 0) {
      c.points += earned;
      c.earned += earned;
      entries.add({'d': earned, 'r': 'Achat ticket n° ${s.no}'});
      ledger.insert(0, PointsEntry(s.at, c.key, c.name, earned, 'Achat ticket n° ${s.no}', user?.name ?? ''));
    }
    _op('cust_delta', 'Client sur le ticket ${s.no} : ${c.name}', {
      'key': c.key, 'name': c.name, 'phone': c.phone, 'points': earned, 'earned': earned, 'spent': s.total, 'visits': 1,
      'last': s.at.toIso8601String(), 'entries': entries, 'ref': '${s.device}:${s.no}', 'by': user?.name ?? '',
    });
    _op('sale_customer', 'Client sur le ticket ${s.no}', {'no': s.no, 'sale_device': s.device, 'key': c.key, 'name': c.name, 'earned': earned});
    audit('client rattaché à une facture', 'Ticket ${s.no} → ${c.name} (+$earned points)');
    notifyListeners();
    return null;
  }

  String? adjustPoints(Customer c, int delta, String reason) {
    if (user?.role != Role.gerant) return 'Réservé au gérant.';
    if (reason.trim().isEmpty) return 'Le motif est obligatoire.';
    if (delta == 0) return 'Indiquez un nombre de points.';
    if (c.points + delta < 0) return 'Le solde ne peut pas être négatif.';
    _addPoints(c, delta, delta > 0 ? delta : 0, 'Ajustement : ${reason.trim()}');
    audit('points ajustés', '${c.name} ${delta > 0 ? '+' : ''}$delta, motif : ${reason.trim()}');
    notifyListeners();
    return null;
  }

  // Prévient (par message WhatsApp, simulé dans l'application) les clients qui ont assez de points pour une récompense.
  int notifyRewardReady() {
    if (rewards.isEmpty) return 0;
    final minCost = rewards.map((r) => r.cost).reduce((a, b) => a < b ? a : b);
    var n = 0;
    for (final c in customers) {
      if (c.points >= minCost) {
        convFor(c).msgs.add(Msg('Bonjour ${c.name}, vous avez ${c.points} points chez $shop : présentez-vous en caisse pour utiliser votre récompense.', true, DateTime.now()));
        n++;
      }
    }
    if (n > 0) campaigns.insert(0, Campaign('Récompenses prêtes', 'Clients avec assez de points', 'Rappel des points disponibles', n, DateTime.now()));
    notifyListeners();
    return n;
  }

  void _rCustDelta(Map<String, dynamic> d) {
    final key = d['key'] as String;
    final found = customerByKey(key);
    final c = found ?? Customer((d['name'] as String?) ?? key, (d['phone'] as String?) ?? key);
    if (found == null) customers.add(c);
    c.points = max(0, c.points + ((d['points'] as num?)?.toInt() ?? 0));
    c.earned = max(0, c.earned + ((d['earned'] as num?)?.toInt() ?? 0));
    c.spent = max(0.0, c.spent + _d(d['spent']));
    c.debt = max(0.0, c.debt + _d(d['debt']));
    c.visits = max(0, c.visits + ((d['visits'] as num?)?.toInt() ?? 0));
    if (d['last'] != null) c.last = _t(d['last']);
    for (final e in (d['entries'] as List? ?? [])) {
      ledger.insert(0, PointsEntry(DateTime.now(), key, c.name, (e['d'] as num).toInt(), e['r'] as String, (d['by'] as String?) ?? ''));
    }
  }

  void _rSaleCustomer(String dev, Map<String, dynamic> d) {
    final sd = (d['sale_device'] as String?) ?? dev;
    for (final s in sales) {
      if (s.device == sd && s.no == (d['no'] as int)) {
        s.client = (d['name'] as String?) ?? s.client;
        s.customerKey = (d['key'] as String?) ?? s.customerKey;
        s.earnedPoints = (d['earned'] as num?)?.toInt() ?? s.earnedPoints;
      }
    }
  }

  List<Reward> _rewardsFrom(List<dynamic> l) => [
        for (final m in l) Reward(m['id'] as String, m['name'] as String, (m['cost'] as num).toInt(), m['kind'] as String, _d(m['value']))
      ];

  Map<String, dynamic> _loyaltyJson() => {
        'ppu': pointsPerUsd, 'welcome': welcomePoints, 'silverAt': silverAt, 'goldAt': goldAt, 'askCustomer': askCustomerAtPayment,
        'rewards': [for (final r in rewards) {'id': r.id, 'name': r.name, 'cost': r.cost, 'kind': r.kind, 'value': r.value}],
      };

  void _loadLoyalty(Map<String, dynamic> j) {
    pointsPerUsd = _d(j['ppu']) > 0 ? _d(j['ppu']) : pointsPerUsd;
    welcomePoints = (j['welcome'] as num?)?.toInt() ?? welcomePoints;
    silverAt = (j['silverAt'] as num?)?.toInt() ?? silverAt;
    goldAt = (j['goldAt'] as num?)?.toInt() ?? goldAt;
    askCustomerAtPayment = (j['askCustomer'] as bool?) ?? askCustomerAtPayment;
    if (j['rewards'] is List) {
      rewards
        ..clear()
        ..addAll(_rewardsFrom(j['rewards'] as List));
    }
  }

  // ---------- File d'attente de synchronisation ----------
  void queueSync(String s) => queueOp('misc', s, {});

  void _op(String type, String label, Map<String, dynamic> data) {
    pendingSync.add({
      'id': '$deviceId-${DateTime.now().microsecondsSinceEpoch}',
      'type': type,
      'label': label,
      'data': data,
      'at': DateTime.now().toIso8601String(),
    });
  }

  void queueOp(String type, String label, Map<String, dynamic> data) {
    _op(type, label, data);
    notifyListeners();
  }

  Map<String, dynamic> productJson(Product p) => {
        'id': p.id, 'sku': p.sku, 'barcode': p.barcode, 'name': p.name, 'cat': p.cat, 'price': p.price,
        'floor': p.floor, 'stock': p.stock, 'min': p.min, 'promo': p.promo, 'color': p.color.value,
      };

  void queueProduct(Product p, bool created, {String? oldSku}) {
    final data = {...productJson(p), 'created': created};
    if (oldSku != null && oldSku != p.sku) data['old_sku'] = oldSku;
    queueOp('product', '${created ? 'Article créé' : 'Article modifié'} : ${p.name}', data);
  }

  Future<_Resp> _http(String method, String url, Map<String, dynamic>? body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = method == 'POST' ? await client.postUrl(Uri.parse(url)) : await client.getUrl(Uri.parse(url));
      if (serverKey.isNotEmpty) req.headers.set('Authorization', 'Bearer $serverKey');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      return _Resp(res.statusCode, text);
    } finally {
      client.close();
    }
  }

  // ---------- Synchronisation entre plusieurs PC ----------
  // Chaque PC enregistre d'abord en local, envoie ses opérations au serveur (POST /sync), puis récupère celles des
  // autres PC (GET /feed) et les applique : articles, stock, ventes, sessions, clôtures, utilisateurs, caisses, clients, réglages.
  Future<void> syncNow() async {
    if (serverUrl.isEmpty) {
      online = false;
      syncStatus = 'Mode local : aucun serveur configuré, tout est enregistré sur cet ordinateur.';
      notifyListeners();
      return;
    }
    if (_syncing) return;
    _syncing = true;
    final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    try {
      if (pendingSync.isNotEmpty) {
        final sent = List<Map<String, dynamic>>.from(pendingSync);
        final r = await _http('POST', '$base/sync', {'shop': shop, 'device': deviceId, 'name': deviceName, 'ops': sent});
        if (r.code < 200 || r.code >= 300) {
          online = false;
          syncStatus = r.code == 401 ? 'Clé d’accès refusée par le serveur.' : 'Serveur : erreur ${r.code}. Les données restent sur cet ordinateur.';
          notifyListeners();
          return;
        }
        Set<dynamic> done = sent.map((o) => o['id']).toSet();
        try {
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          if (j['done'] is List) done = Set<dynamic>.from(j['done'] as List);
        } catch (_) {}
        pendingSync.removeWhere((o) => done.contains(o['id']));
      }
      var guard = 0;
      var more = true;
      while (more && guard++ < 20) {
        final r = await _http('GET', '$base/feed?since=$feedCursor&device=${Uri.encodeQueryComponent(deviceId)}&name=${Uri.encodeQueryComponent(deviceName)}', null);
        if (r.code < 200 || r.code >= 300) {
          online = false;
          syncStatus = r.code == 401 ? 'Clé d’accès refusée par le serveur.' : 'Serveur : erreur ${r.code}.';
          notifyListeners();
          return;
        }
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        for (final o in (j['ops'] as List? ?? [])) {
          _applyRemote(Map<String, dynamic>.from(o as Map));
        }
        feedCursor = (j['last'] as num?)?.toInt() ?? feedCursor;
        more = j['more'] == true;
      }
      online = true;
      lastSync = DateTime.now();
      syncStatus = 'En ligne : dernière synchronisation à ${lastSync!.hour.toString().padLeft(2, '0')}:${lastSync!.minute.toString().padLeft(2, '0')}.';
    } catch (_) {
      online = false;
      syncStatus = 'Hors ligne : les données restent sur cet ordinateur et partiront au retour du réseau.';
    } finally {
      _syncing = false;
    }
    notifyListeners();
  }

  Product? _bySku(String sku) {
    for (final p in products) {
      if (p.sku == sku) return p;
    }
    return null;
  }

  User? _userNamed(String n) {
    for (final u in users) {
      if (u.name == n) return u;
    }
    return null;
  }

  Session? _sess(String id) {
    for (final s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  // Applique une opération venue d'un autre PC. Chaque opération n'est appliquée qu'une fois (identifiant unique).
  void _applyRemote(Map<String, dynamic> op) {
    final id = (op['id'] as String?) ?? '';
    if (id.isEmpty || _applied.contains(id)) return;
    _applied.add(id);
    appliedIds.add(id);
    if (appliedIds.length > 5000) _applied.remove(appliedIds.removeAt(0));
    final dev = (op['device'] as String?) ?? '';
    final d = Map<String, dynamic>.from((op['data'] as Map?) ?? {});
    try {
      switch (op['type']) {
        case 'product':
          _rProduct(d);
        case 'stock':
          _rStock(d);
        case 'reception':
          _rReception(d);
        case 'sale':
          _rSale(dev, d);
        case 'refund':
          _rRefund(dev, d);
        case 'session':
          _rSession(d);
        case 'closure':
          _rSession(d);
        case 'caisse':
          _rCaisse(d);
        case 'user':
          _rUser(d);
        case 'customer':
          _rCustomer(d);
        case 'cust_delta':
          _rCustDelta(d);
        case 'sale_customer':
          _rSaleCustomer(dev, d);
        case 'settings':
          _rSettings(d);
        case 'expense':
          _rExpense(d);
        case 'audit':
          _rAudit(d);
      }
    } catch (_) {
      // opération illisible : ignorée, les autres continuent
    }
  }

  void _rProduct(Map<String, dynamic> d) {
    final sku = d['sku'] as String;
    final old = d['old_sku'] as String?;
    final p = _bySku(sku) ?? (old == null ? null : _bySku(old));
    if (p == null) {
      var pid = (d['id'] as String?) ?? '';
      if (pid.isEmpty || _pid(pid) != null) pid = 'r${DateTime.now().microsecondsSinceEpoch}';
      products.add(Product(pid, (d['barcode'] as String?) ?? '', d['name'] as String, (d['cat'] as String?) ?? '', _d(d['price']), _d(d['floor']),
          d['created'] == true ? ((d['stock'] as num?)?.toInt() ?? 0) : 0, (d['min'] as num?)?.toInt() ?? 5, Icons.inventory_2,
          Color((d['color'] as int?) ?? 0xFF1D4ED8))
        ..promo = _d(d['promo']));
    } else {
      p.barcode = (d['barcode'] as String?) ?? p.barcode;
      p.name = (d['name'] as String?) ?? p.name;
      p.cat = (d['cat'] as String?) ?? p.cat;
      p.price = _d(d['price']);
      p.floor = _d(d['floor']);
      p.min = (d['min'] as num?)?.toInt() ?? p.min;
      p.promo = _d(d['promo']);
    }
  }

  void _rStock(Map<String, dynamic> d) {
    final p = _bySku(d['sku'] as String);
    if (p != null) p.stock += (d['delta'] as num).toInt();
  }

  void _rReception(Map<String, dynamic> d) {
    final rec = <String, int>{};
    for (final l in (d['lines'] as List? ?? [])) {
      final p = _bySku(l['sku'] as String);
      if (p == null) continue;
      final n = (l['delta'] as num).toInt();
      p.stock += n;
      rec[p.name] = n;
    }
    receptions.insert(0, Reception(_rno++, (d['supplier'] as String?) ?? '', rec, DateTime.now()));
  }

  void _rSale(String dev, Map<String, dynamic> d) {
    final no = d['no'] as int;
    if (sales.any((s) => s.device == dev && s.no == no)) return;
    final lines = <Line>[];
    for (final l in (d['lines'] as List? ?? [])) {
      final p = _bySku(l['sku'] as String);
      if (p == null) continue;
      final q = (l['qty'] as num).toInt();
      p.stock -= q;
      lines.add(Line(p, q, unit: _d(l['unit'])));
    }
    final method = PayMethod.values.firstWhere((x) => x.name == d['method'], orElse: () => PayMethod.cashUsd);
    final sale = Sale(no, lines, _d(d['subtotal']), _d(d['tax']), method, (d['client'] as String?) ?? '', _t(d['at']));
    sale.payments = [
      for (final p in (d['payments'] as List? ?? []))
        Payment(PayMethod.values.firstWhere((x) => x.name == p['m'], orElse: () => PayMethod.cashUsd), p['cur'] as String, _d(p['amt']), _d(p['usd']), operator: (p['op'] as String?) ?? '')
    ];
    if (sale.payments.isEmpty) sale.payments = [mkPay(method, sale.total)];
    sale.received = _d(d['received']);
    sale.cashier = (d['cashier'] as String?) ?? '';
    sale.sessionId = (d['session'] as String?) ?? '';
    sale.caisse = (d['caisse'] as String?) ?? '';
    sale.device = dev;
    sale.customerKey = (d['customerKey'] as String?) ?? '';
    sale.reward = (d['reward'] as String?) ?? '';
    sale.discount = _d(d['discount']);
    sale.earnedPoints = (d['earned'] as num?)?.toInt() ?? 0;
    sale.redeemedPoints = (d['redeemed'] as num?)?.toInt() ?? 0;
    sales.add(sale);
  }

  void _rRefund(String dev, Map<String, dynamic> d) {
    final sd = (d['sale_device'] as String?) ?? dev;
    for (final s in sales) {
      if (s.device == sd && s.no == (d['no'] as int) && !s.refunded) {
        for (final l in s.lines) {
          l.p.stock += l.qty;
        }
        s.refunded = true;
        s.cancelReason = (d['reason'] as String?) ?? '';
        s.cancelledBy = (d['by'] as String?) ?? '';
        s.cancelledAt = DateTime.now();
      }
    }
  }

  // Ouverture ou clôture d'une session venue d'un autre PC.
  void _rSession(Map<String, dynamic> d) {
    final sid = d['id'] as String;
    final s = _sess(sid) ??
        (Session(sid, d['caisseId'] as String, d['caisse'] as String, d['cashier'] as String, _t(d['opened']), _d(d['floatUsd']), _d(d['floatCdf'])));
    if (_sess(sid) == null) sessions.add(s);
    if (d['closed'] != null && s.closedAt == null) s.closedAt = _t(d['closed']);
    final c = d['closure'];
    if (c != null) {
      s.closure = Closure(_dm(c['theory']), _dm(c['counted']), _d(c['rate']) == 0 ? rate : _d(c['rate']), c['by'] as String, (c['note'] as String?) ?? '');
    }
    if (!s.open && session?.id == s.id) session = null; // le gérant a clôturé la session de ce caissier
    if (s.open) {
      for (final x in sessions) {
        if (x.open && x.id != s.id && x.caisseId == s.caisseId) {
          alert('Conflit : ${s.caisseName} est ouverte deux fois (${x.cashier} et ${s.cashier}). Clôturez l’une des deux sessions.');
        }
      }
    }
  }

  void _rCaisse(Map<String, dynamic> d) {
    final cid = d['id'] as String;
    for (final c in caisses) {
      if (c.id == cid) {
        c.name = d['name'] as String;
        c.active = (d['active'] as bool?) ?? true;
        return;
      }
    }
    caisses.add(Caisse(cid, d['name'] as String)..active = (d['active'] as bool?) ?? true);
  }

  void _rUser(Map<String, dynamic> d) {
    final name = d['name'] as String;
    var u = _userNamed(name);
    final isNew = u == null;
    u ??= User(name, Role.caissier);
    u.role = Role.values.firstWhere((r) => r.name == d['role'], orElse: () => Role.caissier);
    u.active = (d['active'] as bool?) ?? true;
    u.login = (d['login'] as String?) ?? 'pin';
    u.pinSalt = (d['pinSalt'] as String?) ?? '';
    u.pinHash = (d['pinHash'] as String?) ?? '';
    u.pwSalt = (d['pwSalt'] as String?) ?? '';
    u.pwHash = (d['pwHash'] as String?) ?? '';
    u.secSalt = (d['secSalt'] as String?) ?? '';
    u.secHash = (d['secHash'] as String?) ?? '';
    u.perms = {...List<String>.from(d['perms'] as List? ?? [])};
    u.caisses = List<String>.from(d['caisses'] as List? ?? []);
    if (isNew) users.add(u);
  }

  // Profil client venu d'un autre PC. Les soldes ne sont repris que pour un client inconnu (migration) :
  // ensuite les points et les dettes voyagent sous forme de variations (cust_delta).
  void _rCustomer(Map<String, dynamic> d) {
    final key = (d['key'] as String?) ?? normPhone((d['phone'] as String?) ?? '');
    final found = customerByKey(key);
    if (found != null) {
      found.name = (d['name'] as String?) ?? found.name;
      return;
    }
    final c = Customer((d['name'] as String?) ?? key, (d['phone'] as String?) ?? key,
        points: (d['points'] as num?)?.toInt() ?? 0, debt: _d(d['debt']), spent: _d(d['spent']),
        earned: (d['earned'] as num?)?.toInt() ?? 0, visits: (d['visits'] as num?)?.toInt() ?? 0);
    if (d['joined'] != null) c.joined = _t(d['joined']);
    customers.add(c);
  }

  void _rSettings(Map<String, dynamic> d) {
    shop = (d['shop'] as String?) ?? shop;
    if (_d(d['rate']) > 0) rate = _d(d['rate']);
    if (d.containsKey('vat')) vatRate = _d(d['vat']);
    if (d.containsKey('float')) openingFloat = _d(d['float']);
    if (d['operators'] is List && (d['operators'] as List).isNotEmpty) operators = List<String>.from(d['operators'] as List);
    lineDeletePolicy = (d['lineDelete'] as String?) ?? lineDeletePolicy;
    idleMinutes = (d['idle'] as num?)?.toInt() ?? idleMinutes;
    _loadLoyalty(d);
  }

  void _rExpense(Map<String, dynamic> d) {
    final at = _t(d['at']);
    final amount = _d(d['amount']);
    if (expenses.any((e) => e.at == at && e.by == d['by'] && e.amount == amount)) return;
    expenses.insert(0, Expense(at, (d['by'] as String?) ?? '', (d['category'] as String?) ?? '', (d['note'] as String?) ?? '', amount, (d['currency'] as String?) ?? 'USD', (d['fromCash'] as bool?) ?? false, (d['session'] as String?) ?? ''));
  }

  void _rAudit(Map<String, dynamic> d) {
    final at = _t(d['at']);
    final by = (d['by'] as String?) ?? '';
    final action = (d['action'] as String?) ?? '';
    if (audits.any((a) => a.at == at && a.by == by && a.action == action)) return;
    audits.add(Audit(at, by, action, (d['detail'] as String?) ?? '', authorizer: (d['authorizer'] as String?) ?? ''));
    audits.sort((a, b) => b.at.compareTo(a.at));
  }

  // ---------- Opérations à envoyer aux autres PC ----------
  Map<String, dynamic> userJson(User u) => {
        'name': u.name, 'role': u.role.name, 'active': u.active, 'login': u.login,
        'pinSalt': u.pinSalt, 'pinHash': u.pinHash, 'pwSalt': u.pwSalt, 'pwHash': u.pwHash,
        'secSalt': u.secSalt, 'secHash': u.secHash, 'perms': u.perms.toList(), 'caisses': u.caisses,
      };

  Map<String, dynamic> _caisseJson(Caisse c) => {'id': c.id, 'name': c.name, 'active': c.active};

  Map<String, dynamic> _customerJson(Customer c) => {
        'key': c.key, 'name': c.name, 'phone': c.phone, 'points': c.points, 'earned': c.earned, 'debt': c.debt, 'spent': c.spent,
        'visits': c.visits, 'joined': c.joined.toIso8601String(),
      };

  Map<String, dynamic> _settingsJson() =>
      {'shop': shop, 'rate': rate, 'vat': vatRate, 'float': openingFloat, 'operators': operators, 'lineDelete': lineDeletePolicy, 'idle': idleMinutes, ..._loyaltyJson()};

  void queueUser(User u) => queueOp('user', 'Utilisateur : ${u.name}', userJson(u));
  void queueCaisse(Caisse c) => queueOp('caisse', 'Caisse : ${c.name}', _caisseJson(c));
  void queueCustomer(Customer c) => queueOp('customer', 'Client : ${c.name}', _customerJson(c));
  void queueSettings() => queueOp('settings', 'Réglages', _settingsJson());

  // Envoie les données de base de ce PC (articles, caisses, utilisateurs, clients, réglages) : à faire une fois sur le PC principal.
  void queueFullState() {
    for (final p in products) {
      _op('product', 'Article envoyé : ${p.name}', {...productJson(p), 'created': true});
    }
    for (final c in caisses) {
      _op('caisse', 'Caisse : ${c.name}', _caisseJson(c));
    }
    for (final u in users) {
      _op('user', 'Utilisateur : ${u.name}', userJson(u));
    }
    for (final c in customers) {
      _op('customer', 'Client : ${c.name}', _customerJson(c));
    }
    _op('settings', 'Réglages', _settingsJson());
    notifyListeners();
  }

  // Teste l'adresse et la clé d'accès sans rien modifier.
  Future<String> testServer(String url, String key) async {
    var base = url.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (base.isEmpty) return 'Saisissez l’adresse du serveur.';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final h = await (await client.getUrl(Uri.parse('$base/health'))).close();
      await h.drain<void>();
      if (h.statusCode != 200) return 'Le serveur répond mal (code ${h.statusCode}).';
      final req = await client.getUrl(Uri.parse('$base/devices'));
      req.headers.set('Authorization', 'Bearer ${key.trim()}');
      final r = await req.close();
      await r.drain<void>();
      if (r.statusCode == 401) return 'Serveur joignable, mais la clé d’accès est refusée.';
      if (r.statusCode != 200) return 'Serveur joignable (code ${r.statusCode}).';
      return 'Connexion réussie : serveur joignable et clé acceptée.';
    } catch (_) {
      return 'Serveur injoignable : vérifiez l’adresse, le réseau et le pare-feu.';
    } finally {
      client.close();
    }
  }

  // Liste des PC qui communiquent avec le serveur.
  Future<List<Map<String, dynamic>>> fetchDevices() async {
    if (serverUrl.isEmpty) return [];
    try {
      final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
      final r = await _http('GET', '$base/devices', null);
      if (r.code != 200) return [];
      return List<Map<String, dynamic>>.from(((jsonDecode(r.body) as Map<String, dynamic>)['devices'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {
      return [];
    }
  }

  // ---------- Enregistrement local (fichier JSON dans le dossier de l'utilisateur) ----------
  String get dataDir {
    final base = Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? Directory.current.path;
    return '$base${Platform.pathSeparator}MauzoPOS';
  }

  Timer? _saveTimer;
  Timer? _syncTimer;
  Timer? _idleTimer;
  bool saveError = false;

  @override
  void notifyListeners() {
    super.notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> _save() async {
    try {
      final dir = Directory(dataDir);
      if (!await dir.exists()) await dir.create(recursive: true);
      final tmp = File('${dir.path}${Platform.pathSeparator}data.tmp');
      await tmp.writeAsString(jsonEncode(toJson()));
      final f = File('${dir.path}${Platform.pathSeparator}data.json');
      if (await f.exists()) await f.copy('${dir.path}${Platform.pathSeparator}data.bak');
      await tmp.rename(f.path);
      saveError = false;
    } catch (_) {
      saveError = true;
    }
  }

  Future<void> init() async {
    var loaded = false;
    for (final name in ['data.json', 'data.bak']) {
      try {
        final f = File('$dataDir${Platform.pathSeparator}$name');
        if (await f.exists()) {
          _load(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
          loaded = true;
          break;
        }
      } catch (_) {}
    }
    if (!loaded) await _save();
    HardwareKeyboard.instance.addHandler((_) {
      lastActivity = DateTime.now();
      return false;
    });
    // Déconnexion automatique après inactivité
    _idleTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (user != null && idleMinutes > 0 && DateTime.now().difference(lastActivity).inMinutes >= idleMinutes) {
        logout(reason: 'déconnexion automatique (inactivité)');
      }
    });
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (serverUrl.isNotEmpty) syncNow();
    });
    if (serverUrl.isNotEmpty) syncNow();
  }

  Map<String, dynamic> _saleJson(Sale s) => {
        'no': s.no, 'at': s.at.toIso8601String(), 'client': s.client, 'method': s.method.name,
        'subtotal': s.subtotal, 'tax': s.tax, 'received': s.received, 'cashier': s.cashier, 'refunded': s.refunded,
        'session': s.sessionId, 'caisse': s.caisse, 'device': s.device, 'customerKey': s.customerKey, 'reward': s.reward,
        'discount': s.discount, 'earned': s.earnedPoints, 'redeemed': s.redeemedPoints, 'cancelReason': s.cancelReason, 'cancelledBy': s.cancelledBy,
        'cancelledAt': s.cancelledAt?.toIso8601String(),
        'payments': [
          for (final p in s.payments) {'m': p.method.name, 'cur': p.currency, 'amt': p.amount, 'usd': p.usd, 'op': p.operator}
        ],
        'lines': [for (final l in s.lines) {'id': l.p.id, 'sku': l.p.sku, 'barcode': l.p.barcode, 'name': l.p.name, 'qty': l.qty, 'unit': l.unit}],
      };

  Map<String, dynamic> sessionJson(Session s) => {
        'id': s.id, 'caisseId': s.caisseId, 'caisse': s.caisseName, 'cashier': s.cashier,
        'opened': s.openedAt.toIso8601String(), 'floatUsd': s.floatUsd, 'floatCdf': s.floatCdf,
        'closed': s.closedAt?.toIso8601String(),
        'closure': s.closure == null
            ? null
            : {'theory': s.closure!.theory, 'counted': s.closure!.counted, 'rate': s.closure!.rate, 'by': s.closure!.by, 'note': s.closure!.note},
      };

  Map<String, dynamic> toJson() => {
        'v': 2, 'shop': shop, 'rate': rate, 'vat': vatRate, 'float': openingFloat,
        'serverUrl': serverUrl, 'serverKey': serverKey, 'device': deviceId, 'no': _no, 'rno': _rno, 'ono': _ono,
        'feed': feedCursor, 'applied': appliedIds, 'loyalty': _loyaltyJson(),
        'ledger': [for (final e in ledger.take(2000)) {'at': e.at.toIso8601String(), 'key': e.key, 'name': e.name, 'd': e.delta, 'r': e.reason, 'by': e.by}],
        'lineDelete': lineDeletePolicy, 'idle': idleMinutes, 'autoPrint': autoPrint, 'paper': paperMm,
        'printer': printerName, 'operators': operators,
        'products': [for (final p in products) productJson(p)],
        'customers': [
          for (final c in customers)
            {'name': c.name, 'phone': c.phone, 'points': c.points, 'earned': c.earned, 'visits': c.visits, 'joined': c.joined.toIso8601String(), 'debt': c.debt, 'spent': c.spent, 'last': c.last?.toIso8601String()}
        ],
        'sales': [for (final s in sales) _saleJson(s)],
        'orders': [
          for (final o in orders)
            {
              'no': o.no, 'client': o.client, 'source': o.source, 'total': o.total, 'status': o.status,
              'items': [for (final e in o.items.entries) {'id': e.key.id, 'q': e.value}],
            }
        ],
        'receptions': [for (final r in receptions) {'no': r.no, 'supplier': r.supplier, 'lines': r.lines, 'at': r.at.toIso8601String()}],
        'campaigns': [for (final c in campaigns) {'name': c.name, 'segment': c.segment, 'message': c.message, 'sent': c.sent, 'at': c.at.toIso8601String()}],
        'convs': [
          for (final c in convs)
            {'name': c.name, 'kind': c.kind, 'msgs': [for (final m in c.msgs) {'t': m.text, 'me': m.mine, 'at': m.at.toIso8601String()}]}
        ],
        'users': [
          for (final u in users)
            {
              'name': u.name, 'role': u.role.name, 'active': u.active, 'login': u.login,
              'pinSalt': u.pinSalt, 'pinHash': u.pinHash, 'pwSalt': u.pwSalt, 'pwHash': u.pwHash, 'secSalt': u.secSalt, 'secHash': u.secHash,
              'perms': u.perms.toList(), 'caisses': u.caisses,
            }
        ],
        'caisses': [for (final c in caisses) {'id': c.id, 'name': c.name, 'active': c.active}],
        'sessions': [for (final s in sessions) sessionJson(s)],
        'audits': [for (final a in audits) {'at': a.at.toIso8601String(), 'by': a.by, 'action': a.action, 'detail': a.detail, 'auth': a.authorizer}],
        'expenses': [
          for (final e in expenses)
            {'at': e.at.toIso8601String(), 'by': e.by, 'cat': e.category, 'note': e.note, 'amount': e.amount, 'cur': e.currency, 'cash': e.fromCash, 'session': e.sessionId}
        ],
        'outbox': pendingSync,
        'alerts': alerts,
        'week': week,
      };

  Product? _pid(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
  DateTime _t(dynamic v) => DateTime.tryParse('$v') ?? DateTime.now();
  Map<String, double> _dm(dynamic m) => (m as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()));

  void _load(Map<String, dynamic> j) {
    shop = (j['shop'] as String?) ?? shop;
    if (_d(j['rate']) > 0) rate = _d(j['rate']);
    if (j.containsKey('vat')) vatRate = _d(j['vat']);
    if (j.containsKey('float')) openingFloat = _d(j['float']);
    serverUrl = (j['serverUrl'] as String?) ?? '';
    serverKey = (j['serverKey'] as String?) ?? '';
    deviceId = (j['device'] as String?) ?? deviceId;
    _no = (j['no'] as int?) ?? _no;
    _rno = (j['rno'] as int?) ?? _rno;
    _ono = (j['ono'] as int?) ?? _ono;
    lineDeletePolicy = (j['lineDelete'] as String?) ?? lineDeletePolicy;
    feedCursor = (j['feed'] as int?) ?? 0;
    appliedIds
      ..clear()
      ..addAll(List<String>.from(j['applied'] as List? ?? []));
    _applied
      ..clear()
      ..addAll(appliedIds);
    if (j['loyalty'] is Map) _loadLoyalty(Map<String, dynamic>.from(j['loyalty'] as Map));
    ledger.clear();
    for (final e in (j['ledger'] as List? ?? [])) {
      ledger.add(PointsEntry(_t(e['at']), e['key'] as String, e['name'] as String, (e['d'] as num).toInt(), e['r'] as String, (e['by'] as String?) ?? ''));
    }
    idleMinutes = (j['idle'] as int?) ?? idleMinutes;
    autoPrint = (j['autoPrint'] as bool?) ?? autoPrint;
    paperMm = (j['paper'] as int?) ?? paperMm;
    printerName = (j['printer'] as String?) ?? printerName;
    if (j['operators'] is List && (j['operators'] as List).isNotEmpty) operators = List<String>.from(j['operators'] as List);
    products.clear();
    for (final m in (j['products'] as List? ?? [])) {
      products.add(Product(m['id'] as String, m['barcode'] as String, m['name'] as String, m['cat'] as String, _d(m['price']),
          _d(m['floor']), m['stock'] as int, m['min'] as int, Icons.inventory_2, Color(m['color'] as int))
        ..promo = _d(m['promo']));
    }
    customers.clear();
    for (final m in (j['customers'] as List? ?? [])) {
      final cu = Customer(m['name'] as String, m['phone'] as String, points: m['points'] as int, debt: _d(m['debt']), spent: _d(m['spent']),
          earned: (m['earned'] as num?)?.toInt() ?? 0, visits: (m['visits'] as num?)?.toInt() ?? 0)
        ..last = m['last'] == null ? null : _t(m['last']);
      if (m['joined'] != null) cu.joined = _t(m['joined']);
      customers.add(cu);
    }
    sales.clear();
    for (final m in (j['sales'] as List? ?? [])) {
      final lines = <Line>[];
      for (final l in (m['lines'] as List)) {
        final p = _pid(l['id'] as String);
        if (p != null) lines.add(Line(p, l['qty'] as int, unit: _d(l['unit'])));
      }
      final method = PayMethod.values.firstWhere((x) => x.name == m['method'], orElse: () => PayMethod.cashUsd);
      final sale = Sale(m['no'] as int, lines, _d(m['subtotal']), _d(m['tax']), method, m['client'] as String, _t(m['at']));
      sale.payments = m['payments'] is List
          ? [
              for (final p in (m['payments'] as List))
                Payment(PayMethod.values.firstWhere((x) => x.name == p['m'], orElse: () => PayMethod.cashUsd), p['cur'] as String, _d(p['amt']), _d(p['usd']), operator: (p['op'] as String?) ?? '')
            ]
          : [mkPay(method, sale.total)];
      sale.received = _d(m['received']);
      sale.cashier = (m['cashier'] as String?) ?? '';
      sale.refunded = (m['refunded'] as bool?) ?? false;
      sale.sessionId = (m['session'] as String?) ?? '';
      sale.device = (m['device'] as String?) ?? deviceId;
      sale.customerKey = (m['customerKey'] as String?) ?? '';
      sale.reward = (m['reward'] as String?) ?? '';
      sale.discount = _d(m['discount']);
      sale.earnedPoints = (m['earned'] as num?)?.toInt() ?? 0;
      sale.redeemedPoints = (m['redeemed'] as num?)?.toInt() ?? 0;
      sale.caisse = (m['caisse'] as String?) ?? '';
      sale.cancelReason = (m['cancelReason'] as String?) ?? '';
      sale.cancelledBy = (m['cancelledBy'] as String?) ?? '';
      sale.cancelledAt = m['cancelledAt'] == null ? null : _t(m['cancelledAt']);
      sales.add(sale);
    }
    orders.clear();
    for (final m in (j['orders'] as List? ?? [])) {
      final items = <Product, int>{};
      for (final it in (m['items'] as List)) {
        final p = _pid(it['id'] as String);
        if (p != null) items[p] = it['q'] as int;
      }
      orders.add(Order(m['no'] as int, m['client'] as String, items, _d(m['total']), m['source'] as String)..status = m['status'] as String);
    }
    receptions.clear();
    for (final m in (j['receptions'] as List? ?? [])) {
      receptions.add(Reception(m['no'] as int, m['supplier'] as String, Map<String, int>.from(m['lines'] as Map), _t(m['at'])));
    }
    campaigns.clear();
    for (final m in (j['campaigns'] as List? ?? [])) {
      campaigns.add(Campaign(m['name'] as String, m['segment'] as String, m['message'] as String, m['sent'] as int, _t(m['at'])));
    }
    convs.clear();
    for (final m in (j['convs'] as List? ?? [])) {
      final c = Conv(m['name'] as String, m['kind'] as String);
      for (final x in (m['msgs'] as List)) {
        c.msgs.add(Msg(x['t'] as String, x['me'] as bool, _t(x['at'])));
      }
      convs.add(c);
    }
    if (convs.isEmpty) convs.add(Conv('Équipe caisse', 'Équipe'));
    final us = j['users'] as List?;
    if (us != null && us.isNotEmpty) {
      users.clear();
      for (final m in us) {
        final u = User(m['name'] as String, Role.values.firstWhere((r) => r.name == m['role'], orElse: () => Role.caissier), login: (m['login'] as String?) ?? 'pin');
        u.active = (m['active'] as bool?) ?? true;
        if (m['pinHash'] != null) {
          u.pinSalt = (m['pinSalt'] as String?) ?? '';
          u.pinHash = m['pinHash'] as String;
          u.pwSalt = (m['pwSalt'] as String?) ?? '';
          u.pwHash = (m['pwHash'] as String?) ?? '';
        } else if (m['pin'] != null) {
          u.setPin(m['pin'] as String); // ancien format : le PIN en clair est haché puis oublié
        }
        u.secSalt = (m['secSalt'] as String?) ?? '';
        u.secHash = (m['secHash'] as String?) ?? '';
        u.perms = {...List<String>.from(m['perms'] as List? ?? [])};
        u.caisses = List<String>.from(m['caisses'] as List? ?? []);
        users.add(u);
      }
    }
    final cs = j['caisses'] as List?;
    if (cs != null && cs.isNotEmpty) {
      caisses.clear();
      for (final m in cs) {
        caisses.add(Caisse(m['id'] as String, m['name'] as String)..active = (m['active'] as bool?) ?? true);
      }
    }
    sessions.clear();
    for (final m in (j['sessions'] as List? ?? [])) {
      final s = Session(m['id'] as String, m['caisseId'] as String, m['caisse'] as String, m['cashier'] as String, _t(m['opened']), _d(m['floatUsd']), _d(m['floatCdf']));
      if (m['closed'] != null) s.closedAt = _t(m['closed']);
      final c = m['closure'];
      if (c != null) s.closure = Closure(_dm(c['theory']), _dm(c['counted']), _d(c['rate']) == 0 ? rate : _d(c['rate']), c['by'] as String, (c['note'] as String?) ?? '');
      sessions.add(s);
    }
    audits.clear();
    for (final m in (j['audits'] as List? ?? [])) {
      audits.add(Audit(_t(m['at']), m['by'] as String, m['action'] as String, m['detail'] as String, authorizer: (m['auth'] as String?) ?? ''));
    }
    expenses.clear();
    for (final m in (j['expenses'] as List? ?? [])) {
      expenses.add(Expense(_t(m['at']), m['by'] as String, m['cat'] as String, (m['note'] as String?) ?? '', _d(m['amount']), m['cur'] as String, (m['cash'] as bool?) ?? false, (m['session'] as String?) ?? ''));
    }
    pendingSync
      ..clear()
      ..addAll((j['outbox'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
    alerts
      ..clear()
      ..addAll(List<String>.from(j['alerts'] as List? ?? []));
    final w = j['week'] as List?;
    if (w != null && w.length == week.length) {
      for (var i = 0; i < w.length; i++) {
        week[i] = _d(w[i]);
      }
    }
  }

  // Repartir à zéro (articles, clients, ventes) pour commencer l'enregistrement réel du magasin.
  void wipeDemo() {
    products.clear();
    customers.clear();
    sales.clear();
    orders.clear();
    receptions.clear();
    campaigns.clear();
    held.clear();
    cart.clear();
    alerts.clear();
    pendingSync.clear();
    sessions.clear();
    expenses.clear();
    audits.clear();
    ledger.clear();
    appliedReward = null;
    session = null;
    _lowNotified.clear();
    convs
      ..clear()
      ..add(Conv('Équipe caisse', 'Équipe'));
    convIndex = 0;
    customer = null;
    _no = 1;
    _rno = 1;
    _ono = 1;
    week.fillRange(0, week.length, 0);
    notifyListeners();
  }
}

final app = AppState();

class _Resp {
  _Resp(this.code, this.body);
  final int code;
  final String body;
}
