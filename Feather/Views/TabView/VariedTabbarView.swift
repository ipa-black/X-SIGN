import SwiftUI

struct VariedTabbarView: View {
    @State private var selectedTab: TabEnum = .today
    @ObservedObject private var pipeline = AutoSignPipelineManager.shared
    @State private var presentedSheet: XSignSheet?
    @State private var presentedInstallID: String?

    private let tabs: [TabEnum] = [.today, .games, .sources, .library]

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(tabs, id: \.self) { tab in
                TabEnum.view(for: tab)
                    .tag(tab)
                    .tabItem { Label(tab.title, systemImage: tab.icon) }
                    .toolbar(.hidden, for: .tabBar)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            XSignFloatingDock(selection: $selectedTab, showsSearch: Binding(
                get: { if case .search? = presentedSheet { return true }; return false },
                set: { if $0 { presentedSheet = .search } }
            ))
                .frame(maxWidth: 560)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
        }
        .sheet(item: $presentedSheet, onDismiss: {
            if let id = presentedInstallID {
                presentedInstallID = nil
                pipeline.dismissInstallation(id: id)
            }
            DispatchQueue.main.async { presentInstallationIfReady() }
        }) { sheet in
            switch sheet {
            case .search:
                AppStoreSearchView()
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.large])
            case .installation(let app):
                InstallPreviewView(app: app.base, isSharing: app.archive)
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.height(200)])
            }
        }
        .onReceive(pipeline.$readyToInstallApp) { _ in
            // Published emits before its stored value changes.
            DispatchQueue.main.async { presentInstallationIfReady() }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(.dark)
    }

    @MainActor
    private func presentInstallationIfReady() {
        guard presentedSheet == nil, let app = pipeline.readyToInstallApp else { return }
        presentedInstallID = app.id
        presentedSheet = .installation(app)
    }
}

private enum XSignSheet: Identifiable {
    case search
    case installation(AnyApp)

    var id: String {
        switch self {
        case .search: return "search"
        case .installation(let app): return "install-" + app.id
        }
    }
}

private struct XSignFloatingDock: View {
    @Binding var selection: TabEnum
    @Binding var showsSearch: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 66
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 12

    // Fixed visual order from the reference: search, Arcade, apps, games, today.
    private let visualOrder: [TabEnum] = [.library, .sources, .games, .today]
    private let accent = Color(red: 0.24, green: 0.77, blue: 1)

    var body: some View {
        HStack(spacing: 10) {
            Button {
                showsSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: height, height: height)
                    .background { XSignGlassSurface() }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("بحث في التطبيقات والألعاب")

            HStack(spacing: 0) {
                ForEach(visualOrder, id: \.self) { tab in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                            selection = tab
                        }
                    } label: {
                        VStack(spacing: 4) {
                            dockIcon(tab)
                                .frame(width: 30, height: 29)
                            Text(tab == .library ? "Arcade" : tab.title)
                                .font(.system(size: labelSize, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(selection == tab ? accent : .white.opacity(0.94))
                        .frame(maxWidth: .infinity)
                        .frame(height: height - 8)
                        .contentShape(Capsule())
                        .background {
                            if selection == tab {
                                Capsule().fill(.white.opacity(0.14))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab == .library ? "Arcade، مكتبة التوقيع" : tab.title)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
            .padding(4)
            .background { XSignGlassSurface() }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder
    private func dockIcon(_ tab: TabEnum) -> some View {
        switch tab {
        case .library:
            XSignJoystickIcon()
        case .games:
            XSignRocketIcon().fill(style: FillStyle(eoFill: true))
        case .sources:
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 28, weight: .bold))
        default:
            Image(systemName: "doc.text.image")
                .font(.system(size: 27, weight: .semibold))
        }
    }
}

private struct XSignGlassSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                Capsule().fill(Color(white: 0.15))
            } else {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(.white.opacity(0.06))
            }
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.5), .white.opacity(0.08), .white.opacity(0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
            )
        }
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }
}

private struct XSignJoystickIcon: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.08, y: h * 0.63))
                p.addLines([
                    CGPoint(x: w * 0.5, y: h * 0.42),
                    CGPoint(x: w * 0.92, y: h * 0.63),
                    CGPoint(x: w * 0.5, y: h * 0.84)
                ])
                p.closeSubpath()
                p.move(to: CGPoint(x: w * 0.08, y: h * 0.79))
                p.addLines([
                    CGPoint(x: w * 0.5, y: h * 0.99),
                    CGPoint(x: w * 0.92, y: h * 0.79)
                ])
            }
            .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            Capsule().frame(width: 3.5, height: h * 0.35)
                .position(x: w * 0.5, y: h * 0.4)
            Circle().frame(width: 9, height: 9)
                .position(x: w * 0.5, y: h * 0.12)
        }
    }
}

private struct XSignRocketIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 37, y: 2))
        p.addCurve(to: CGPoint(x: 17, y: 9), control1: CGPoint(x: 29, y: 1), control2: CGPoint(x: 22, y: 4))
        p.addLine(to: CGPoint(x: 12, y: 15))
        p.addCurve(to: CGPoint(x: 4, y: 17), control1: CGPoint(x: 7, y: 12), control2: CGPoint(x: 5, y: 14))
        p.addLine(to: CGPoint(x: 1, y: 26))
        p.addLine(to: CGPoint(x: 9, y: 24))
        p.addLine(to: CGPoint(x: 15, y: 30))
        p.addLine(to: CGPoint(x: 13, y: 38))
        p.addLine(to: CGPoint(x: 22, y: 34))
        p.addCurve(to: CGPoint(x: 24, y: 26), control1: CGPoint(x: 25, y: 31), control2: CGPoint(x: 26, y: 30))
        p.addCurve(to: CGPoint(x: 37, y: 2), control1: CGPoint(x: 33, y: 18), control2: CGPoint(x: 37, y: 10))
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: 24, y: 8, width: 7, height: 7))
        p.move(to: CGPoint(x: 8, y: 29))
        p.addQuadCurve(to: CGPoint(x: 2, y: 38), control: CGPoint(x: 0, y: 31))
        p.addQuadCurve(to: CGPoint(x: 13, y: 33), control: CGPoint(x: 9, y: 39))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 40, y: rect.height / 40))
    }
}
