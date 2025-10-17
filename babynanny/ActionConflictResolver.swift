import Foundation

struct ActionConflictResolver {
    enum Policy {
        case lastModifiedWins
    }

    var policy: Policy = .lastModifiedWins

    func resolve(local: BabyActionSnapshot, remote: BabyActionSnapshot) -> BabyActionSnapshot {
        switch policy {
        case .lastModifiedWins:
            if remote.updatedAt > local.updatedAt {
                return remote
            }
            if remote.updatedAt < local.updatedAt {
                return local
            }
            if let remoteEnd = remote.endDate, let localEnd = local.endDate, remoteEnd != localEnd {
                return remoteEnd > localEnd ? remote : local
            }
            return remote
        }
    }
}
