import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:web/web.dart' as web;

import '../config.dart';
import '../eth/fay_pool.dart';
import '../main.dart';

class BuyScreen extends StatefulWidget {
  const BuyScreen({super.key});
  @override
  State<BuyScreen> createState() => _BuyScreenState();
}

class _BuyScreenState extends State<BuyScreen> {
  static const presets = <String, LatLng>{
    'İstanbul': LatLng(41.01, 28.98),
    'İzmir': LatLng(38.42, 27.14),
    'Hatay': LatLng(36.20, 36.16),
    'Kahramanmaraş': LatLng(37.58, 36.93),
    'Van': LatLng(38.49, 43.38),
  };

  LatLng _point = presets['İstanbul']!;
  double _coverageEth = 0.01;
  BigInt? _premiumWei;
  bool _busy = false;
  bool _private = true;
  String? _txHash;
  String? _error;

  bool _quoted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_quoted) {
      _quoted = true;
      _quote();
    }
  }

  BigInt get _coverageWei => BigInt.from((_coverageEth * 1e18).round());

  Future<void> _quote() async {
    try {
      final p = await AppScope.of(context).pool.quotePremium(_coverageWei);
      if (mounted) setState(() => _premiumWei = p);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _buy() async {
    final scope = AppScope.of(context);
    final w = scope.wallet;
    if (!w.connected) {
      await w.connect();
      if (!w.connected) return;
    }
    if (!w.onSepolia) {
      await w.switchToSepolia();
      if (!w.onSepolia) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _txHash = null;
    });
    try {
      if (_private) {
        final rnd = Random.secure();
        final salt = Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
        final commit = FayPool.locationCommit(_point.latitude, _point.longitude, salt);
        final data = scope.pool.buyPolicyPrivateCalldata(commit: commit, coverageWei: _coverageWei);
        final hash = await w.sendTransaction(to: FayConfig.fayPoolAddress, dataHex: data, value: _premiumWei);
        setState(() => _txHash = hash);
        final nextId = (await scope.pool.policyCountAfter(hash)).toInt();
        await http.post(
          Uri.parse(FayConfig.vaultUrl),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'policyId': nextId,
            'latE6': (_point.latitude * 1e6).round(),
            'lonE6': (_point.longitude * 1e6).round(),
            'salt': '0x${salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
            'commit': '0x${commit.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
          }),
        );
      } else {
        final data = scope.pool.buyPolicyCalldata(lat: _point.latitude, lon: _point.longitude, coverageWei: _coverageWei);
        final hash = await w.sendTransaction(to: FayConfig.fayPoolAddress, dataHex: data, value: _premiumWei);
        setState(() => _txHash = hash);
        await scope.pool.policyCountAfter(hash);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      scope.pool.notifyChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).l10n.t;
    final wide = MediaQuery.of(context).size.width > 900;

    final map = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: const LatLng(39.0, 35.0),
          initialZoom: 5.3,
          onTap: (_, latlng) => setState(() => _point = latlng),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'link.fay.app',
          ),
          MarkerLayer(markers: [
            Marker(
              point: _point,
              width: 40,
              height: 40,
              child: const Icon(Icons.location_on, color: Colors.red, size: 40),
            ),
          ]),
        ],
      ),
    );

    final form = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('pick_location'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text('${_point.latitude.toStringAsFixed(4)}, ${_point.longitude.toStringAsFixed(4)}',
          style: const TextStyle(fontFamily: 'monospace')),
      const SizedBox(height: 12),
      Text(t('presets'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
      Wrap(spacing: 8, children: [
        for (final e in presets.entries)
          ChoiceChip(
            label: Text(e.key),
            selected: _point == e.value,
            onSelected: (_) => setState(() => _point = e.value),
          ),
      ]),
      const SizedBox(height: 20),
      Text('${t('coverage')}: ${_coverageEth.toStringAsFixed(3)} ETH', style: Theme.of(context).textTheme.titleMedium),
      Slider(
        value: _coverageEth,
        min: 0.001,
        max: 0.05,
        divisions: 49,
        label: '${_coverageEth.toStringAsFixed(3)} ETH',
        onChanged: (v) => setState(() => _coverageEth = v),
        onChangeEnd: (_) => _quote(),
      ),
      Text('${t('premium')}: ${_premiumWei == null ? '…' : fmtEth(_premiumWei!)}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _private,
        onChanged: (v) => setState(() => _private = v),
        title: Text(t('private_policy')),
        subtitle: Text(t('private_policy_hint'), style: const TextStyle(fontSize: 12)),
        secondary: Icon(_private ? Icons.lock : Icons.lock_open),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _busy || _premiumWei == null ? null : _buy,
        icon: _busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.shield),
        label: Text(_busy ? t('buying') : t('buy')),
      ),
      if (_txHash != null) ...[
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 8),
          Text(t('bought')),
          TextButton(
            onPressed: () => web.window.open('${FayConfig.explorer}/tx/$_txHash', '_blank'),
            child: Text(t('view_tx')),
          ),
        ]),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
      ],
      const SizedBox(height: 24),
      Text(t('disclaimer'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
    ]);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: SizedBox(height: 560, child: map)),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: SingleChildScrollView(child: form)),
            ])
          : ListView(children: [SizedBox(height: 320, child: map), const SizedBox(height: 16), form]),
    );
  }
}
