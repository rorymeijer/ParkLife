import SwiftUI
import SpriteKit
import ParkLifeCore

/// Top-level layout.
///
/// iPhone gets a full-bleed park with contextual sheets; iPad keeps a panel open beside the park,
/// which is the difference the brief asks for rather than the same layout stretched (brief §35).
struct RootView: View {

    @EnvironmentObject private var session: GameSession
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var scene: ParkScene?
    @State private var activePanel: ManagementPanel?
    @State private var showingDebugMenu = false

    private var isWide: Bool { sizeClass == .regular }

    var body: some View {
        Group {
            if session.isReady {
                content
            } else if let error = session.loadError {
                ContentUnavailableView(
                    NSLocalizedString("error.couldNotStart", comment: ""),
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ProgressView()
            }
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .top) {
                parkView
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    HUDView(showingDebugMenu: $showingDebugMenu)
                    if let message = session.lastIntentRejection {
                        BannerView(message: message)
                    }
                    Spacer()
                    InspectorView()
                    BuildBarView()
                    NavigationBarView(activePanel: $activePanel, isWide: isWide)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            if isWide, let panel = activePanel {
                Divider()
                panelContent(panel)
                    .frame(width: 380)
                    .background(.regularMaterial)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activePanel)
        .sheet(item: sheetBinding) { panel in
            NavigationStack {
                panelContent(panel)
                    .navigationTitle(Text(NSLocalizedString(panel.localizationKey, comment: "")))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(NSLocalizedString("common.done", comment: "")) { activePanel = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingDebugMenu) {
            NavigationStack {
                DebugMenuView()
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// On iPad the panel lives beside the park, so the sheet binding must stay nil there.
    private var sheetBinding: Binding<ManagementPanel?> {
        Binding(
            get: { isWide ? nil : activePanel },
            set: { activePanel = $0 }
        )
    }

    private var parkView: some View {
        GeometryReader { proxy in
            SpriteView(scene: makeScene(size: proxy.size), preferredFramesPerSecond: 60)
                .accessibilityLabel(Text(NSLocalizedString("accessibility.parkView", comment: "")))
                .accessibilityHint(Text(NSLocalizedString("accessibility.parkViewHint", comment: "")))
        }
    }

    private func makeScene(size: CGSize) -> ParkScene {
        if let scene {
            scene.size = size
            return scene
        }
        let created = ParkScene(size: size, session: session)
        DispatchQueue.main.async { scene = created }
        return created
    }

    @ViewBuilder
    private func panelContent(_ panel: ManagementPanel) -> some View {
        switch panel {
        case .build: BuildPanel()
        case .guests: GuestsPanel()
        case .staff: StaffPanel()
        case .finances: FinancePanel()
        case .reservations: ReservationsPanel()
        case .park: ParkPanel()
        case .research: ResearchPanel()
        case .statistics: StatisticsPanel()
        case .notifications: NotificationsPanel()
        case .saves: SavesPanel()
        }
    }
}

/// The management sections in the bottom navigation.
enum ManagementPanel: String, CaseIterable, Identifiable {
    case build
    case guests
    case staff
    case reservations
    case finances
    case park
    case research
    case statistics
    case notifications
    case saves

    var id: String { rawValue }

    var localizationKey: String { "panel.\(rawValue)" }

    var symbolName: String {
        switch self {
        case .build: return "hammer"
        case .guests: return "figure.2.and.child.holdinghands"
        case .staff: return "person.badge.shield.checkmark"
        case .reservations: return "calendar"
        case .finances: return "eurosign.circle"
        case .park: return "leaf"
        case .research: return "flask"
        case .statistics: return "chart.xyaxis.line"
        case .notifications: return "bell"
        case .saves: return "externaldrive"
        }
    }
}

struct NavigationBarView: View {

    @EnvironmentObject private var session: GameSession
    @Binding var activePanel: ManagementPanel?
    let isWide: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ManagementPanel.allCases) { panel in
                    Button {
                        activePanel = (activePanel == panel) ? nil : panel
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: panel.symbolName)
                                .font(.system(size: 18, weight: .semibold))
                            Text(NSLocalizedString(panel.localizationKey, comment: ""))
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 64, minHeight: 52)
                        .overlay(alignment: .topTrailing) {
                            if panel == .notifications, unreadCount > 0 {
                                Text("\(unreadCount)")
                                    .font(.caption2.bold())
                                    .padding(4)
                                    .background(Circle().fill(.red))
                                    .foregroundStyle(.white)
                                    .offset(x: 6, y: -4)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(activePanel == panel ? .accentColor : .secondary)
                    .accessibilityLabel(Text(NSLocalizedString(panel.localizationKey, comment: "")))
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 62)
    }

    private var unreadCount: Int {
        session.snapshot?.hud.unreadNotifications ?? 0
    }
}

struct BannerView: View {

    let message: String

    var body: some View {
        Text(message)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.orange, lineWidth: 1))
            .transition(.opacity)
            .accessibilityAddTraits(.isStaticText)
    }
}
