import CloudKit

extension Error {
    var isMissingRecordTypeError: Bool {
        guard let ckError = self as? CKError else { return false }
        return ckError.isMissingRecordTypeError
    }
}

extension CKError {
    var isMissingRecordTypeError: Bool {
        switch code {
        case .unknownItem:
            return containsMissingRecordTypeMessage
        case .partialFailure:
            let partialErrors = partialErrorsByItemID ?? [:]
            return partialErrors.values.contains { $0.isMissingRecordTypeError }
        default:
            return false
        }
    }

    var containsMissingRecordTypeMessage: Bool {
        if localizedDescription.localizedCaseInsensitiveContains("did not find record type") {
            return true
        }

        if let failureReason = userInfo[NSLocalizedFailureReasonErrorKey] as? String,
           failureReason.localizedCaseInsensitiveContains("record type") {
            return true
        }

        if let debugDescription = userInfo[NSDebugDescriptionErrorKey] as? String,
           debugDescription.localizedCaseInsensitiveContains("record type") {
            return true
        }

        return false
    }
}
