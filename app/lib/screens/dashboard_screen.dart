import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:web/web.dart' as web;

import '../config.dart';
import '../eth/fay_pool.dart';
import '../main.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

typedef _Data = (PoolStats, List<QuakeEvent>, List<Payout>, List<Policy>);

class _DashboardScreenState extends State<DashboardScreen> {
  Future<_Data>? _future;
  FayPool? _pool;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pool = AppScope.of(context).pool;
    if (_pool != pool) {
      _pool?.changed.removeListener(_reload);
      _pool = pool..changed.addListener(_reload);
    }
    _future ??= _load();
  }

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  @override
  void dispose() {
    _pool?.changed.removeListener(_reload);
    super.dispose();
  }

  Future<_Data> _load() async {
    final pool = AppScope.of(context).pool;
    final r = await Future.wait([pool.stats(), pool.quakeEvents(), pool.payouts(), pool.allPolicies()]);
    return (r[0] as PoolStats, r[1] as List<QuakeEvent>, r[2] as List<Payout>, r[3] as List<Policy>);
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
          final (stats, quakes, payouts, policies) = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(children: [
                Expanded(child: Text(t('tagline'), style: Theme.of(context).textTheme.titleLarge)),
                IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: t('refresh')),
              ]),
              const SizedBox(height: 20),
              _PoolHealthCard(stats: stats),
              const SizedBox(height: 20),
              _CoverageMap(quakes: quakes, payouts: payouts, policies: policies),
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

class _CoverageMap extends StatelessWidget {
  final List<QuakeEvent> quakes;
  final List<Payout> payouts;
  final List<Policy> policies;
  const _CoverageMap({required this.quakes, required this.payouts, required this.policies});

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).l10n.t;
    final paid = {for (final p in payouts) p.policyId};
    final circles = <CircleMarker>[];
    for (final q in quakes) {
      final (full, half) = FayPool.payoutRadiiKm(q.mag);
      circles.add(CircleMarker(
        point: LatLng(q.lat, q.lon),
        radius: half * 1000,
        useRadiusInMeter: true,
        color: Colors.orange.withOpacity(0.12),
        borderColor: Colors.orange,
        borderStrokeWidth: 1.5,
      ));
      circles.add(CircleMarker(
        point: LatLng(q.lat, q.lon),
        radius: full * 1000,
        useRadiusInMeter: true,
        color: Colors.red.withOpacity(0.18),
        borderColor: Colors.red,
        borderStrokeWidth: 1.5,
      ));
    }
    final markers = <Marker>[
      for (final p in policies.where((p) => !p.isPrivate))
        Marker(
          point: LatLng(p.lat, p.lon),
          width: 32,
          height: 32,
          child: Tooltip(
            message: '${t('policy')} #${p.id} · ${fmtEth(p.coverageWei)}',
            child: Icon(
              paid.contains(p.id) ? Icons.paid : Icons.shield,
              color: paid.contains(p.id) ? Colors.green : (p.active ? Theme.of(context).colorScheme.primary : Colors.grey),
              size: 26,
            ),
          ),
        ),
      for (final q in quakes)
        Marker(
          point: LatLng(q.lat, q.lon),
          width: 36,
          height: 36,
          child: Tooltip(
            message: 'M${q.mag.toStringAsFixed(1)} · ${fmtEth(q.totalPaidWei)}',
            child: const Icon(Icons.flash_on, color: Colors.red, size: 30),
          ),
        ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('map_title'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 340,
              child: FlutterMap(
                options: const MapOptions(initialCenter: LatLng(38.6, 35.5), initialZoom: 5.2),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'link.fay.app',
                  ),
                  CircleLayer(circles: circles),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(t('map_legend'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ),
    );
  }
}
