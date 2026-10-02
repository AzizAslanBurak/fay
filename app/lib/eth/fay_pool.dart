// FayPool sözleşmesi: okuma (RPC) + işlem verisi üretme (MetaMask'a verilir) + olay tarama.
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';

import '../config.dart';

const _abiJson = '''
[
  {"type":"function","name":"policyCount","stateMutability":"view","inputs":[],"outputs":[{"name":"","type":"uint256"}]},
  {"type":"function","name":"activePolicyCount","stateMutability":"view","inputs":[],"outputs":[{"name":"","type":"uint256"}]},
  {"type":"function","name":"totalActiveCoverage","stateMutability":"view","inputs":[],"outputs":[{"name":"","type":"uint256"}]},
  {"type":"function","name":"reserveHealthBps","stateMutability":"view","inputs":[],"outputs":[{"name":"","type":"uint256"}]},
  {"type":"function","name":"reserveRatioBps","stateMutability":"view","inputs":[],"outputs":[{"name":"","type":"uint16"}]},
  {"type":"function","name":"premiumBps","stateMutability":"view","inputs":[],"outputs":[{"name":"","type":"uint16"}]},
  {"type":"function","name":"salesPaused","stateMutability":"view","inputs":[],"outputs":[{"name":"","type":"bool"}]},
  {"type":"function","name":"quotePremium","stateMutability":"view","inputs":[{"name":"coverage","type":"uint256"}],"outputs":[{"name":"","type":"uint256"}]},
  {"type":"function","name":"policies","stateMutability":"view","inputs":[{"name":"","type":"uint256"}],"outputs":[
    {"name":"holder","type":"address"},{"name":"latE6","type":"int32"},{"name":"lonE6","type":"int32"},
    {"name":"coverage","type":"uint128"},{"name":"expiresAt","type":"uint64"},{"name":"active","type":"bool"}]},
  {"type":"function","name":"buyPolicy","stateMutability":"payable","inputs":[
    {"name":"latE6","type":"int32"},{"name":"lonE6","type":"int32"},{"name":"coverage","type":"uint128"}],
    "outputs":[{"name":"policyId","type":"uint256"}]},
  {"type":"function","name":"fund","stateMutability":"payable","inputs":[],"outputs":[]},
  {"type":"event","name":"PolicyPurchased","anonymous":false,"inputs":[
    {"indexed":true,"name":"policyId","type":"uint256"},{"indexed":true,"name":"holder","type":"address"},
    {"indexed":false,"name":"latE6","type":"int32"},{"indexed":false,"name":"lonE6","type":"int32"},
    {"indexed":false,"name":"coverage","type":"uint256"},{"indexed":false,"name":"premium","type":"uint256"}]},
  {"type":"event","name":"QuakeProcessed","anonymous":false,"inputs":[
    {"indexed":true,"name":"eventId","type":"bytes32"},{"indexed":false,"name":"magX100","type":"uint32"},
    {"indexed":false,"name":"latE6","type":"int32"},{"indexed":false,"name":"lonE6","type":"int32"},
    {"indexed":false,"name":"policiesPaid","type":"uint256"},{"indexed":false,"name":"totalPaid","type":"uint256"}]},
  {"type":"event","name":"PolicyPaid","anonymous":false,"inputs":[
    {"indexed":true,"name":"policyId","type":"uint256"},{"indexed":true,"name":"holder","type":"address"},
    {"indexed":true,"name":"eventId","type":"bytes32"},{"indexed":false,"name":"amount","type":"uint256"},
    {"indexed":false,"name":"tier","type":"uint8"}]}
]
''';

class PoolStats {
  final BigInt balanceWei, activeCoverageWei, policyCount, activePolicies, reserveHealthBps;
  final int reserveRatioBps, premiumBps;
  final bool salesPaused;
  PoolStats({
    required this.balanceWei,
    required this.activeCoverageWei,
    required this.policyCount,
    required this.activePolicies,
    required this.reserveHealthBps,
    required this.reserveRatioBps,
    required this.premiumBps,
    required this.salesPaused,
  });
}

class Policy {
  final int id;
  final String holder;
  final double lat, lon;
  final BigInt coverageWei;
  final DateTime expiresAt;
  final bool active;
  Policy(this.id, this.holder, this.lat, this.lon, this.coverageWei, this.expiresAt, this.active);
}

class QuakeEvent {
  final String eventId;
  final double mag, lat, lon;
  final int policiesPaid;
  final BigInt totalPaidWei;
  final String txHash;
  final int block;
  QuakeEvent(this.eventId, this.mag, this.lat, this.lon, this.policiesPaid, this.totalPaidWei, this.txHash, this.block);
}

class Payout {
  final int policyId;
  final String holder, eventId, txHash;
  final BigInt amountWei;
  final int tier, block;
  Payout(this.policyId, this.holder, this.eventId, this.amountWei, this.tier, this.txHash, this.block);
}

