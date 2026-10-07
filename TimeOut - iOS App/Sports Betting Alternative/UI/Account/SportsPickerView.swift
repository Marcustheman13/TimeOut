import SwiftUI

/// Pick the leagues that show up on the board. Used for first-launch onboarding and from Account.
struct SportsPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var isOnboarding = false
    @State private var selection: Set<League> = []

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isOnboarding {
                        header
                    } else {
                        Text("Only the sports you follow show up on the board.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(League.allCases) { league in
                            tile(league)
                        }
                    }

                    HStack {
                        Button(selection.count == League.allCases.count ? "Clear all" : "Select all") {
                            selection = selection.count == League.allCases.count ? [] : Set(League.allCases)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("\(selection.count) selected")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle(isOnboarding ? "" : "Your Sports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                if !isOnboarding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.sports.save(selection)
                    Task { await model.tick() }
                    dismiss()
                } label: {
                    Text(selection.isEmpty ? "Pick at least one" : isOnboarding ? "Let's Go" : "Save")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(selection.isEmpty ? Theme.textMuted : Theme.accent, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(selection.isEmpty)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .background(Theme.background)
            }
        }
        .onAppear { selection = isOnboarding ? [] : model.sports.followed }
        .interactiveDismissDisabled(isOnboarding)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hourglass.bottomhalf.filled")
                    .foregroundStyle(Theme.accent)
                Text(Theme.brand)
                    .font(.display(28, weight: .black))
                    .italic()
            }
            Text("Pick your sports")
                .font(.display(38, weight: .black))
            Text("Bet screen time, not money. You get \(BetBook.dailyAllowance) minutes a day. Wins add to tomorrow's phone time and losses take it away.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 12)
    }

    private func tile(_ league: League) -> some View {
        let on = selection.contains(league)
        return Button {
            if on { selection.remove(league) } else { selection.insert(league) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: league.symbol)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(on ? .black : Theme.accent)
                    Spacer()
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(on ? .black : Theme.textMuted)
                }
                Text(league.title)
                    .font(.display(22, weight: .black))
                    .foregroundStyle(on ? .black : .white)
                Text(subtitle(league))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? .black.opacity(0.6) : Theme.textMuted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Theme.accent : Theme.surface, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(on ? .clear : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func subtitle(_ league: League) -> String {
        switch league {
        case .nfl: "Pro football"
        case .ncaaf: "College football"
        case .nba: "Pro basketball"
        case .wnba: "Women's pro basketball"
        case .mlb: "Pro baseball"
        case .nhl: "Pro hockey"
        case .mls: "US soccer"
        case .epl: "Premier League"
        case .sim: "Always on, every 10 min"
        }
    }
}
