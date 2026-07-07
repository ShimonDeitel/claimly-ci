import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var purchases: PurchaseManager

    @State private var activeSheet: ActiveSheet?
    @State private var stampedRebateId: UUID?

    private var sortedRebates: [Rebate] {
        store.rebates.sorted { a, b in
            if a.isActive != b.isActive { return a.isActive && !b.isActive }
            return a.submissionDeadline < b.submissionDeadline
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    tallyCard

                    if sortedRebates.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(sortedRebates) { rebate in
                                RebateCardView(
                                    rebate: rebate,
                                    isStamping: stampedRebateId == rebate.id,
                                    onMarkReceived: { markReceived(rebate) },
                                    onMarkExpired: { store.setStatus(.expired, for: rebate) },
                                    onMarkSubmitted: { store.setStatus(.submittedAwaitingPayment, for: rebate) },
                                    onEdit: { activeSheet = .editRebate(rebate) },
                                    onDelete: { store.deleteRebate(rebate) }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Theme.backdrop.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle("Claimly")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if store.canAddMoreFree || purchases.isPro {
                            activeSheet = .addRebate
                        } else {
                            activeSheet = .paywall
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("addRebateButton")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addRebate:
                    RebateFormView(existing: nil).environmentObject(store)
                case .editRebate(let rebate):
                    RebateFormView(existing: rebate).environmentObject(store)
                case .paywall:
                    PaywallView().environmentObject(purchases)
                }
            }
        }
        .tint(Theme.safeBlue)
        .preferredColorScheme(.dark)
    }

    private var tallyCard: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reclaimed This Year")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(currency(store.totalReclaimedThisYear()))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.stampGreen)
                        .accessibilityIdentifier("totalReclaimedValue")
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.stampGreen.opacity(0.85))
            }

            if purchases.isPro {
                Divider().background(Theme.divider)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("At Risk of Expiring (14 days)")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Text(currency(store.totalAtRiskOfExpiring()))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.criticalRed)
                            .accessibilityIdentifier("totalAtRiskValue")
                    }
                    Spacer()
                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .foregroundStyle(Theme.criticalRed.opacity(0.85))
                }
            }
        }
        .padding(18)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        .padding(.horizontal)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textSecondary)
            Text("No rebates tracked yet")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Tap + to log a mail-in rebate or cash-back offer before its deadline slips by.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 48)
    }

    private func markReceived(_ rebate: Rebate) {
        store.setStatus(.received, for: rebate)
        stampedRebateId = rebate.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            if stampedRebateId == rebate.id {
                stampedRebateId = nil
            }
        }
    }

    private func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

struct RebateCardView: View {
    let rebate: Rebate
    let isStamping: Bool
    let onMarkReceived: () -> Void
    let onMarkExpired: () -> Void
    let onMarkSubmitted: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var pulse = false

    private var bucket: UrgencyBucket { rebate.urgencyBucket() }
    private var daysRemaining: Int { rebate.daysRemaining() }
    private var urgencyColor: Color { Theme.urgencyColor(daysRemaining: daysRemaining, isExpired: rebate.status == .expired) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rebate.storeOrProduct)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(String(format: "$%.2f", rebate.amount))
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.safeBlue)
                }
                Spacer()
                clockBadge
            }

            Text(deadlineText)
                .font(.caption)
                .foregroundStyle(urgencyColor)

            if rebate.status == .notSubmitted || rebate.status == .submittedAwaitingPayment {
                HStack(spacing: 10) {
                    if rebate.status == .notSubmitted {
                        Button("Mark Submitted", action: onMarkSubmitted)
                            .buttonStyle(.bordered)
                            .tint(Theme.warnAmber)
                            .accessibilityIdentifier("markSubmittedButton-\(rebate.id.uuidString)")
                    }
                    Button("Cashed In!", action: onMarkReceived)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.stampGreen)
                        .accessibilityIdentifier("markReceivedButton-\(rebate.id.uuidString)")
                    Button("Missed", action: onMarkExpired)
                        .buttonStyle(.bordered)
                        .tint(Theme.criticalRed)
                        .accessibilityIdentifier("markExpiredButton-\(rebate.id.uuidString)")
                }
                .font(.caption)
            } else {
                statusPill
            }
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .stroke(urgencyColor.opacity(bucket == .critical ? (pulse ? 0.9 : 0.3) : 0.25), lineWidth: bucket == .critical ? 2 : 1)
        )
        .overlay(alignment: .center) {
            if isStamping {
                stampOverlay
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rebateCard-\(rebate.id.uuidString)")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("deleteRebateButton-\(rebate.id.uuidString)")
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Theme.safeBlue)
            .accessibilityIdentifier("editRebateButton-\(rebate.id.uuidString)")
        }
        .onAppear {
            if bucket == .critical {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    private var clockBadge: some View {
        ZStack {
            Circle()
                .fill(urgencyColor.opacity(0.18))
                .frame(width: 44, height: 44)
            Image(systemName: rebate.status == .received ? "checkmark.seal.fill" : (rebate.status == .expired ? "xmark.seal.fill" : "clock.fill"))
                .font(.system(size: 18))
                .foregroundStyle(urgencyColor)
                .scaleEffect(bucket == .critical && pulse ? 1.12 : 1.0)
        }
    }

    private var deadlineText: String {
        switch rebate.status {
        case .received: return "Received"
        case .expired: return "Expired unclaimed"
        default:
            if daysRemaining < 0 {
                return "Overdue by \(-daysRemaining) day(s)"
            } else if daysRemaining == 0 {
                return "Deadline is today"
            } else {
                return "\(daysRemaining) day(s) left to submit"
            }
        }
    }

    private var statusPill: some View {
        Text(rebate.status.shortLabel)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (rebate.status == .received ? Theme.stampGreen : Theme.expiredMuted).opacity(0.2)
            )
            .foregroundStyle(rebate.status == .received ? Theme.stampGreen : Theme.expiredMuted)
            .clipShape(Capsule())
    }

    private var stampOverlay: some View {
        ZStack {
            Color.black.opacity(0.15)
            VStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 42))
                Text("CASHED IN")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Theme.stampGreen)
            .rotationEffect(.degrees(-12))
            .scaleEffect(1.15)
            .transition(.scale.combined(with: .opacity))
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        .animation(.spring(response: 0.35, dampingFraction: 0.5), value: isStamping)
    }
}
