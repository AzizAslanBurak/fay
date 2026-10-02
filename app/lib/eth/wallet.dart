// MetaMask / EIP-1193 cüzdan köprüsü (Flutter Web). Ek paket yok: doğrudan window.ethereum.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../config.dart';

extension type _Eip1193(JSObject _) implements JSObject {
  external JSPromise<JSAny?> request(JSObject args);
  external void on(JSString event, JSFunction handler);
}

class Wallet extends ChangeNotifier {
  String? address;
  int? chainId;
  String? error;

  bool get available => _provider != null;
  bool get connected => address != null;
  bool get onSepolia => chainId == FayConfig.chainId;

  _Eip1193? get _provider {
    final p = web.window.getProperty<JSAny?>('ethereum'.toJS);
    if (p == null || p.isUndefinedOrNull) return null;
    return _Eip1193(p as JSObject);
  }

  Future<JSAny?> _req(String method, [List<Object?> params = const []]) async {
    final p = _provider;
    if (p == null) throw StateError('no_wallet');
    final args = {'method': method, 'params': params}.jsify() as JSObject;
    return await p.request(args).toDart;
  }

  Future<void> connect() async {
    error = null;
    try {
      final accounts = (await _req('eth_requestAccounts')).dartify() as List?;
      address = accounts != null && accounts.isNotEmpty ? (accounts.first as String).toLowerCase() : null;
      final cid = (await _req('eth_chainId')).dartify() as String?;
      chainId = cid == null ? null : int.parse(cid.substring(2), radix: 16);
      _listen();
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  Future<void> switchToSepolia() async {
    try {
      await _req('wallet_switchEthereumChain', [
        {'chainId': FayConfig.chainIdHex}
      ]);
    } catch (_) {
      // Ağ cüzdanda tanımlı değilse ekle
      await _req('wallet_addEthereumChain', [
        {
          'chainId': FayConfig.chainIdHex,
          'chainName': 'Sepolia',
          'nativeCurrency': {'name': 'Sepolia ETH', 'symbol': 'ETH', 'decimals': 18},
          'rpcUrls': [FayConfig.rpcUrl],
          'blockExplorerUrls': [FayConfig.explorer],
        }
      ]);
    }
    final cid = (await _req('eth_chainId')).dartify() as String?;
    chainId = cid == null ? null : int.parse(cid.substring(2), radix: 16);
    notifyListeners();
  }

  /// Ham işlem gönderir; data hex (0x…), value wei. Tx hash döner.
  Future<String> sendTransaction({required String to, required String dataHex, BigInt? value}) async {
    if (address == null) throw StateError('not_connected');
    final tx = <String, Object?>{
      'from': address,
      'to': to,
      'data': dataHex,
      if (value != null && value > BigInt.zero) 'value': '0x${value.toRadixString(16)}',
    };
    final hash = (await _req('eth_sendTransaction', [tx])).dartify() as String;
    return hash;
  }

  bool _listening = false;
  void _listen() {
    if (_listening) return;
    final p = _provider;
    if (p == null) return;
    _listening = true;
    p.on(
      'accountsChanged'.toJS,
      ((JSAny? accs) {
        final list = accs.dartify() as List?;
        address = list != null && list.isNotEmpty ? (list.first as String).toLowerCase() : null;
        notifyListeners();
      }).toJS,
    );
    p.on(
      'chainChanged'.toJS,
      ((JSAny? cid) {
        final s = cid.dartify() as String?;
        chainId = s == null ? null : int.parse(s.substring(2), radix: 16);
        notifyListeners();
      }).toJS,
    );
  }
}
