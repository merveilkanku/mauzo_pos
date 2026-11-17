import 'package:flutter/material.dart';
import '../core.dart';
import '../state.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Widget _kpi(String t, String v, String s, Color c) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: muted),
              const SizedBox(height: 6),
              Text(v, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c)),
              Text(s, style: muted),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final series = [...app.week, app.todayTotal];
          final mix = app.byMethod;
          final mixTotal = mix.values.fold(0.0, (a, b) => a + b);
          final top = app.topProducts.take(5).toList();
          final low = app.products.where((p) => p.low).toList();
          final avg = app.todaySales.isEmpty ? 0.0 : app.todayTotal / app.todaySales.length;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _kpi('Ventes du jour', usd(app.todayTotal), cdf(app.todayTotal * app.rate), C.blue),
                _kpi('Tickets', '${app.todaySales.length}', 'aujourd’hui', C.text),
                _kpi('Panier moyen', usd(avg), 'par ticket', C.green),
                _kpi('Articles à réapprovisionner', '${low.length}', 'stock bas ou rupture', low.isEmpty ? C.green : C.red),
              ]),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Panel(
                      title: 'Encaissements des 7 derniers jours',
                      child: Column(children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: SizedBox(height: 200, width: double.infinity, child: CustomPaint(painter: LinePainter(series))),
                        ),
                        const SizedBox(height: 8),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          for (final d in ['J-6', 'J-5', 'J-4', 'J-3', 'J-2', 'J-1', 'Auj.']) Text(d, style: muted),
                        ]),
                      ]),
                    ),
                  ),
                ),
                Expanded(
                  child: Panel(
                    title: 'Moyens de paiement',
                    child: Column(children: [
                      for (final e in mix.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            SizedBox(width: 92, child: Text(e.key.label, style: muted)),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(value: mixTotal == 0 ? 0 : e.value / mixTotal, minHeight: 10, color: C.blue, backgroundColor: C.blueSoft),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(usd(e.value), style: bold),
                          ]),
                        ),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Panel(
                      title: 'Produits les plus vendus',
                      child: Column(children: [
                        for (final e in top) kv(e.key, '${e.value} vendus'),
                      ]),
                    ),
                  ),
                ),
                Expanded(
                  child: Panel(
                    title: 'Alertes de stock',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (low.isEmpty) const Text('Aucune alerte.', style: muted),
                      for (final p in low)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            Expanded(child: Text('${p.name} (${p.stock})', style: bold)),
                            stockPill(p),
                          ]),
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: () => app.go(2), child: const Text('Ouvrir le stock')),
                    ]),
                  ),
                ),
              ]),
            ]),
          );
        },
      );
}

class LinePainter extends CustomPainter {
  LinePainter(this.v);
  final List<double> v;

  @override
  void paint(Canvas c, Size s) {
    final top = v.reduce((a, b) => a > b ? a : b);
    final mx = (top <= 0 ? 1.0 : top) * 1.15;
    final grid = Paint()
      ..color = C.line
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = s.height * i / 4;
      c.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }
    final pts = <Offset>[
      for (var i = 0; i < v.length; i++) Offset(s.width * i / (v.length - 1), s.height - (v[i] / mx) * s.height),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(path)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    c.drawPath(fill, Paint()..color = C.blue.withOpacity(0.10));
    c.drawPath(
      path,
      Paint()
        ..color = C.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    for (final p in pts) {
      c.drawCircle(p, 4, Paint()..color = C.blue);
    }
  }

  @override
  bool shouldRepaint(covariant LinePainter old) => true;
}
