import Foundation

// MARK: - Undo/Redo Support

extension DSPState {
    /// Register current state for undo before making changes
    func registerUndo() {
        let snapshot = createSnapshot()
        undoManager.registerUndo(withTarget: self) { target in
            target.restoreSnapshot(snapshot)
        }
        updateUndoState()
    }

    /// Register undo for EQ band changes (call at drag start, not during drag)
    /// This prevents polluting the undo stack with intermediate drag states
    func registerUndoForEQBandChange() {
        registerUndo()
    }

    /// Undo the last change
    func undo(showToast: Bool = true) {
        guard undoManager.canUndo else { return }
        undoManager.undo()
        updateUndoState()
        syncToChain()
        if showToast {
            ToastManager.shared.show(action: "Undo", icon: "arrow.uturn.backward.circle.fill")
        }
    }

    /// Redo the last undone change
    func redo(showToast: Bool = true) {
        guard undoManager.canRedo else { return }
        undoManager.redo()
        updateUndoState()
        syncToChain()
        if showToast {
            ToastManager.shared.show(action: "Redo", icon: "arrow.uturn.forward.circle.fill")
        }
    }

    /// Update published undo/redo availability
    func updateUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }
}
