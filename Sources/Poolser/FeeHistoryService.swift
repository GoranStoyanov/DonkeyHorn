import Foundation

private struct FeeHistoryCache: Codable {
    /// Top of the next historical chunk to scan (going backward). nil = fully bootstrapped.
    var nextScanCeiling: Int?
    /// Highest block already scanned — used to pick up new blocks each refresh.
    var lastSeenBlock: Int
    var fees: [String: PositionFees]
    /// Earliest IncreaseLiquidity block found per tokenId — used to bound backward scan.
    var knownMintBlocks: [String: Int]

    struct PositionFees: Codable {
        var amount0: Double
        var amount1: Double
    }

    // Custom decode so old caches without knownMintBlocks don't fail.
    init(nextScanCeiling: Int?, lastSeenBlock: Int, fees: [String: PositionFees], knownMintBlocks: [String: Int] = [:]) {
        self.nextScanCeiling = nextScanCeiling
        self.lastSeenBlock = lastSeenBlock
        self.fees = fees
        self.knownMintBlocks = knownMintBlocks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nextScanCeiling = try c.decodeIfPresent(Int.self, forKey: .nextScanCeiling)
        lastSeenBlock = try c.decode(Int.self, forKey: .lastSeenBlock)
        fees = try c.decode([String: PositionFees].self, forKey: .fees)
        knownMintBlocks = (try? c.decode([String: Int].self, forKey: .knownMintBlocks)) ?? [:]
    }
}

// keccak256("Collect(uint256,address,uint256,uint256)") — verified from on-chain events
private let collectEventTopic = "0x40d0efd1a53d60ecbf40971b9daf7dc90178c3aadc7aab1765632738fa8b8f01"
// keccak256("IncreaseLiquidity(uint256,uint128,uint256,uint256)") — verified known value
private let increaseLiquidityTopic = "0x3067048beee31b25b2f1681f88dac838c8bba36af25bfb2b7cf7473a5847e35f"

private let tokenIdBatchSize = 50

struct FeeHistoryService {

    struct Result {
        var fees: [String: (amount0: Double, amount1: Double)]
        var bootstrapInProgress: Bool
    }

    static func scan(
        positions: [Position],
        nfpm: String,
        deployBlock: Int,
        currentBlock: Int,
        eth: EthereumClient,
        chainID: String,
        wallet: String
    ) async -> Result {
        guard !positions.isEmpty else {
            return Result(fees: [:], bootstrapInProgress: false)
        }

        let cacheKey = "v3FeeHistory.\(chainID).\(wallet.lowercased())"
        var cache: FeeHistoryCache = loadCache(forKey: cacheKey)
            ?? FeeHistoryCache(nextScanCeiling: currentBlock, lastSeenBlock: currentBlock, fees: [:])

        let chunkSize = AppSettings.shared.v4LogChunkSize
        let baseMaxChunks = AppSettings.shared.v4BootstrapMaxChunksPerRefresh
        // Scale maxChunks so each refresh covers roughly the same calendar time on all chains.
        // Capped at 10× to avoid excessive RPC calls on very fast chains (Arbitrum, MegaETH).
        let blockTimeFactor = max(1, Int((12.0 / (SupportedChain.byID(chainID)?.blockTimeSeconds ?? 12)).rounded()))
        let maxChunks = baseMaxChunks * min(blockTimeFactor, 10)

        let decMap: [String: (dec0: Int, dec1: Int)] = Dictionary(
            uniqueKeysWithValues: positions.map { ($0.tokenId, ($0.dec0, $0.dec1)) }
        )
        let tokenIds = positions.map(\.tokenId)

        // 1. Fresh scan: always pick up new blocks since last refresh.
        if currentBlock > cache.lastSeenBlock {
            await scanRange(
                from: cache.lastSeenBlock + 1,
                to: currentBlock,
                chunkSize: chunkSize,
                maxChunks: maxChunks,
                nfpm: nfpm,
                tokenIds: tokenIds,
                decMap: decMap,
                eth: eth,
                chainID: chainID,
                cache: &cache
            )
            cache.lastSeenBlock = currentBlock
        }

        // 2. Historical bootstrap: scan backward from nextScanCeiling.
        // Stop at the earliest known position creation block rather than deployBlock,
        // so we don't scan blocks that predate the wallet.
        var bootstrapInProgress = false
        let lowerBound = effectiveLowerBound(cache: cache, tokenIds: tokenIds, deployBlock: deployBlock)
        if let ceiling = cache.nextScanCeiling, ceiling >= lowerBound {
            let scanFrom = max(ceiling - chunkSize * maxChunks + 1, lowerBound)
            await scanRange(
                from: scanFrom,
                to: ceiling,
                chunkSize: chunkSize,
                maxChunks: maxChunks,
                nfpm: nfpm,
                tokenIds: tokenIds,
                decMap: decMap,
                eth: eth,
                chainID: chainID,
                cache: &cache
            )
            // Recompute after scan — knownMintBlocks may have been updated.
            let newLower = effectiveLowerBound(cache: cache, tokenIds: tokenIds, deployBlock: deployBlock)
            cache.nextScanCeiling = scanFrom > newLower ? scanFrom - 1 : nil
            bootstrapInProgress = cache.nextScanCeiling != nil
        }

        saveCache(cache, forKey: cacheKey)
        return Result(fees: feeDict(from: cache), bootstrapInProgress: bootstrapInProgress)
    }

