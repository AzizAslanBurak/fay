/// Zincir ayarları. deployments/sepolia.json ile aynı tutulur (scripts/deploy.ts günceller).
class FayConfig {
  static const String rpcUrl = 'https://ethereum-sepolia-rpc.publicnode.com';
  static const int chainId = 11155111; // Sepolia
  static const String chainIdHex = '0xaa36a7';
  static const String fayPoolAddress = '0x280983aa19c44cb3a925a1b1ad84b5eae8a48bee';
  static const String explorer = 'https://sepolia.etherscan.io';

  /// Olayları taramaya başlanacak blok (deploy bloğu civarı; tüm zinciri taramamak için).
  static const int deployBlock = 11827117;
}
