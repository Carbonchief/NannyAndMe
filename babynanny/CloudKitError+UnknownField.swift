import CloudKit

extension Error {
    var isUnknownFieldError: Bool {
        guard let ckError = self as? CKError else { return false }
        return ckError.isUnknownFieldError
    }
}

extension CKError {
    var isUnknownFieldError: Bool {
        switch code {
        case .invalidArguments:
            return containsUnknownFieldMessage
        case .partialFailure:
            let partialErrors = partialErrorsByItemID ?? [:]
            return partialErrors.values.contains { $0.isUnknownFieldError }
        default:
            return false
        }
    }

    private var containsUnknownFieldMessage: Bool {
        let possibleMessages: [String] = [
            localizedDescription,
            userInfo[NSLocalizedFailureReasonErrorKey] as? String,
            userInfo[NSDebugDescriptionErrorKey] as? String
        ].compactMap { $0?.lowercased() }

        return possibleMessages.contains { message in
            message.contains("unknown field")
        }
    }
}