    // MARK: - Private

    /// Returns the block we can safely stop scanning at.
    /// Once we know when every tracked position was created, we stop at the earliest
    /// creation block — no Collect event can exist before a position's mint.
    private static func effectiveLowerBound(
        cache: FeeHistoryCache,
        tokenIds: [String],
        deployBlock: Int
    ) -> Int {
        guard !tokenIds.isEmpty,
              tokenIds.allSatisfy({ cache.knownMintBlocks[$0] != nil }),
              let earliest = tokenIds.compactMap({ cache.knownMintBlocks[$0] }).min()
        else { return deployBlock }
        return max(deployBlock, earliest)
    }

    private static func scanRange(
        from: Int,
        to: Int,
        chunkSize: Int,
        maxChunks: Int,
        nfpm: String,
        tokenIds: [String],
        decMap: [String: (dec0: Int, dec1: Int)],
        eth: EthereumClient,
        chainID: String,
        cache: inout FeeHistoryCache
    ) async {
        guard from <= to else { return }
        var chunk = from
        var chunksScanned = 0
        while chunk <= to && chunksScanned < maxChunks {
            let chunkEnd = min(chunk + chunkSize - 1, to)
            let fromHex = "0x" + String(chunk, radix: 16)
            let toHex   = "0x" + String(chunkEnd, radix: 16)

            for batchStart in stride(from: 0, to: tokenIds.count, by: tokenIdBatchSize) {
                let batch = Array(tokenIds[batchStart..<min(batchStart + tokenIdBatchSize, tokenIds.count)])
                let tokenTopics = batch.map { "0x" + String(format: "%064x", UInt64($0) ?? 0) }
                do {
                    let logs = try await eth.ethGetLogsOR(
                        address: nfpm,
                        topics: [[collectEventTopic, increaseLiquidityTopic], tokenTopics],
                        fromBlock: fromHex,
                        toBlock: toHex,
                        context: "feeHist[\(chainID)]"
                    )
                    parseLogs(logs, decMap: decMap, into: &cache)
                } catch {
                    Task { @MainActor in
                        LogStore.shared.log("feeHistory[\(chainID)]: \(error.localizedDescription)", level: .error)
                    }
                }
            }
            chunk = chunkEnd + 1
            chunksScanned += 1
        }
    }

    private static func parseLogs(
        _ logs: [[String: Any]],
        decMap: [String: (dec0: Int, dec1: Int)],
        into cache: inout FeeHistoryCache
    ) {
        for entry in logs {
            guard let topics = entry["topics"] as? [String], topics.count >= 2 else { continue }
            let tidHex = topics[1]
            let clean = tidHex.hasPrefix("0x") ? String(tidHex.dropFirst(2)) : tidHex
            guard let tokenIdVal = UInt64(clean, radix: 16) else { continue }
            let tokenIdStr = String(tokenIdVal)
            guard decMap[tokenIdStr] != nil else { continue }

            let topic0 = topics[0]

            if topic0 == increaseLiquidityTopic {
                // Track the earliest block we've seen this position exist.
                if let blockHex = entry["blockNumber"] as? String,
                   let blockNum = Int(blockHex.hasPrefix("0x") ? String(blockHex.dropFirst(2)) : blockHex, radix: 16) {
                    let prev = cache.knownMintBlocks[tokenIdStr] ?? Int.max
                    cache.knownMintBlocks[tokenIdStr] = min(prev, blockNum)
                }
                continue
            }

            guard topic0 == collectEventTopic else { continue }
            guard let decs = decMap[tokenIdStr] else { continue }
            let dataHex = entry["data"] as? String ?? ""
            guard let logData = Data(hexString: dataHex), logData.count >= 96 else { continue }
            // Collect data: recipient (32B) | amount0 (32B) | amount1 (32B)
            let a0 = logData.readAmount(wordAt: 32, decimals: decs.dec0)
            let a1 = logData.readAmount(wordAt: 64, decimals: decs.dec1)
            var existing = cache.fees[tokenIdStr] ?? FeeHistoryCache.PositionFees(amount0: 0, amount1: 0)
            existing.amount0 += a0
            existing.amount1 += a1
            cache.fees[tokenIdStr] = existing
        }
    }

    private static func loadCache(forKey key: String) -> FeeHistoryCache? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FeeHistoryCache.self, from: data)
    }

    private static func saveCache(_ cache: FeeHistoryCache, forKey key: String) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func feeDict(from cache: FeeHistoryCache) -> [String: (amount0: Double, amount1: Double)] {
        cache.fees.mapValues { ($0.amount0, $0.amount1) }
    }

    /// Clears ALL cached fee history (call when scan logic changes to force a fresh scan).
    static func clearAllCaches() {
        let ud = UserDefaults.standard
        for key in ud.dictionaryRepresentation().keys where key.hasPrefix("v3FeeHistory.") {
            ud.removeObject(forKey: key)
        }
    }

    /// Clears cached fee history for a wallet across all chains (call on wallet change).
    static func clearCache(wallet: String) {
        let prefix = "v3FeeHistory."
        let suffix = ".\(wallet.lowercased())"
        let ud = UserDefaults.standard
        for key in ud.dictionaryRepresentation().keys where key.hasPrefix(prefix) && key.hasSuffix(suffix) {
            ud.removeObject(forKey: key)
        }
    }
}
