import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var slip = model.slip

        TabView(selection: $model.tab) {
            Tab("Sportsbook", systemImage: "sportscourt.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("My Bets", systemImage: "ticket.fill", value: AppTab.bets) {
                MyBetsView()
            }
            .badge(model.book.openBets.count)
            Tab("Record", systemImage: "chart.bar.fill", value: AppTab.record) {
                RecordView()
            }
            Tab("Account", systemImage: "hourglass", value: AppTab.account) {
                AccountView()
            }
        }
        .tabViewBottomAccessory(isEnabled: !slip.isEmpty) {
            SlipBar()
        }
        .sheet(isPresented: $slip.isPresented) {
            BetSlipView()
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.background)
        }
        .fullScreenCover(isPresented: .init(get: { !model.sports.hasPicked }, set: { _ in })) {
            SportsPickerView(isOnboarding: true)
        }
        .sheet(item: $model.sharing) { bet in
            ShareBetView(bet: bet)
                .presentationBackground(Theme.background)
        }
        .alert("Betting forfeited for today", isPresented: $model.showForfeitNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Screen Time access was turned off while your limits were on. Your betting balance is gone until midnight. Reconnect Screen Time in Account to keep playing tomorrow.")
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { model.toast = nil }
                    .padding(.top, 4)
            }
        }
        .animation(.spring(duration: 0.35), value: model.toast)
    }
}

/// Floating bar above the tab bar while picks are on the slip.
private struct SlipBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let slip = model.slip
        Button {
            slip.isPresented = true
        } label: {
            HStack(spacing: 10) {
                Text("\(slip.legs.count)")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 22, height: 22)
                    .background(Theme.accent, in: .circle)
                Text(slip.legs.count > 1 ? "Parlay" : "Bet Slip")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                if slip.hasOddsChanges {
                    Label("Odds changed", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.warning)
                } else {
                    Text(Odds.format(slip.americanOdds))
                        .font(.display(17))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.system(size: 15, weight: .heavy))
                Text(toast.message).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.raised, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(color.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch toast.style {
        case .win: "checkmark.seal.fill"
        case .loss: "xmark.octagon.fill"
        case .neutral: "ticket.fill"
        }
    }

    private var color: Color {
        switch toast.style {
        case .win: Theme.win
        case .loss: Theme.loss
        case .neutral: Theme.accent
        }
    }
}
