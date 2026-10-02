/// Zincir ayarları. deployments/sepolia.json ile aynı tutulur (scripts/deploy.ts günceller).
class FayConfig {
  static const String rpcUrl = 'https://ethereum-sepolia-rpc.publicnode.com';
  static const int chainId = 11155111; // Sepolia
  static const String chainIdHex = '0xaa36a7';
  static const String fayPoolAddress = '0x2ecd376ed2a1f71523a85aa7e37df0d9e8e901ca';
  static const String explorer = 'https://sepolia.etherscan.io';

  /// Olayları taramaya başlanacak blok (deploy bloğu civarı; tüm zinciri taramamak için).
  static const int deployBlock = 11830567;
}
