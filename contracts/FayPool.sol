// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReceiverTemplate} from "./ReceiverTemplate.sol";

/// @title FayPool – Deprem için parametrik sigorta havuzu (Chainlink CRE tüketicisi)
/// @notice Poliçe satar, sermaye toplar; CRE'den gelen imzalı deprem raporuna göre
///         poliçe sahiplerine OTOMATİK ödeme yapar. Hasar tespiti yoktur.
/// @dev Prototip. Para birimi: zincirin yerel token'ı (Sepolia ETH). Üretimde stablecoin + ACE + sayfalama gerekir.
contract FayPool is ReceiverTemplate {
  // ------------------------------------------------------------------ Tipler
  struct Policy {
    address holder;
    int32 latE6; // enlem × 1e6
    int32 lonE6; // boylam × 1e6
    uint128 coverage; // teminat (wei)
    uint64 expiresAt;
    bool active;
  }

  /// @dev Tek onReport kapısından iki tür rapor geçer: abi.encode(uint8 kind, bytes payload)
  uint8 public constant KIND_QUAKE = 1;
  uint8 public constant KIND_GUARDIAN = 2;

  /// @dev pool-guardian/main.ts ile BİREBİR aynı sıra.
  struct GuardianReport {
    uint64 observedAt; // CRE'nin okuma zamanı (unix s)
    uint256 healthBps; // kasa / (aktif teminat × rezerv oranı), 1e4 = %100
    bool pause; // true → satışları durdur, false → aç
  }

  /// @dev quake-oracle/main.ts içindeki encodeAbiParameters sırasıyla BİREBİR aynı olmalı.
  struct QuakeReport {
    bytes32 eventId;
    uint64 eventTime;
    int32 latE6;
    int32 lonE6;
    uint32 magX100;
    uint32 depthKmX10;
    uint32 fullRadiusKmX10; // ≤ bu mesafe → %100
    uint32 halfRadiusKmX10; // ≤ bu mesafe → %50
    uint32 cosLatE6; // cos(episantr enlemi) × 1e6
    uint8 sourcesAgreed;
  }

  // ------------------------------------------------------------------ Durum
  uint256 public policyCount;
  mapping(uint256 => Policy) public policies;
  mapping(bytes32 => bool) public processedEvents;

  uint256 public totalActiveCoverage; // aktif poliçelerin toplam teminatı
  uint16 public premiumBps = 500; // teminatın %5'i prim
  uint16 public reserveRatioBps = 2000; // aktif teminatın en az %20'si kasada olmalı
  uint64 public policyDuration = 365 days;
  uint32 public minMagX100 = 550; // M5.5
  uint8 public minSources = 2;
  bool public salesPaused; // devre kesici (CRE pool-guardian veya owner)
  uint64 public lastGuardianAt; // bekçinin son raporu
  uint256 public lastGuardianHealthBps;

  uint256 private constant KM_PER_DEG_E6 = 111_320; // 1° ≈ 111.32 km → metre/1e6 derece

  // ------------------------------------------------------------------ Olaylar
  event Funded(address indexed from, uint256 amount);
  event PolicyPurchased(uint256 indexed policyId, address indexed holder, int32 latE6, int32 lonE6, uint256 coverage, uint256 premium);
  event QuakeProcessed(bytes32 indexed eventId, uint32 magX100, int32 latE6, int32 lonE6, uint256 policiesPaid, uint256 totalPaid);
  event PolicyPaid(uint256 indexed policyId, address indexed holder, bytes32 indexed eventId, uint256 amount, uint8 tier);
  event SalesPausedSet(bool paused);
  event GuardianReported(uint64 observedAt, uint256 healthBps, bool paused);

  error SalesPaused();
  error InsufficientReserve(uint256 required, uint256 available);
  error WrongPremium(uint256 expected, uint256 sent);
  error InvalidCoverage();
  error EventAlreadyProcessed(bytes32 eventId);
  error ReportRejected(string reason);

  constructor(address forwarder) ReceiverTemplate(forwarder) {}

  // ------------------------------------------------------------------ Sermaye
  receive() external payable {
    emit Funded(msg.sender, msg.value);
  }

  function fund() external payable {
    emit Funded(msg.sender, msg.value);
  }

  // ------------------------------------------------------------------ Poliçe
  function quotePremium(uint256 coverage) public view returns (uint256) {
    return (coverage * premiumBps) / 10_000;
  }

  /// @notice Poliçe satın al. msg.value tam olarak quotePremium(coverage) olmalı.
  function buyPolicy(int32 latE6, int32 lonE6, uint128 coverage) external payable returns (uint256 policyId) {
    if (salesPaused) revert SalesPaused();
    if (coverage == 0) revert InvalidCoverage();
    uint256 premium = quotePremium(coverage);
    if (msg.value != premium) revert WrongPremium(premium, msg.value);

    // Ödeme gücü kontrolü: (aktif teminat + yeni) × rezerv oranı ≤ kasa
    uint256 required = ((totalActiveCoverage + coverage) * reserveRatioBps) / 10_000;
    if (address(this).balance < required) revert InsufficientReserve(required, address(this).balance);

    policyId = ++policyCount;
    policies[policyId] = Policy({
      holder: msg.sender,
      latE6: latE6,
      lonE6: lonE6,
      coverage: coverage,
      expiresAt: uint64(block.timestamp) + policyDuration,
      active: true
    });
    totalActiveCoverage += coverage;
    emit PolicyPurchased(policyId, msg.sender, latE6, lonE6, coverage, premium);
  }

  function activePolicyCount() external view returns (uint256 n) {
    for (uint256 i = 1; i <= policyCount; i++) {
      if (policies[i].active && policies[i].expiresAt > block.timestamp) n++;
    }
  }

  /// @notice Havuz sağlığı: kasa / (aktif teminat × rezerv oranı), 1e4 = %100
  function reserveHealthBps() external view returns (uint256) {
    uint256 required = (totalActiveCoverage * reserveRatioBps) / 10_000;
    if (required == 0) return type(uint256).max;
    return (address(this).balance * 10_000) / required;
  }

  // ------------------------------------------------------------------ CRE raporu
  function _processReport(bytes calldata report) internal override {
    (uint8 kind, bytes memory payload) = abi.decode(report, (uint8, bytes));
    if (kind == KIND_QUAKE) {
      _processQuake(abi.decode(payload, (QuakeReport)));
    } else if (kind == KIND_GUARDIAN) {
      _processGuardian(abi.decode(payload, (GuardianReport)));
    } else {
      revert ReportRejected("unknown report kind");
    }
  }

  /// @dev CRE pool-guardian: ödeme gücü düşükse satışları durdur, düzelince aç. Eski raporu yok say.
  function _processGuardian(GuardianReport memory g) internal {
    if (g.observedAt <= lastGuardianAt) revert ReportRejected("stale guardian report");
    lastGuardianAt = g.observedAt;
    lastGuardianHealthBps = g.healthBps;
    if (salesPaused != g.pause) {
      salesPaused = g.pause;
      emit SalesPausedSet(g.pause);
    }
    emit GuardianReported(g.observedAt, g.healthBps, g.pause);
  }

  function _processQuake(QuakeReport memory q) internal {

    if (processedEvents[q.eventId]) revert EventAlreadyProcessed(q.eventId);
    if (q.sourcesAgreed < minSources) revert ReportRejected("insufficient sources");
    if (q.magX100 < minMagX100) revert ReportRejected("below magnitude threshold");
    if (q.halfRadiusKmX10 < q.fullRadiusKmX10) revert ReportRejected("bad radii");
    processedEvents[q.eventId] = true;

    uint256 paidCount;
    uint256 paidTotal;
    for (uint256 i = 1; i <= policyCount; i++) {
      Policy storage p = policies[i];
      if (!p.active || p.expiresAt <= block.timestamp) continue;

      uint8 tier = _payoutTier(p, q);
      if (tier == 0) continue;

      uint256 amount = tier == 1 ? p.coverage : p.coverage / 2;
      if (amount > address(this).balance) amount = address(this).balance; // kasa biterse kalanı öde

      p.active = false;
      totalActiveCoverage -= p.coverage;
      paidCount++;
      paidTotal += amount;

      (bool ok, ) = p.holder.call{value: amount}("");
      // ödeme başarısız olursa (ör. kontrat cüzdan) poliçeyi düşürmeyelim ki tekrar denenebilsin
      if (!ok) {
        p.active = true;
        totalActiveCoverage += p.coverage;
        paidCount--;
        paidTotal -= amount;
        continue;
      }
      emit PolicyPaid(i, p.holder, q.eventId, amount, tier);
    }

    emit QuakeProcessed(q.eventId, q.magX100, q.latE6, q.lonE6, paidCount, paidTotal);
  }

  /// @return tier 0 = ödeme yok, 1 = %100, 2 = %50
  function _payoutTier(Policy storage p, QuakeReport memory q) internal view returns (uint8 tier) {
    uint256 d2 = _distanceSquaredMeters(p.latE6, p.lonE6, q);
    uint256 full = uint256(q.fullRadiusKmX10) * 100; // km×10 → metre
    uint256 half = uint256(q.halfRadiusKmX10) * 100;
    if (d2 <= full * full) return 1;
    if (d2 <= half * half) return 2;
    return 0;
  }

  /// @dev Hiposantr mesafesinin karesi (m²). Equirectangular yaklaşım; cos(lat) raporla gelir.
  function _distanceSquaredMeters(int32 latE6, int32 lonE6, QuakeReport memory q) internal pure returns (uint256) {
    uint256 dLatE6 = _absDiff(latE6, q.latE6);
    uint256 dLonE6 = _absDiff(lonE6, q.lonE6);
    uint256 latM = (dLatE6 * KM_PER_DEG_E6) / 1e6;
    uint256 lonM = (((dLonE6 * KM_PER_DEG_E6) / 1e6) * q.cosLatE6) / 1e6;
    uint256 depthM = uint256(q.depthKmX10) * 100;
    return latM * latM + lonM * lonM + depthM * depthM;
  }

  function _absDiff(int32 a, int32 b) internal pure returns (uint256) {
    int256 d = int256(a) - int256(b);
    return uint256(d < 0 ? -d : d);
  }

  /// @notice Flutter/test için: bir poliçe şu raporla hangi kademeden ödeme alırdı?
  function previewTier(uint256 policyId, QuakeReport calldata q) external view returns (uint8) {
    return _payoutTier(policies[policyId], q);
  }

  // ------------------------------------------------------------------ Yönetim
  function setSalesPaused(bool paused) external onlyOwner {
    salesPaused = paused;
    emit SalesPausedSet(paused);
  }

  function setParams(uint16 _premiumBps, uint16 _reserveRatioBps, uint64 _policyDuration, uint32 _minMagX100, uint8 _minSources)
    external
    onlyOwner
  {
    premiumBps = _premiumBps;
    reserveRatioBps = _reserveRatioBps;
    policyDuration = _policyDuration;
    minMagX100 = _minMagX100;
    minSources = _minSources;
  }
}
