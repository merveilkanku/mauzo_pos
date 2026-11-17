import 'package:flutter/material.dart';
import 'core.dart';
import 'state.dart';
import 'screens/login.dart';
import 'screens/pos.dart';
import 'screens/dashboard.dart';
import 'screens/stock.dart';
import 'screens/reception.dart';
import 'screens/customers.dart';
import 'screens/marketing.dart';
import 'screens/messages.dart';
import 'screens/orders.dart';
import 'screens/sales.dart';
import 'screens/inventory.dart';
import 'screens/reports.dart';
import 'screens/settings.dart';
import 'screens/cloture.dart';
import 'screens/users.dart';
import 'screens/expenses.dart';
import 'screens/audit.dart';
import 'screens/loyalty.dart';
import 'screens/server_screen.dart';
import 'server_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.init();
  await server.load();
  if (server.autoStart) await server.start();
  runApp(const MauzoApp());
}

const _titles = [
  'Caisse', 'Tableau de bord', 'Gestion du stock', 'Réception de marchandise', 'Clients et fidélité', 'Marketing',
  'Messages', 'Commandes', 'Factures et ventes', 'Inventaire', 'Rapports', 'Paramètres',
  'Clôture de caisse', 'Utilisateurs et caisses', 'Dépenses', 'Journal d’audit', 'Programme de fidélité', 'Serveur du réseau',
];
const _labels = [
  'Caisse', 'Tableau de bord', 'Stock', 'Réception', 'Clients', 'Marketing',
  'Messages', 'Commandes', 'Factures', 'Inventaire', 'Rapports', 'Paramètres',
  'Clôture de caisse', 'Utilisateurs', 'Dépenses', 'Journal d’audit', 'Fidélité', 'Serveur',
];
const _icons = [
  Icons.point_of_sale, Icons.dashboard, Icons.inventory_2, Icons.local_shipping, Icons.people, Icons.campaign,
  Icons.chat, Icons.shopping_bag, Icons.receipt_long, Icons.fact_check, Icons.bar_chart, Icons.settings,
  Icons.lock_clock, Icons.admin_panel_settings, Icons.money_off, Icons.history, Icons.loyalty, Icons.dns,
];

class MauzoApp extends StatelessWidget {
  const MauzoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Mauzo POS',
        theme: buildTheme(),
        // Toute action de la souris compte comme une activité (déconnexion automatique après inactivité).
        builder: (context, child) => Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => app.lastActivity = DateTime.now(),
          onPointerMove: (_) => app.lastActivity = DateTime.now(),
          child: child,
        ),
        home: const Shell(),
      );
}

class Shell extends StatelessWidget {
  const Shell({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          if (app.user == null) return const LoginScreen();
          // Le caissier n'a que l'écran de caisse, sans menu.
          if (app.user!.role == Role.caissier) return const PosScreen(kiosk: true);
          final idx = app.canSee(app.section) ? app.section : 0;
          return Scaffold(
            body: Row(children: [
              _sidebar(),
              Expanded(
                child: Column(children: [
                  _topBar(context, idx),
                  Expanded(
                    child: IndexedStack(
                      index: idx,
                      children: const [
                        PosScreen(), DashboardScreen(), StockScreen(), ReceptionScreen(), CustomersScreen(), MarketingScreen(),
                        MessagesScreen(), OrdersScreen(), SalesScreen(), InventoryScreen(), ReportsScreen(), SettingsScreen(),
                        ClotureScreen(), UsersScreen(), ExpensesScreen(), AuditScreen(), LoyaltyScreen(), ServerScreen(),
                      ],
                    ),
                  ),
                ]),
              ),
            ]),
          );
        },
      );

  Widget _sidebar() => Container(
        width: 220,
        color: C.navy,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          Row(children: [
            const MauzoMark(size: 42),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Mauzo', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                Text(app.shop, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF9FB2D8), fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          Expanded(
            child: ListView(children: [
              for (var i = 0; i < _titles.length; i++)
                if (app.canSee(i)) _item(i),
            ]),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0x22FFFFFF), borderRadius: BorderRadius.circular(10)),
            child: const Text('Msaidizi, l’assistant, suggère déjà des réponses dans Messages.', style: TextStyle(color: Color(0xFFC9D6F2), fontSize: 12)),
          ),
        ]),
      );

  Widget _item(int i) {
    final sel = app.section == i;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => app.go(i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: sel ? C.blue : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Icon(_icons[i], color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(_labels[i], style: TextStyle(color: Colors.white, fontWeight: sel ? FontWeight.w700 : FontWeight.w500))),
          ]),
        ),
      ),
    );
  }

  void _alerts(BuildContext context) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Signalements de la caisse'),
          content: SizedBox(
            width: 440,
            child: app.alerts.isEmpty
                ? const Text('Aucun signalement.')
                : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final a in app.alerts.take(12)) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $a')),
                  ]),
          ),
          actions: [
            TextButton(
              onPressed: () {
                app.alerts.clear();
                app.touch();
                Navigator.pop(ctx);
              },
              child: const Text('Tout effacer'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
          ],
        ),
      );

  Widget _topBar(BuildContext context, int idx) => Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: C.line))),
        child: Row(children: [
          Text(_titles[idx], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.text)),
          const Spacer(),
          IconButton(
            tooltip: 'Signalements',
            onPressed: () => _alerts(context),
            icon: Badge(isLabelVisible: app.alerts.isNotEmpty, label: Text('${app.alerts.length}'), child: const Icon(Icons.notifications)),
          ),
          InkWell(onTap: app.syncNow, child: syncPill()),
          const SizedBox(width: 10),
          Pill('1 \$ = ${group(app.rate)} FC', C.blue, C.blueSoft),
          const SizedBox(width: 10),
          Pill('${app.user!.name} · ${app.user!.roleLabel}', C.green, C.greenSoft),
          const SizedBox(width: 10),
          TextButton(onPressed: () => app.logout(), child: const Text('Verrouiller')),
        ]),
      );
}
