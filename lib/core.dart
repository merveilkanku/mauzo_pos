import 'package:flutter/material.dart';
import 'state.dart';

class C {
  static const navy = Color(0xFF0B1B3F);
  static const blue = Color(0xFF1D4ED8);
  static const blueSoft = Color(0xFFE6EDFD);
  static const green = Color(0xFF0E8F4F);
  static const greenSoft = Color(0xFFE2F5EA);
  static const red = Color(0xFFD92D20);
  static const redSoft = Color(0xFFFDECEA);
  static const amber = Color(0xFFB45309);
  static const amberSoft = Color(0xFFFEF3E2);
  static const bg = Color(0xFFF2F5FA);
  static const line = Color(0xFFE1E7F0);
  static const text = Color(0xFF0F1B33);
  static const muted = Color(0xFF64738B);
}

const muted = TextStyle(color: C.muted, fontSize: 13);
const bold = TextStyle(color: C.text, fontWeight: FontWeight.w700, fontSize: 14);
const mono = TextStyle(fontFamily: 'Consolas', fontSize: 13);

String group(num n) => n
    .round()
    .toString()
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ' ');
String usd(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} \$';
String cdf(double v) => '${group(v)} FC';
String money(double v, String cur) => cur == 'CDF' ? cdf(v) : usd(v);
String signed(double v, String cur) => '${v >= 0 ? '+' : ''}${money(v, cur)}';
String dateFr(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String timeFr(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: C.blue, primary: C.blue, secondary: C.green),
      scaffoldBackgroundColor: C.bg,
      fontFamily: 'Segoe UI',
    );

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.title});
  final Widget child;
  final String? title;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(title!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: C.text)),
              ),
            child,
          ],
        ),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.label, this.fg, this.bg, {super.key});
  final String label;
  final Color fg, bg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

Widget stockPill(Product p) {
  if (p.stock <= 0) return const Pill('Rupture', C.red, C.redSoft);
  if (p.low) return const Pill('Stock bas', C.amber, C.amberSoft);
  return const Pill('En stock', C.green, C.greenSoft);
}

Widget kv(String a, String b, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(a, style: strong ? bold : muted),
        const Spacer(),
        Text(b, style: strong ? bold : const TextStyle(color: C.text, fontSize: 13)),
      ]),
    );

Widget syncPill() {
  final n = app.pendingSync.length;
  if (app.serverUrl.isEmpty) {
    return Pill(n == 0 ? 'Mode local · enregistré' : 'Mode local · $n à envoyer plus tard', C.blue, C.blueSoft);
  }
  if (app.online) return Pill(n == 0 ? 'En ligne · à jour' : 'En ligne · $n en attente', C.green, C.greenSoft);
  return Pill('Hors ligne · $n en attente', C.amber, C.amberSoft);
}

String receipt(Sale s) {
  final b = StringBuffer();
  b.writeln(app.shop.toUpperCase());
  b.writeln('Ticket n° ${s.no}   ${dateFr(s.at)} ${timeFr(s.at)}');
  b.writeln('${s.caisse.isEmpty ? 'Caisse' : s.caisse} · Caissier : ${s.cashier.isEmpty ? '-' : s.cashier}');
  if (s.refunded) b.writeln('*** FACTURE ANNULÉE ***');
  b.writeln('--------------------------------');
  for (final l in s.lines) {
    b.writeln(l.p.name);
    b.writeln('   ${l.qty} x ${usd(l.unit)}   ${usd(l.total)}');
  }
  b.writeln('--------------------------------');
  b.writeln('Articles : ${s.lines.fold(0, (a, l) => a + l.qty)}');
  if (s.discount > 0.004) {
    b.writeln('Sous-total  ${usd(s.subtotal + s.discount)}');
    b.writeln('Remise (${s.reward})  -${usd(s.discount)}');
  }
  b.writeln('Total HT   ${usd(s.subtotal)}');
  b.writeln('TVA        ${usd(s.tax)}');
  b.writeln('TOTAL TTC  ${usd(s.total)}');
  b.writeln('En francs  ${cdf(s.total * app.rate)}');
  b.writeln('Paiement :');
  for (final p in s.payments) {
    b.writeln('  ${p.label} : ${money(p.amount, p.currency)}');
  }
  if (s.received - s.total > 0.004) {
    b.writeln('Reçu : ${usd(s.received)}');
    b.writeln('Rendu : ${usd(s.received - s.total)}');
  }
  b.writeln('Client : ${s.client}');
  if (s.customerKey.isNotEmpty) {
    b.writeln('Points gagnés : ${s.earnedPoints}');
    if (s.redeemedPoints > 0) b.writeln('Points utilisés : ${s.redeemedPoints}');
    final c = app.customerByKey(s.customerKey);
    if (c != null) b.writeln('Solde : ${c.points} points (${app.tierOf(c)})');
  }
  b.write('Merci de votre visite !');
  return b.toString();
}

