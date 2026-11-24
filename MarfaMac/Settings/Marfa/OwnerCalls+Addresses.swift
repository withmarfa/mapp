import Foundation
import Marfa
import MarfaAPI

extension ClientOwnerCalls {
    // MARK: Addresses

    private static func settings(_ config: Components.Schemas.InstanceConfig) -> AddressSettings {
        let addresses = config.addresses ?? []
        return AddressSettings(
            instanceID: config.instanceId, signIn: config.signInAddress ?? addresses.first ?? "", addresses: addresses,
            websites: config.corsOrigins ?? [])
    }

    func addresses() async throws(OwnerFailure) -> AddressSettings {
        try await run { client in Self.settings(try await client.getConfig().ok.body.json) }
    }

    func check(signIn: String?, addresses: [String]?) async throws(OwnerFailure) -> AddressPlan {
        try await run { client in
            let answer = try await client.check(
                AddressChange(signInAddress: signIn.map { .set($0) }, addresses: addresses.map { .set($0) })
            ).answer
            let reach: AddressPlan.Reach =
                switch answer.signInAddressCheck?.passed {
                case true?: .answers
                case false?: .notAnswering(reason: answer.signInAddressCheck?.reason?.rawValue)
                case nil: signIn == nil ? .notAsked : .notChecked
                }
            return AddressPlan(
                askedSignIn: signIn, askedAddresses: addresses, signIn: answer.signInAddress, addresses: answer.addresses,
                requiresConfirmation: answer.requiresConfirmation,
                consequences: answer.consequences.map { .init(code: $0.code.rawValue, sentence: $0.sentence, count: $0.count) },
                reach: reach)
        }
    }

    func apply(_ plan: AddressPlan, instanceID: String?) async throws(OwnerFailure) -> AddressSettings {
        try await run(plainConflict: Self.configConflict) { client in
            let body = Operations.UpdateConfig.Input.Body.JsonPayload(
                addresses: plan.askedAddresses.map { .value($0) }, signInAddress: plan.askedSignIn.map { .value($0) },
                confirmSignInAddressChange: plan.requiresConfirmation ? true : nil)
            return Self.settings(
                try await client.updateConfig(headers: .init(xMarfaInstanceId: instanceID), body: .json(body)).ok.body.json)
        }
    }

    func setWebsites(_ websites: [String], instanceID: String?) async throws(OwnerFailure) -> AddressSettings {
        try await run(plainConflict: Self.configConflict) { client in
            let body = Operations.UpdateConfig.Input.Body.JsonPayload(corsOrigins: .value(websites))
            return Self.settings(
                try await client.updateConfig(headers: .init(xMarfaInstanceId: instanceID), body: .json(body)).ok.body.json)
        }
    }
}
