import 'package:flutter/material.dart';

import '../eth/fay_pool.dart';
import '../main.dart';

class PoliciesScreen extends StatefulWidget {
  const PoliciesScreen({super.key});
  @override
  State<PoliciesScreen> createState() => _PoliciesScreenState();
}

class _PoliciesScreenState extends State<PoliciesScreen> {
  Future<(List<Policy>, List<Payout>)>? _future;
  String? _forAddress;

  Future<(List<Policy>, List<Payout>)> _load(String addr) async {
    final pool = AppScope.of(context).pool;
    final r = await Future.wait([pool.policiesOf(addr), pool.payouts()]);
    final payouts = (r[1] as List<Payout>).where((p) => p.holder == addr).toList();
    return (r[0] as List<Policy>, payouts);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = scope.l10n.t;
    final w = scope.wallet;

    if (!w.connected) {
      return Center(
        child: FilledButton.icon(onPressed: w.connect, icon: const Icon(Icons.account_balance_wallet), label: Text(t('connect'))),
      );
    }
    if (_forAddress != w.address) {
      _forAddress = w.address;
      _future = _load(w.address!);
    }

    return FutureBuilder(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('RPC error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final (policies, payouts) = snap.data!;
        if (policies.isEmpty) return Center(child: Text(t('no_policies')));
        final paidIds = {for (final p in payouts) p.policyId: p};
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final p in policies)
              Card(
                child: ListTile(
                  leading: Icon(
                    paidIds.containsKey(p.id)
                        ? Icons.payments
                        : p.active
                            ? Icons.shield
                            : Icons.shield_outlined,
                    color: paidIds.containsKey(p.id)
                        ? Colors.green
                        : p.active
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                  ),
                  title: Text('${t('policy')} #${p.id} · ${fmtEth(p.coverageWei)}'),
                  subtitle: Text(
                    '${p.isPrivate ? '🔒 ${t('private_policy')}' : '${p.lat.toStringAsFixed(3)}, ${p.lon.toStringAsFixed(3)}'} · '
                    '${paidIds.containsKey(p.id) ? '${t('paid')} ${fmtEth(paidIds[p.id]!.amountWei)}' : p.active ? t('active') : p.expiresAt.isBefore(DateTime.now()) ? t('expired') : t('paid')}'
                    ' · ${p.expiresAt.toIso8601String().substring(0, 10)}',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