String invoiceText(Sale s) {
  final b = StringBuffer();
  b.writeln('FACTURE N° FAC-${s.no.toString().padLeft(4, '0')}');
  b.writeln(app.shop);
  b.writeln('Date : ${dateFr(s.at)} ${timeFr(s.at)}');
  final cu = app.customerByKey(s.customerKey);
  b.writeln('Client : ${s.client}${cu == null ? '' : ' (WhatsApp ${cu.phone})'}');
  b.writeln('--------------------------------');
  for (final l in s.lines) {
    b.writeln('${l.p.name}\n   ${l.qty} x ${usd(l.unit)} = ${usd(l.total)}');
  }
  b.writeln('--------------------------------');
  if (s.discount > 0.004) b.writeln('Remise fidélité (${s.reward}) : -${usd(s.discount)}');
  b.writeln('Total HT  : ${usd(s.subtotal)}');
  b.writeln('TVA ${(app.vatRate * 100).round()} % : ${usd(s.tax)}');
  b.writeln('Total TTC : ${usd(s.total)} (${cdf(s.total * app.rate)})');
  b.writeln('Règlement : ${s.methodLabel}');
  b.write('Numéro fiscal et mentions légales : à compléter avec votre comptable.');
  return b.toString();
}

// Rapport de clôture : montants par moyen de paiement, chacun dans sa devise, avec écart.
String closureReport(Session s) {
  final c = s.closure;
  final theory = c?.theory ?? app.theoryOf(s);
  final keys = theory.keys.toList()..sort();
  final b = StringBuffer();
  b.writeln('RAPPORT DE CLÔTURE DE CAISSE');
  b.writeln(app.shop);
  b.writeln('--------------------------------');
  b.writeln('Caisse : ${s.caisseName}');
  b.writeln('Caissier : ${s.cashier}');
  b.writeln('Ouverture : ${dateFr(s.openedAt)} ${timeFr(s.openedAt)}');
  b.writeln('Fermeture : ${s.closedAt == null ? '-' : '${dateFr(s.closedAt!)} ${timeFr(s.closedAt!)}'}');
  b.writeln('Nombre de factures : ${app.salesOf(s).length}');
  b.writeln('--------------------------------');
  b.writeln('Fond de caisse : ${usd(s.floatUsd)} / ${cdf(s.floatCdf)}');
  final sums = <String, double>{};
  app.channelsOf(s).forEach((k, v) => sums[currencyOfKey(k)] = (sums[currencyOfKey(k)] ?? 0) + v);
  sums.forEach((cur, v) => b.writeln('Total des ventes encaissées $cur : ${money(v, cur)}'));
  b.writeln('Ventes à l’ardoise (non encaissées) : ${usd(app.creditOf(s))}');
  b.writeln('--------------------------------');
  for (final k in keys) {
    final cur = currencyOfKey(k);
    final t = theory[k] ?? 0;
    b.writeln(labelOfKey(k));
    b.writeln('   Théorique : ${money(t, cur)}');
    if (c != null) {
      final n = c.counted[k] ?? 0;
      b.writeln('   Compté    : ${money(n, cur)}');
      b.writeln('   Écart     : ${signed(n - t, cur)}');
    }
  }
  if (c != null) {
    b.writeln('--------------------------------');
    b.writeln('Écart total : ${signed(c.varianceUsd(), 'USD')} (taux ${group(c.rate)} FC pour 1 \$)');
    b.writeln('Clôturé par : ${c.by}');
    if (c.note.isNotEmpty) b.writeln('Remarques : ${c.note}');
  }
  return b.toString();
}

/// Demande le mot de sécurité du gérant connecté (s'il en a un) avant une action sensible. Retourne true si autorisé.
Future<bool> askSecurity(BuildContext context, String why) async {
  final u = app.user;
  if (u == null || u.role != Role.gerant || !u.hasSecurity) return true;
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Mot de sécurité'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(why, style: muted),
        const SizedBox(height: 10),
        TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          onSubmitted: (_) => Navigator.pop(ctx, true),
          decoration: const InputDecoration(labelText: 'Votre mot de sécurité', border: OutlineInputBorder()),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Valider')),
      ],
    ),
  );
  if (ok != true) return false;
  if (u.checkSecurity(c.text)) return true;
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mot de sécurité incorrect.')));
  return false;
}

/// Logo Mauzo dessiné par le code : un « M » dont la moitié droite verte monte comme une courbe de ventes.
class MauzoMark extends StatelessWidget {
  const MauzoMark({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _MarkPainter()));
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final u = s.width / 1024;
    final rect = Offset.zero & s;
    c.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(230 * u)),
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2B5FE8), Color(0xFF0B1B3F)]).createShader(rect),
    );
    Paint stroke(Color col) => Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = 100 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final left = Path()
      ..moveTo(270 * u, 730 * u)
      ..lineTo(270 * u, 330 * u)
      ..lineTo(512 * u, 610 * u);
    final right = Path()
      ..moveTo(512 * u, 610 * u)
      ..lineTo(754 * u, 330 * u)
      ..lineTo(754 * u, 730 * u);
    c.drawPath(left, stroke(Colors.white));
    c.drawPath(right, stroke(const Color(0xFF2ED38A)));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
