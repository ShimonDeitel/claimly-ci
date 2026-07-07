import SwiftUI

/// Unified sheet-item enum so the home screen uses a single `.sheet(item:)`
/// modifier instead of stacking several `.sheet`/`.alert` modifiers (which has
/// caused real bugs in sibling apps -- only the last one attaches reliably).
enum ActiveSheet: Identifiable, Equatable {
    case addRebate
    case editRebate(Rebate)
    case paywall

    var id: String {
        switch self {
        case .addRebate: return "addRebate"
        case .editRebate(let rebate): return "editRebate-\(rebate.id.uuidString)"
        case .paywall: return "paywall"
        }
    }
}

struct RebateFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let existing: Rebate?

    @State private var storeOrProduct: String = ""
    @State private var amountText: String = ""
    @State private var purchaseDate: Date = Date()
    @State private var submissionDeadline: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var status: RebateStatus = .notSubmitted
    @State private var notes: String = ""

    private var isValid: Bool {
        !storeOrProduct.trimmingCharacters(in: .whitespaces).isEmpty && Double(amountText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rebate Details") {
                    TextField("Store or Product", text: $storeOrProduct)
                        .accessibilityIdentifier("storeOrProductField")
                    TextField("Rebate Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("amountField")
                }
                Section("Dates") {
                    DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
                        .accessibilityIdentifier("purchaseDatePicker")
                    DatePicker("Submission Deadline", selection: $submissionDeadline, displayedComponents: .date)
                        .accessibilityIdentifier("deadlinePicker")
                }
                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(RebateStatus.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .accessibilityIdentifier("statusPicker")
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("notesField")
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle(existing == nil ? "New Rebate" : "Edit Rebate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                        .accessibilityIdentifier("saveEntryButton")
                }
            }
            .onAppear { populateIfEditing() }
        }
    }

    private func populateIfEditing() {
        guard let existing else { return }
        storeOrProduct = existing.storeOrProduct
        amountText = String(format: "%.2f", existing.amount)
        purchaseDate = existing.purchaseDate
        submissionDeadline = existing.submissionDeadline
        status = existing.status
        notes = existing.notes
    }

    private func save() {
        guard let amount = Double(amountText) else { return }
        if let existing {
            var updated = existing
            updated.storeOrProduct = storeOrProduct
            updated.amount = amount
            updated.purchaseDate = purchaseDate
            updated.submissionDeadline = submissionDeadline
            updated.status = status
            updated.notes = notes
            store.updateRebate(updated)
        } else {
            store.addRebate(
                storeOrProduct: storeOrProduct,
                amount: amount,
                purchaseDate: purchaseDate,
                submissionDeadline: submissionDeadline,
                notes: notes
            )
        }
        dismiss()
    }
}
