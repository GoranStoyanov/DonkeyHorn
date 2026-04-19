import Foundation

/// Fetches all-time collected fees for Uniswap v3 positions from The Graph.
final class SubgraphService {
    private let gatewayBase = "https://gateway.thegraph.com/api"

    /// Returns a map of tokenId → (collectedFees0, collectedFees1) for the given positions.
    /// Uses The Graph decentralized network with the provided API key.
    func fetchCollectedFees(
        tokenIds: [String],
        subgraphID: String,
        apiKey: String
    ) async -> [String: (Double, Double)] {
        guard !tokenIds.isEmpty, !subgraphID.isEmpty, !apiKey.isEmpty else { return [:] }

        let idList = tokenIds.map { "\"\($0)\"" }.joined(separator: ",")
        let query = """
        {
          positions(where: {id_in: [\(idList)]}, first: \(min(tokenIds.count, 1000))) {
            id
            collectedFeesToken0
            collectedFeesToken1
          }
        }
        """
        let urlStr = "\(gatewayBase)/\(apiKey)/subgraphs/id/\(subgraphID)"
        guard let url = URL(string: urlStr) else { return [:] }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? JSONSerialization.data(withJSONObject: ["query": query]) else { return [:] }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [:] }
            return parse(data: data)
        } catch {
            return [:]
        }
    }

    private func parse(data: Data) -> [String: (Double, Double)] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj = json["data"] as? [String: Any],
            let positions = dataObj["positions"] as? [[String: Any]]
        else { return [:] }

        var result: [String: (Double, Double)] = [:]
        for pos in positions {
            guard
                let id = pos["id"] as? String,
                let f0 = toDouble(pos["collectedFeesToken0"]),
                let f1 = toDouble(pos["collectedFeesToken1"])
            else { continue }
            result[id] = (f0, f1)
        }
        return result
    }

    private func toDouble(_ value: Any?) -> Double? {
        switch value {
        case let s as String: return Double(s)
        case let d as Double: return d
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }
}