class FayPool {
  final Web3Client _client = Web3Client(FayConfig.rpcUrl, http.Client());
  late final DeployedContract _c = DeployedContract(
    ContractAbi.fromJson(_abiJson, 'FayPool'),
    EthereumAddress.fromHex(FayConfig.fayPoolAddress),
  );

  Future<List<dynamic>> _call(String fn, [List<dynamic> params = const []]) =>
      _client.call(contract: _c, function: _c.function(fn), params: params);

  Future<PoolStats> stats() async {
    final results = await Future.wait([
      _client.getBalance(_c.address),
      _call('totalActiveCoverage'),
      _call('policyCount'),
      _call('activePolicyCount'),
      _call('reserveHealthBps'),
      _call('reserveRatioBps'),
      _call('premiumBps'),
      _call('salesPaused'),
    ]);
    return PoolStats(
      balanceWei: (results[0] as EtherAmount).getInWei,
      activeCoverageWei: (results[1] as List).first as BigInt,
      policyCount: (results[2] as List).first as BigInt,
      activePolicies: (results[3] as List).first as BigInt,
      reserveHealthBps: (results[4] as List).first as BigInt,
      reserveRatioBps: ((results[5] as List).first as BigInt).toInt(),
      premiumBps: ((results[6] as List).first as BigInt).toInt(),
      salesPaused: (results[7] as List).first as bool,
    );
  }

  Future<BigInt> quotePremium(BigInt coverageWei) async => (await _call('quotePremium', [coverageWei])).first as BigInt;

  Future<Policy> policy(int id) async {
    final r = await _call('policies', [BigInt.from(id)]);
    return Policy(
      id,
      (r[0] as EthereumAddress).hexEip55.toLowerCase(),
      (r[1] as BigInt).toInt() / 1e6,
      (r[2] as BigInt).toInt() / 1e6,
      r[3] as BigInt,
      DateTime.fromMillisecondsSinceEpoch((r[4] as BigInt).toInt() * 1000),
      r[5] as bool,
    );
  }

  /// Bağlı adresin poliçeleri (MVP: tüm poliçeleri tarar; üretimde indeksleyici gerekir).
  Future<List<Policy>> policiesOf(String holder) async {
    final n = ((await _call('policyCount')).first as BigInt).toInt();
    final all = await Future.wait([for (var i = 1; i <= n; i++) policy(i)]);
    return all.where((p) => p.holder == holder.toLowerCase()).toList().reversed.toList();
  }

  /// buyPolicy çağrısının calldata'sı (MetaMask'a verilir).
  String buyPolicyCalldata({required double lat, required double lon, required BigInt coverageWei}) {
    final data = _c.function('buyPolicy').encodeCall([
      BigInt.from((lat * 1e6).round()),
      BigInt.from((lon * 1e6).round()),
      coverageWei,
    ]);
    return '0x${_hex(data)}';
  }

  Future<List<QuakeEvent>> quakeEvents() async {
    final ev = _c.event('QuakeProcessed');
    final logs = await _client.getLogs(FilterOptions.events(
      contract: _c,
      event: ev,
      fromBlock: const BlockNum.exact(FayConfig.deployBlock),
    ));
    return logs.map((l) {
      final d = ev.decodeResults(l.topics!, l.data!);
      // decodeResults indeksli alanları da sırayla döner: [eventId, magX100, latE6, lonE6, policiesPaid, totalPaid]
      return QuakeEvent(
        l.topics![1] ?? '',
        (d[1] as BigInt).toInt() / 100,
        (d[2] as BigInt).toInt() / 1e6,
        (d[3] as BigInt).toInt() / 1e6,
        (d[4] as BigInt).toInt(),
        d[5] as BigInt,
        l.transactionHash ?? '',
        l.blockNum ?? 0,
      );
    }).toList().reversed.toList();
  }

  Future<List<Payout>> payouts() async {
    final ev = _c.event('PolicyPaid');
    final logs = await _client.getLogs(FilterOptions.events(
      contract: _c,
      event: ev,
      fromBlock: const BlockNum.exact(FayConfig.deployBlock),
    ));
    return logs.map((l) {
      final d = ev.decodeResults(l.topics!, l.data!);
      return Payout(
        (d[0] as BigInt).toInt(),
        (d[1] as EthereumAddress).hexEip55.toLowerCase(),
        l.topics![3] ?? '',
        d[3] as BigInt,
        (d[4] as BigInt).toInt(),
        l.transactionHash ?? '',
        l.blockNum ?? 0,
      );
    }).toList().reversed.toList();
  }

  static String _hex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}

String fmtEth(BigInt wei, {int decimals = 4}) {
  final s = EtherAmount.inWei(wei).getValueInUnit(EtherUnit.ether);
  return '${s.toStringAsFixed(decimals)} ETH';
}

String shortAddr(String a) => a.length > 10 ? '${a.substring(0, 6)}…${a.substring(a.length - 4)}' : a;
