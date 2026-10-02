import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../config.dart';
import '../eth/fay_pool.dart';
import '../main.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Future<(PoolStats, List<QuakeEvent>, List<Payout>)>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<(PoolStats, List<QuakeEvent>, List<Payout>)> _load() async {
    final pool = AppScope.of(context).pool;
    final r = await Future.wait([pool.stats(), pool.quakeEvents(), pool.payouts()]);
    return (r[0] as PoolStats, r[1] as List<QuakeEvent>, r[2] as List<Payout>);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).l10n.t;
    return RefreshIndicator(
      onRefresh: () async => setState(() => _future = _load()),
      child: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('RPC error: ${snap.error}'));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (stats, quakes, payouts) = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(t('tagline'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              _PoolHealthCard(stats: stats),
              const SizedBox(height: 20),
              _HowItWorks(),
              const SizedBox(height: 20),
              Text(t('recent_events'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (quakes.isEmpty) Text(t('no_events'), style: const TextStyle(color: Colors.grey)),
              for (final q in quakes) _QuakeTile(q: q),
              const SizedBox(height: 20),
              Text(t('payouts'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final p in payouts) _PayoutTile(p: p),
              const SizedBox(height: 32),
              Text(t('disclaimer'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          );
        },
      ),
    );
  }
}

class _PoolHealthCard extends StatelessWidget {
  final PoolStats stats;
  const _PoolHealthCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).l10n.t;
    final healthy = stats.reserveHealthBps >= BigInt.from(10000);
    final healthPct = stats.reserveHealthBps > BigInt.from(100000) ? '—' : '${(stats.reserveHealthBps.toInt() / 100).toStringAsFixed(0)}%';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(stats.salesPaused ? Icons.pause_circle : Icons.check_circle, color: stats.salesPaused ? Colors.orange : Colors.green),
            const SizedBox(width: 8),
            Text(t('pool_health'), style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Text(stats.salesPaused ? t('sales_paused') : t('sales_open'),
                style: TextStyle(color: stats.salesPaused ? Colors.orange : Colors.green)),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 32, runSpacing: 12, children: [
            _Stat(t('pool_balance'), fmtEth(stats.balanceWei)),
            _Stat(t('active_coverage'), fmtEth(stats.activeCoverageWei)),
            _Stat(t('reserve_ratio'), healthPct, color: healthy ? Colors.green : Colors.red),
            _Stat(t('policies_count'), '${stats.activePolicies} / ${stats.policyCount}'),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.security, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            Text(
              stats.lastGuardianAt == null
                  ? t('guardian_none')
                  : '${t('guardian_last')}: ${stats.lastGuardianAt!.toLocal().toString().substring(0, 16)} · ${stats.lastGuardianHealthBps == BigInt.zero ? '—' : '${(stats.lastGuardianHealthBps.toInt() / 100).toStringAsFixed(0)}%'}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _Stat(this.label, this.value, {this.color});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: color)),
      ]);
}

class _HowItWorks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).l10n.t;
    final steps = [
      (Icons.place_outlined, t('how_1')),
      (Icons.hub_outlined, t('how_2')),
      (Icons.bolt_outlined, t('how_3')),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('how_it_works'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final s in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [Icon(s.$1), const SizedBox(width: 12), Expanded(child: Text(s.$2))]),
            ),
        ]),
      ),
    );
  }
}

class _QuakeTile extends StatelessWidget {
  final QuakeEvent q;
  const _QuakeTile({required this.q});
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).l10n.t;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: q.mag >= 7 ? Colors.red : Colors.orange,
          child: Text('M${q.mag.toStringAsFixed(1)}', style: const TextStyle(color: Colors.white, fontSize: 11)),
        ),
        title: Text('${q.lat.toStringAsFixed(3)}, ${q.lon.toStringAsFixed(3)}'),
        subtitle: Text('${q.policiesPaid} ${q.policiesPaid == 1 ? t('policy').toLowerCase() : t('policies_count').toLowerCase()} · ${fmtEth(q.totalPaidWei)} · block ${q.block}'),
        trailing: IconButton(
          icon: const Icon(Icons.open_in_new),
          tooltip: t('view_tx'),
          onPressed: () => web.window.open('${FayConfig.explorer}/tx/${q.txHash}', '_blank'),
        ),
      ),
    );
  }
}

class _PayoutTile extends StatelessWidget {
  final Payout p;
  const _PayoutTile({required this.p});
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).l10n.t;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.payments_outlined, color: Colors.green),
        title: Text('${t('policy')} #${p.policyId} → ${shortAddr(p.holder)}'),
        subtitle: Text('${fmtEth(p.amountWei)} · ${p.tier == 1 ? t('tier_full') : t('tier_half')}'),
        trailing: IconButton(
          icon: const Icon(Icons.open_in_new),
          onPressed: () => web.window.open('${FayConfig.explorer}/tx/${p.txHash}', '_blank'),
        ),
      ),
    );
  }
}
