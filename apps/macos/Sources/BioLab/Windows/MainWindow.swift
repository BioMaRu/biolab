import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case ports, agents, usage, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ports: "Ports"
        case .agents: "Agents"
        case .usage: "AI Usage"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .ports: "network"
        case .agents: "cpu"
        case .usage: "waveform.path.ecg"
        case .settings: "gearshape"
        }
    }
}

struct MainWindow: View {
    @Environment(AppState.self) private var state
    @AppStorage("window.section") private var sectionRaw = MainSection.ports.rawValue

    private var selection: Binding<MainSection?> {
        Binding(
            get: { MainSection(rawValue: sectionRaw) ?? .ports },
            set: { sectionRaw = ($0 ?? .ports).rawValue }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(MainSection.allCases, selection: selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .listStyle(.sidebar)
        } detail: {
            switch MainSection(rawValue: sectionRaw) ?? .ports {
            case .ports: PortsScreen()
            case .agents: AgentsScreen()
            case .usage: UsageScreen()
            case .settings: SettingsScreen()
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .task { state.bootstrap() }
    }
}
