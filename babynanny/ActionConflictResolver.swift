import Foundation

struct ActionConflictResolver {
    enum Policy {
        case lastModifiedWins
    }

    var policy: Policy = .lastModifiedWins
    /// Tolerance used when comparing timestamps sourced from Supabase.
    ///
    /// Supabase currently stores timestamps with second precision, which means
    /// values that originate on-device (with subsecond precision) can appear
    /// slightly older once they round-trip through the backend. Treating values
    /// that fall within this window as equal prevents legitimate remote edits
    /// from being discarded because they appear marginally stale.
    var timestampEqualityTolerance: TimeInterval = 1

    func resolve(local: BabyActionSnapshot, remote: BabyActionSnapshot) -> BabyActionSnapshot {
        switch policy {
        case .lastModifiedWins:
            switch compare(remote.updatedAt, local.updatedAt) {
            case .orderedDescending:
                return remote
            case .orderedAscending:
                return local
            case .orderedSame:
                return resolveTie(local: local, remote: remote)
            }
        }
    }

    private func resolveTie(local: BabyActionSnapshot, remote: BabyActionSnapshot) -> BabyActionSnapshot {
        if let remoteEnd = remote.endDate {
            guard let localEnd = local.endDate else { return remote }

            switch compare(remoteEnd, localEnd) {
            case .orderedDescending:
                return remote
            case .orderedAscending:
                return local
            case .orderedSame:
                break
            }
        }

        return remote
    }

    private func compare(_ lhs: Date, _ rhs: Date) -> ComparisonResult {
        let delta = lhs.timeIntervalSince(rhs)
        if abs(delta) <= timestampEqualityTolerance {
            return .orderedSame
        }
        return delta < 0 ? .orderedAscending : .orderedDescending
    }
}
