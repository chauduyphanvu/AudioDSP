import Foundation

// MARK: - A/B Comparison

/// A/B comparison slot identifier
enum ABSlot {
    case a, b
}

extension DSPState {
    /// Copy current state to the active slot
    func copyToCurrentSlot() {
        let snapshot = createSnapshot()
        switch abSlot {
        case .a: slotA = snapshot
        case .b: slotB = snapshot
        }
    }

    /// Switch between A/B comparison slots
    func switchABSlot(showToast: Bool = true) {
        // Save current to current slot
        copyToCurrentSlot()

        // Switch slot
        abSlot = abSlot == .a ? .b : .a

        // Restore from new slot
        if let snapshot = (abSlot == .a ? slotA : slotB) {
            restoreSnapshot(snapshot)
        }

        syncToChain()

        if showToast {
            let slotName = abSlot == .a ? "A" : "B"
            ToastManager.shared.show(action: "Slot \(slotName)", icon: "a.square.fill")
        }
    }
}
