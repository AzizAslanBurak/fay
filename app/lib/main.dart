import 'package:flutter/material.dart';

import 'eth/fay_pool.dart';
import 'eth/wallet.dart';
import 'l10n.dart';
import 'screens/buy_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/policies_screen.dart';

void main() => runApp(const FayApp());

/// Basit bağımlılık taşıyıcı (provider paketi olmadan).
class AppScope extends InheritedWidget {
  final L10n l10n;
  final Wallet wallet;
  final FayPool pool;
  const AppScope({super.key, required this.l10n, required this.wallet, required this.pool, required super.child});
  static AppScope of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<AppScope>()!;
  @override
  bool updateShouldNotify(AppScope old) => true;
}

class FayApp extends StatefulWidget {
  const FayApp({super.key});
  @override
  State<FayApp> createState() => _FayAppState();
}

class _FayAppState extends State<FayApp> {
  final l10n = L10n();
  final wallet = Wallet();
  final pool = FayPool();

  @override
  void initState() {
    super.initState();
    l10n.addListener(_rebuild);
    wallet.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1D4ED8);
    return AppScope(
      l10n: l10n,
      wallet: wallet,
      pool: pool,
      child: MaterialApp(
        title: 'Fay',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
          useMaterial3: true,
          fontFamily: 'Inter',
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: const Shell(),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = scope.l10n.t;
    final w = scope.wallet;
    final wide = MediaQuery.of(context).size.width > 900;

    final pages = const [DashboardScreen(), BuyScreen(), PoliciesScreen()];
    final dests = [
      (Icons.dashboard_outlined, Icons.dashboard, t('nav_dashboard')),
      (Icons.shield_outlined, Icons.shield, t('nav_buy')),
      (Icons.receipt_long_outlined, Icons.receipt_long, t('nav_policies')),
    ];

    Widget walletButton() {
      if (!w.available) {
        return Tooltip(message: t('no_wallet'), child: const Icon(Icons.account_balance_wallet_outlined));
      }
      if (!w.connected) {
        return FilledButton.icon(
          onPressed: w.connect,
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: Text(t('connect')),
        );
      }
      if (!w.onSepolia) {
        return FilledButton.tonalIcon(
          onPressed: w.switchToSepolia,
          icon: const Icon(Icons.swap_horiz),
          label: Text(t('wrong_network')),
        );
      }
      return Chip(
        avatar: const Icon(Icons.check_circle, color: Colors.green, size: 18),
        label: Text(shortAddr(w.address!)),
      );
    }

    final appBar = AppBar(
      title: Row(children: [
        const Icon(Icons.waves, size: 26),
        const SizedBox(width: 8),
        Text(t('app_title'), style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(width: 8),
        const Chip(label: Text('Sepolia'), visualDensity: VisualDensity.compact),
      ]),
      actions: [
        walletButton(),
        const SizedBox(width: 8),
        TextButton(onPressed: scope.l10n.toggle, child: Text(t('lang'))),
        const SizedBox(width: 8),
      ],
    );

    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in dests)
                NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages[_index]),
        ]),
      );
    }
    return Scaffold(
      appBar: appBar,
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in dests) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
        ],
      ),
    );
  }
}
