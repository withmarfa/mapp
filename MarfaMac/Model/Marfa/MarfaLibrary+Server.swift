import Foundation

/// What only the server holds or names (sources, type icons and fields, the bin's retention), which the library keeps
/// the last answer of, and the catalogue the copy read with the person's choices on it.
extension MarfaLibrary {
    /// Asks the server for the names and the counts. An ask that fails keeps the earlier answer for that part.
    func refreshSources() async {
        guard let sourceNames else { return }
        sourceTurn += 1
        let turn = sourceTurn
        async let named = try? await sourceNames.sources()
        async let counted = try? await sourceNames.counts()
        let (names, counts) = await (named, counted)
        if let names, turn > appliedNamesTurn {
            appliedNamesTurn = turn
            sources.infos = Dictionary(names.map { ($0.code, $0) }, uniquingKeysWith: { $1 })
        }
        if let counts, turn > appliedCountsTurn {
            appliedCountsTurn = turn
            sources.counts = counts
        }
    }

    func readConnectors() async {
        guard connectors == nil, !isReadingConnectors, let sourceNames else { return }
        isReadingConnectors = true
        defer { isReadingConnectors = false }
        connectors = try? await sourceNames.connectors()
    }

    func updateSource(_ code: String, name: SourceFieldChange?, mark: SourceFieldChange?) async -> SourceEditFailure? {
        guard let sourceNames else { return .unsupported }
        do {
            let changed = try await sourceNames.update(code, name: name, mark: mark)
            sourceTurn += 1
            appliedNamesTurn = sourceTurn
            sources = sources.updating(changed)
            return nil
        } catch {
            return error
        }
    }

    func setIcon(_ icon: String?, ofType type: TypeID) async -> TypeIconFailure? {
        guard let typeIcons else { return .unsupported }
        do {
            let shown = try await typeIcons.setIcon(icon, ofType: type)
            chosenIcons[type] = (shown, readCatalogue.itemTypes[type]?.icon)
            catalogue = catalogue.choosingIcon(shown, ofType: type)
            reindex()
            return nil
        } catch {
            return error
        }
    }

    func editField(_ plan: FieldEditPlan) async -> TypeSchemaFailure? {
        guard let typeSchemas else { return .unsupported }
        do {
            try await typeSchemas.apply(plan)
            chosenFields.append((plan, readCatalogue.itemTypes[plan.type]))
            catalogue = catalogue.applying(plan)
            reindex()
            return nil
        } catch {
            return error
        }
    }

    /// The catalogue the copy read, with the icons the person has chosen since. A choice ends once the copy shows the
    /// type with a different icon than it did at the choice, whether the chosen one or one another app set.
    func holdingChosenIcons(_ read: Catalogue) -> Catalogue {
        readCatalogue = read
        var held = read
        chosenFields.removeAll { $0.before != read.itemTypes[$0.plan.type] }
        for choice in chosenFields { held = held.applying(choice.plan) }
        for (type, choice) in chosenIcons {
            if read.itemTypes[type]?.icon != choice.before {
                chosenIcons[type] = nil
            } else {
                held = held.choosingIcon(choice.icon, ofType: type)
            }
        }
        return held
    }

    /// Reads the bin's retention from the server's settings, where the host gave the library a way to.
    func readTrashDays() {
        guard let config else { return }
        settingsTurn += 1
        let turn = settingsTurn
        Task { [weak self] in
            guard let answer = try? await config.read(), let self, turn > appliedTurn else { return }
            appliedTurn = turn
            keep(answer)
        }
    }

    /// Takes a save made in This Marfa: the server's settings as it gave them.
    func take(_ answer: InstanceConfig) {
        settingsTurn += 1
        appliedTurn = settingsTurn
        keep(answer)
    }

    private func keep(_ answer: InstanceConfig) {
        trashDays = answer.number(.trashRetentionDays).flatMap { $0 > 0 ? $0 : nil }
    }

    /// The favorite tag, which the Favorite command owns, and the tag the server puts on a conflicted copy, which
    /// stays until the person keeps or bins the copy.
    var reservedTags: Set<String> { [ItemTag.favorite, MarfaProblems.conflictedCopyTag] }

    var knownTagCounts: [String: Int] { index.tagCounts.filter { !reservedTags.contains($0.key) } }

    var knownTags: [String] {
        knownTagCounts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map(\.key)
    }

    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool {
        try await source.resolve(problem, by: action)
    }
}
