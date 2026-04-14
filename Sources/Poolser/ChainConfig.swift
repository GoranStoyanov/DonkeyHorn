import Foundation

struct SupportedChain: Identifiable, Hashable {
    let id: String
    let displayName: String
    let chainId: Int
    let infuraHost: String
    let coingeckoPlatformID: String
    let defiLlamaChainKey: String
    let v3Factory: String
    let v3NFPM: String
    let wrappedNativeToken: String
    let v4PM: String?
    let v4SV: String?
    let v4DeployBlockHex: String?

    var supportsV4: Bool {
        v4PM != nil && v4SV != nil && v4DeployBlockHex != nil
    }

    var infuraRPCURLTemplate: String {
        "https://\(infuraHost).infura.io/v3/<YOUR-API-KEY>"
    }

    static let all: [SupportedChain] = [
        SupportedChain(
            id: "ethereum",
            displayName: "Ethereum",
            chainId: 1,
            infuraHost: "mainnet",
            coingeckoPlatformID: "ethereum",
            defiLlamaChainKey: "ethereum",
            v3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
            v3NFPM: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
            wrappedNativeToken: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
            v4PM: "0xbd216513d74c8cf14cf4747e6aaa6420ff64ee9e",
            v4SV: "0x7ffe42c4a5deea5b0fec41c94c136cf115597227",
            v4DeployBlockHex: "0x14A0000"
        ),
        SupportedChain(
            id: "base",
            displayName: "Base",
            chainId: 8453,
            infuraHost: "base-mainnet",
            coingeckoPlatformID: "base",
            defiLlamaChainKey: "base",
            v3Factory: "0x33128a8fC17869897dcE68Ed026d694621f6FDfD",
            v3NFPM: "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1",
            wrappedNativeToken: "0x4200000000000000000000000000000000000006",
            v4PM: "0x7c5f5a4bbd8fd63184577525326123b519429bdc",
            v4SV: "0xa3c0c9b65bad0b08107aa264b0f3db444b867a71",
            v4DeployBlockHex: nil
        ),
        SupportedChain(
            id: "arbitrum",
            displayName: "Arbitrum",
            chainId: 42161,
            infuraHost: "arbitrum-mainnet",
            coingeckoPlatformID: "arbitrum-one",
            defiLlamaChainKey: "arbitrum",
            v3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
            v3NFPM: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
            wrappedNativeToken: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
            v4PM: "0xd88f38f930b7952f2db2432cb002e7abbf3dd869",
            v4SV: "0x76fd297e2d437cd7f76d50f01afe6160f86e9990",
            v4DeployBlockHex: nil
        ),
        SupportedChain(
            id: "optimism",
            displayName: "Optimism",
            chainId: 10,
            infuraHost: "optimism-mainnet",
            coingeckoPlatformID: "optimistic-ethereum",
            defiLlamaChainKey: "optimism",
            v3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
            v3NFPM: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
            wrappedNativeToken: "0x4200000000000000000000000000000000000006",
            v4PM: "0x3c3ea4b57a46241e54610e5f022e5c45859a1017",
            v4SV: "0xc18a3169788f4f75a170290584eca6395c75ecdb",
            v4DeployBlockHex: nil
        ),
        SupportedChain(
            id: "polygon",
            displayName: "Polygon",
            chainId: 137,
            infuraHost: "polygon-mainnet",
            coingeckoPlatformID: "polygon-pos",
            defiLlamaChainKey: "polygon",
            v3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
            v3NFPM: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
            wrappedNativeToken: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
            v4PM: "0x1ec2ebf4f37e7363fdfe3551602425af0b3ceef9",
            v4SV: "0x5ea1bd7974c8a611cbab0bdcafcb1d9cc9b3ba5a",
            v4DeployBlockHex: nil
        )
    ]

    static func byID(_ id: String) -> SupportedChain? {
        all.first(where: { $0.id == id })
    }
}
