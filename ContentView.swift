import SwiftUI
import CoreLocation
import CoreMotion
import MapKit
import AVFoundation
import UIKit

// MARK: - iOS 14/15 相容色彩
extension Color {
    static var safeCyan: Color {
        if #available(iOS 15.0, *) { return Color.cyan }
        else { return Color(red: 0.0, green: 0.75, blue: 1.0) }
    }
}
extension UIColor {
    static var safeSystemCyan: UIColor {
        if #available(iOS 15.0, *) { return UIColor.systemCyan }
        else { return UIColor(red: 0.0, green: 0.75, blue: 1.0, alpha: 1.0) }
    }
    static var navigationBlue: UIColor {
        return UIColor(red: 0.1, green: 0.4, blue: 1.0, alpha: 1.0)
    }
}

// MARK: - 資料模型
struct OverspeedRecord: Identifiable, Codable {
    let id: UUID; let date: Date; let speed: Double; let speedLimit: Double
}
struct HistoryRecord: Identifiable, Codable {
    let id: UUID; let date: Date; let maxSpeed: Double
    let zeroToOneHundredTime: Double; let maxGForce: Double
    let tripDistance: Double; let routeCoordinates: [CodableCoordinate]
}
struct CodableCoordinate: Codable {
    let latitude: Double; let longitude: Double
    init(_ c: CLLocationCoordinate2D) { latitude = c.latitude; longitude = c.longitude }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
struct SpeedCamera: Identifiable, Codable {
    var id: UUID = UUID()
    let latitude: Double; let longitude: Double
    let speedLimit: Double; let description: String
    var isTemporary: Bool = false
    var expiresAt: Date? = nil
    enum CodingKeys: String, CodingKey { case latitude, longitude, speedLimit, description, isTemporary, expiresAt }
    init(latitude: Double, longitude: Double, speedLimit: Double, description: String, isTemporary: Bool = false, expiresAt: Date? = nil) {
        self.latitude = latitude; self.longitude = longitude
        self.speedLimit = speedLimit; self.description = description; self.isTemporary = isTemporary
        self.expiresAt = expiresAt
    }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

enum TransportMode: String, CaseIterable, Identifiable {
    case car = "汽車"
    case motorcycle = "機車"
    case bicycle = "腳踏車"
    var id: String { rawValue }
    var defaultSpeedLimit: Double {
        switch self { case .car: return 50; case .motorcycle: return 50; case .bicycle: return 25 }
    }
}
struct MapSearchResult: Identifiable {
    let id = UUID(); let title: String; let subtitle: String; let coordinate: CLLocationCoordinate2D
}

// MARK: - 主題
enum DashboardTheme: String, CaseIterable, Identifiable {
    case skull = "骷髏暴力風"
    case cyberpunk = "賽伯戰爭風"
    case sakura = "日本櫻花風"
    var id: String { rawValue }
    func primaryColor(custom: Color?) -> Color {
        if let c = custom { return c }
        switch self {
        case .skull:     return .red
        case .cyberpunk: return .safeCyan
        case .sakura:    return Color(red: 1.0, green: 0.3, blue: 0.4)
        }
    }
    var backgroundGradientColors: [Color] {
        switch self {
        case .skull:    return [Color(red:0.18,green:0,blue:0), Color.black, Color(red:0.08,green:0,blue:0.02)]
        case .cyberpunk: return [Color(red:0.01,green:0.04,blue:0.16), Color.black, Color(red:0.04,green:0,blue:0.14)]
        case .sakura:   return [Color(red:0.14,green:0.02,blue:0.05), Color(red:0.03,green:0.01,blue:0.03), Color.black]
        }
    }
}
extension Color: @retroactive RawRepresentable {
    public init?(rawValue: String) {
        let c = rawValue.components(separatedBy: ",")
        guard c.count == 3, let r = Double(c[0]), let g = Double(c[1]), let b = Double(c[2]) else { return nil }
        self.init(red: r, green: g, blue: b)
    }
    public var rawValue: String {
        let u = UIColor(self); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a); return "\(r),\(g),\(b)"
    }
}

// MARK: - 動畫計時器
private final class DisplayLinkTarget: NSObject {
    weak var owner: AnimationClock?
    init(owner: AnimationClock) { self.owner = owner }
    @objc func update() { owner?.update() }
}

final class AnimationClock: ObservableObject {
    @Published private(set) var tick: Double = 0
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private lazy var displayLinkTarget = DisplayLinkTarget(owner: self)
    init() {}
    func start() {
        guard displayLink == nil else { return }
        startTime = CACurrentMediaTime()
        displayLink = CADisplayLink(target: displayLinkTarget, selector: #selector(DisplayLinkTarget.update))
        displayLink?.preferredFramesPerSecond = 30
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
        }
        displayLink?.add(to: .main, forMode: .common)
    }
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }
    fileprivate func update() { tick = CACurrentMediaTime() - startTime }
    deinit { stop() }
}

// MARK: - 地圖搜尋管理器
class MapSearchManager: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var searchText: String = ""
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var searchResults: [MapSearchResult] = []
    @Published var isSearching: Bool = false
    private let completer = MKLocalSearchCompleter()
    private var pendingCompletionUpdate: DispatchWorkItem?
    private var activeSearch: MKLocalSearch?
    var currentRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25.033, longitude: 121.565),
        latitudinalMeters: 5000, longitudinalMeters: 5000)
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }
    func updateSearch(_ text: String) {
        searchText = text
        pendingCompletionUpdate?.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            completer.queryFragment = ""
            completions = []
            return
        }
        let update = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.completer.region = self.currentRegion
            self.completer.queryFragment = query
        }
        pendingCompletionUpdate = update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: update)
    }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async { self.completions = Array(completer.results.prefix(6)) }
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) { completions = [] }
    func searchFor(_ completion: MKLocalSearchCompletion, callback: @escaping (CLLocationCoordinate2D?) -> Void) {
        let req = MKLocalSearch.Request(completion: completion)
        activeSearch?.cancel()
        let search = MKLocalSearch(request: req)
        activeSearch = search
        search.start { [weak self] resp, _ in
            DispatchQueue.main.async {
                guard self?.activeSearch === search else { return }
                self?.activeSearch = nil
                callback(resp?.mapItems.first?.placemark.coordinate)
            }
        }
    }
    func searchByText(_ text: String, region: MKCoordinateRegion, callback: @escaping (CLLocationCoordinate2D?) -> Void) {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text; req.region = region
        activeSearch?.cancel()
        let search = MKLocalSearch(request: req)
        activeSearch = search
        search.start { [weak self] resp, _ in
            DispatchQueue.main.async {
                guard self?.activeSearch === search else { return }
                self?.activeSearch = nil
                callback(resp?.mapItems.first?.placemark.coordinate)
            }
        }
    }
}

// MARK: - 地圖搜尋覆蓋層
struct MapSearchOverlayView: View {
    @ObservedObject var searchManager: MapSearchManager
    @ObservedObject var vehicleManager: VehicleManager
    var primaryColor: Color
    var onSelectDestination: (CLLocationCoordinate2D, String) -> Void
    var onDismiss: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: { onDismiss() }) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold))
                        .foregroundColor(primaryColor).frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.7)).clipShape(Circle())
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundColor(primaryColor)
                    SearchTextField(
                        text: Binding(get: { searchManager.searchText }, set: { searchManager.updateSearch($0) }),
                        placeholder: "搜尋目的地、地址、景點",
                        primaryColor: UIColor(primaryColor),
                        onSubmit: {
                            guard !searchManager.searchText.isEmpty else { return }
                            let region = MKCoordinateRegion(center: vehicleManager.currentLocation,
                                latitudinalMeters: 10000, longitudinalMeters: 10000)
                            searchManager.searchByText(searchManager.searchText, region: region) { coord in
                                guard let coord = coord else { return }
                                onSelectDestination(coord, searchManager.searchText)
                            }
                        }
                    ).frame(height: 36)
                    if !searchManager.searchText.isEmpty {
                        Button(action: { searchManager.updateSearch("") }) {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(primaryColor.opacity(0.5), lineWidth: 1))
                .cornerRadius(12)
            }
            .padding(.horizontal, 16).padding(.top, 16)
            .padding(.bottom, searchManager.completions.isEmpty ? 16 : 8)
            if !searchManager.completions.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(searchManager.completions, id: \.self) { item in
                            Button(action: {
                                searchManager.searchFor(item) { coord in
                                    guard let coord = coord else { return }
                                    onSelectDestination(coord, item.title)
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill").font(.system(size: 18))
                                        .foregroundColor(primaryColor).frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white).lineLimit(1)
                                        if !item.subtitle.isEmpty {
                                            Text(item.subtitle).font(.system(size: 11))
                                                .foregroundColor(.gray).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.left").font(.system(size: 11)).foregroundColor(.gray)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                            }
                            if item != searchManager.completions.last {
                                Divider().background(Color.white.opacity(0.1)).padding(.leading, 56)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
                .background(Color.black.opacity(0.88))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(primaryColor.opacity(0.25), lineWidth: 1))
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            Spacer()
        }
        .background(VStack {
            Color.black.opacity(0.5).frame(height: searchManager.completions.isEmpty ? 90 : 400)
            Spacer()
        }.ignoresSafeArea())
    }
}

// MARK: - iOS 14 搜尋輸入框
struct SearchTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String; var primaryColor: UIColor; var onSubmit: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.attributedPlaceholder = NSAttributedString(string: placeholder,
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.4)])
        tf.textColor = .white
        tf.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        tf.returnKeyType = .search; tf.backgroundColor = .clear; tf.delegate = context.coordinator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tf.becomeFirstResponder() }
        return tf
    }
    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text { uiView.text = text }
    }
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SearchTextField
        init(_ p: SearchTextField) { self.parent = p }
        func textFieldDidChangeSelection(_ textField: UITextField) {
            let newText = textField.text ?? ""
            if parent.text != newText { parent.text = newText }
        }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder(); parent.onSubmit(); return true
        }
    }
}

// MARK: - ★ 骷髏主題：血色霧氣
struct SkullBloodFogView: View {
    let tick: Double
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<18, id: \.self) { i in
                    let seed = Double(i) * 137.5
                    let phase = tick * 0.38 + seed
                    let xFrac = sin(phase * 0.31 + seed * 0.07) * 0.5 + 0.5
                    let yFrac = cos(phase * 0.19 + seed * 0.11) * 0.5 + 0.5
                    let radius = CGFloat(55 + sin(phase * 0.5 + seed) * 35)
                    let opacity = 0.05 + abs(sin(phase * 0.27 + seed * 0.3)) * 0.12
                    Circle().fill(Color(red: 0.85, green: 0.0, blue: 0.05))
                        .frame(width: radius * 2, height: radius * 2)
                        .position(x: CGFloat(xFrac) * geo.size.width, y: CGFloat(yFrac) * geo.size.height)
                        .opacity(opacity).blur(radius: 18)
                }
            }
        }
        .blendMode(.screen).allowsHitTesting(false).ignoresSafeArea()
    }
}

// MARK: - ★ 賽伯主題：青色霧氣（與骷髏同結構）
struct CyberpunkFogView: View {
    let tick: Double
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<18, id: \.self) { i in
                    let seed = Double(i) * 137.5
                    let phase = tick * 0.38 + seed
                    let xFrac = sin(phase * 0.31 + seed * 0.07) * 0.5 + 0.5
                    let yFrac = cos(phase * 0.19 + seed * 0.11) * 0.5 + 0.5
                    let radius = CGFloat(55 + sin(phase * 0.5 + seed) * 35)
                    let opacity = 0.04 + abs(sin(phase * 0.27 + seed * 0.3)) * 0.10
                    Circle().fill(Color.safeCyan)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(x: CGFloat(xFrac) * geo.size.width, y: CGFloat(yFrac) * geo.size.height)
                        .opacity(opacity).blur(radius: 20)
                }
            }
        }
        .blendMode(.screen).allowsHitTesting(false).ignoresSafeArea()
    }
}

// MARK: - ★ 櫻花主題：粉紅霧氣（與骷髏同結構）
struct SakuraFogView: View {
    let tick: Double
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<18, id: \.self) { i in
                    let seed = Double(i) * 137.5
                    let phase = tick * 0.38 + seed
                    let xFrac = sin(phase * 0.31 + seed * 0.07) * 0.5 + 0.5
                    let yFrac = cos(phase * 0.19 + seed * 0.11) * 0.5 + 0.5
                    let radius = CGFloat(55 + sin(phase * 0.5 + seed) * 35)
                    let opacity = 0.05 + abs(sin(phase * 0.27 + seed * 0.3)) * 0.11
                    Circle().fill(Color(red: 1.0, green: 0.3, blue: 0.5))
                        .frame(width: radius * 2, height: radius * 2)
                        .position(x: CGFloat(xFrac) * geo.size.width, y: CGFloat(yFrac) * geo.size.height)
                        .opacity(opacity).blur(radius: 18)
                }
            }
        }
        .blendMode(.screen).allowsHitTesting(false).ignoresSafeArea()
    }
}

// MARK: - 賽伯矩陣數字流（開場用）
struct CyberpunkMatrixRainView: View {
    let tick: Double
    var body: some View {
        if #available(iOS 15.0, *) { CyberpunkMatrixRainCanvas(tick: tick) }
        else { CyberpunkMatrixRainFallback(tick: tick) }
    }
}
@available(iOS 15.0, *)
private struct CyberpunkMatrixRainCanvas: View {
    let tick: Double
    private let columns = 22
    private let chars = ["0","1","ア","イ","ウ","エ","オ","カ","キ","ク","ケ","コ",
                         "サ","シ","ス","△","◇","╬","░","▓","∑","∞","π","Ω"]
    var body: some View {
        Canvas { ctx, size in
            let colWidth = size.width / CGFloat(columns)
            for col in 0..<columns {
                let seed = Double(col) * 73.1
                let spd = 0.6 + fmod(seed * 0.031, 0.8)
                let phase = fmod(tick * spd + seed * 0.4, 1.0)
                for row in 0..<12 {
                    let rowFrac = (CGFloat(row)/12.0 + CGFloat(phase)).truncatingRemainder(dividingBy: 1.0)
                    let y = rowFrac * (size.height + 60) - 30
                    let x = CGFloat(col) * colWidth + colWidth / 2
                    let fade = 1.0 - Double(row) / 12.0
                    let charIdx = (col*7 + row + Int(tick*8)) % chars.count
                    ctx.opacity = (row == 0 ? 1.0 : fade*0.55) * 0.85
                    ctx.draw(Text(chars[charIdx])
                        .font(.system(size: CGFloat(9+col%3*2), weight: .bold, design: .monospaced))
                        .foregroundColor(row == 0 ? .white : .safeCyan), at: CGPoint(x:x,y:y))
                }
            }
        }
        .allowsHitTesting(false).ignoresSafeArea().blendMode(.screen)
    }
}
private struct CyberpunkMatrixRainFallback: View {
    let tick: Double
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<12, id: \.self) { col in
                    let seed = Double(col) * 73.1
                    let phase = CGFloat(fmod(tick*0.7 + seed*0.4, 1.0))
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, Color.safeCyan.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(width: 1.5, height: geo.size.height*0.4)
                        .position(x: CGFloat(col)/12.0*geo.size.width, y: phase*geo.size.height)
                }
            }
        }
        .blendMode(.screen).allowsHitTesting(false).ignoresSafeArea()
    }
}

// MARK: - 賽伯霓虹網格（開場用）
struct CyberpunkNeonGridView: View {
    let tick: Double
    var body: some View {
        if #available(iOS 15.0, *) { CyberpunkNeonGridCanvas(tick: tick) }
        else { CyberpunkNeonGridFallback(tick: tick) }
    }
}
@available(iOS 15.0, *)
private struct CyberpunkNeonGridCanvas: View {
    let tick: Double
    var body: some View {
        Canvas { ctx, size in
            let vp = CGPoint(x: size.width/2, y: size.height*0.55)
            let cols = 10; let rows = 8
            let pulse = 0.7 + sin(tick*2.2)*0.3
            for c in 0...cols {
                let t = CGFloat(c)/CGFloat(cols)
                var path = Path(); path.move(to: vp)
                path.addLine(to: CGPoint(x: t*size.width, y: size.height))
                ctx.opacity = 0.18*pulse
                ctx.stroke(path, with: .color(.safeCyan), style: StrokeStyle(lineWidth: 0.8))
            }
            for r in 1...rows {
                let t = CGFloat(r)/CGFloat(rows); let eased = t*t
                let leftX = vp.x - vp.x*eased; let rightX = vp.x + (size.width-vp.x)*eased
                let y = vp.y + (size.height-vp.y)*eased
                var path = Path(); path.move(to: CGPoint(x:leftX,y:y)); path.addLine(to: CGPoint(x:rightX,y:y))
                ctx.opacity = (0.08+eased*0.2)*pulse
                ctx.stroke(path, with: .color(.safeCyan), style: StrokeStyle(lineWidth: 0.9))
            }
        }
        .allowsHitTesting(false).ignoresSafeArea().blendMode(.screen)
    }
}
private struct CyberpunkNeonGridFallback: View {
    let tick: Double
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    let t = CGFloat(i)/5.0
                    Rectangle().fill(Color.safeCyan.opacity(0.12*Double(t))).frame(height: 1)
                        .position(x: geo.size.width/2, y: geo.size.height*0.55+geo.size.height*0.45*t)
                        .frame(width: geo.size.width*(0.2+t*0.8))
                }
            }
        }
        .blendMode(.screen).allowsHitTesting(false).ignoresSafeArea()
    }
}

// MARK: - 櫻花金光粒子（開場用）
struct SakuraGoldParticlesView: View {
    let tick: Double
    var body: some View {
        if #available(iOS 15.0, *) { SakuraGoldParticlesCanvas(tick: tick) }
        else { SakuraGoldParticlesFallback(tick: tick) }
    }
}
@available(iOS 15.0, *)
private struct SakuraGoldParticlesCanvas: View {
    let tick: Double
    var body: some View {
        Canvas { ctx, size in
            for i in 0..<30 {
                let seed = Double(i)*111.3
                let phase = fmod(tick*(0.25+fmod(seed*0.009,0.3))+seed*0.6, 1.0)
                let x = (sin(seed*0.47+tick*0.12)*0.5+0.5)*size.width
                let y = (1.0-phase)*(size.height+40)-20
                let s = CGFloat(2.5+sin(seed*1.7+tick)*1.5)
                let fade = sin(phase*Double.pi)
                let shimmer = sin(tick*4.0+seed)*0.5+0.5
                ctx.opacity = fade*0.85
                ctx.fill(Path(ellipseIn: CGRect(x:x-s,y:y-s,width:s*2,height:s*2)),
                         with: .color(Color(red:1.0,green:0.82+shimmer*0.1,blue:0.2)))
                let glowR = s*3.5; ctx.opacity = fade*0.18
                ctx.fill(Path(ellipseIn: CGRect(x:x-glowR,y:y-glowR,width:glowR*2,height:glowR*2)),
                         with: .color(Color(red:1.0,green:0.9,blue:0.4)))
            }
        }
        .allowsHitTesting(false).ignoresSafeArea().blendMode(.screen)
    }
}
private struct SakuraGoldParticlesFallback: View {
    let tick: Double
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<20, id: \.self) { i in
                    let seed = Double(i)*111.3
                    let phase = CGFloat(fmod(tick*0.3+seed*0.6,1.0))
                    let x = CGFloat(sin(seed*0.47+tick*0.12)*0.5+0.5)*geo.size.width
                    let y = (1.0-phase)*(geo.size.height+40)-20
                    let s = CGFloat(2.5+sin(seed*1.7+tick)*1.5)
                    Circle().fill(Color(red:1.0,green:0.85,blue:0.25))
                        .frame(width:s*2,height:s*2).position(x:x,y:y)
                        .opacity(Double(sin(phase*CGFloat.pi))*0.85)
                }
            }
        }
        .blendMode(.screen).allowsHitTesting(false).ignoresSafeArea()
    }
}

// MARK: - 動態背景
// iOS 15+ 將所有霧氣合併成單一非同步 Canvas，避免數十個模糊圖層各自重繪。
struct AnimatedBackgroundView: View {
    var themeColors: [Color]; var primaryColor: Color
    var theme: DashboardTheme
    var body: some View {
        if #available(iOS 15.0, *) {
            AnimatedBackgroundCanvas(
                themeColors: themeColors,
                primaryColor: primaryColor,
                theme: theme
            )
        } else {
            AnimatedBackgroundFallback(
                themeColors: themeColors,
                primaryColor: primaryColor,
                theme: theme
            )
        }
    }
}

@available(iOS 15.0, *)
private struct AnimatedBackgroundCanvas: View {
    let themeColors: [Color]
    let primaryColor: Color
    let theme: DashboardTheme
    @Environment(\.scenePhase) private var scenePhase

    private var fogColor: Color {
        switch theme {
        case .skull: return Color(red: 0.85, green: 0.0, blue: 0.05)
        case .cyberpunk: return .safeCyan
        case .sakura: return Color(red: 1.0, green: 0.3, blue: 0.5)
        }
    }

    var body: some View {
        TimelineView(.animation(paused: scenePhase != .active)) { timeline in
            let tick = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(
                    colors: themeColors,
                    startPoint: UnitPoint(x: 0.5 + CGFloat(sin(tick * 0.15)) * 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5 + CGFloat(cos(tick * 0.12)) * 0.5, y: 1)
                )
                Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: 20))
                        for i in 0..<12 {
                            let seed = Double(i) * 137.5
                            let phase = tick * 0.32 + seed
                            let x = CGFloat(sin(phase * 0.31 + seed * 0.07) * 0.5 + 0.5) * size.width
                            let y = CGFloat(cos(phase * 0.19 + seed * 0.11) * 0.5 + 0.5) * size.height
                            let radius = CGFloat(70 + sin(phase * 0.5 + seed) * 34)
                            layer.opacity = 0.045 + abs(sin(phase * 0.27 + seed * 0.3)) * 0.09
                            layer.fill(
                                Path(ellipseIn: CGRect(x: x-radius, y: y-radius, width: radius*2, height: radius*2)),
                                with: .color(i < 4 ? primaryColor : fogColor)
                            )
                        }
                    }
                }
                .blendMode(.screen)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct AnimatedBackgroundFallback: View {
    let themeColors: [Color]
    let primaryColor: Color
    let theme: DashboardTheme
    @StateObject private var clock = AnimationClock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            LinearGradient(
                colors: themeColors,
                startPoint: UnitPoint(x:0.5+CGFloat(sin(clock.tick*0.15))*0.5, y:0),
                endPoint: UnitPoint(x:0.5+CGFloat(cos(clock.tick*0.12))*0.5, y:1)
            )
            switch theme {
            case .skull: SkullBloodFogView(tick: clock.tick)
            case .cyberpunk: CyberpunkFogView(tick: clock.tick)
            case .sakura: SakuraFogView(tick: clock.tick)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if scenePhase == .active { clock.start() }
        }
        .onDisappear { clock.stop() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { clock.start() }
            else { clock.stop() }
        }
    }
}

// MARK: - 語音播報
class SpeechManager: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var currentLanguage: String = "zh-TW" {
        didSet { UserDefaults.standard.set(currentLanguage, forKey: "AppLanguage") }
    }
    init() { if let s = UserDefaults.standard.string(forKey: "AppLanguage") { currentLanguage = s } }
    func speak(_ text: String) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: currentLanguage)
        u.rate = 0.52; u.pitchMultiplier = 1.0; synthesizer.speak(u)
    }
    func announceWarning(speedLimit: Int, isOverspeed: Bool) {
        let text: String
        if currentLanguage.starts(with: "zh") {
            text = isOverspeed ? "注意，您已超速！前方速限 \(speedLimit) 公里" : "前方速限 \(speedLimit) 公里"
        } else {
            text = isOverspeed ? "Warning! Speed limit \(speedLimit). You are speeding!" : "Speed limit \(speedLimit)."
        }
        speak(text)
    }
}

// MARK: - GPS & 感應器管理器
class VehicleManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    @Published var speed: Double = 0.0
    @Published var maxSpeed: Double = 0.0
    @Published var tripDistance: Double = 0.0
    private(set) var heading: Double = 0.0
    private(set) var currentGForceX: Double = 0.0
    private(set) var currentGForceY: Double = 0.0
    private(set) var maxGForce: Double = 0.0
    @Published var zeroToOneHundredTime: Double = 0.0
    @Published var isTesting0_100: Bool = false
    private var accelStartTime: Date? = nil
    private var hasReached100: Bool = false
    @Published var zeroTo100mTime: Double = 0.0
    @Published var isTesting0_100m: Bool = false
    private var distanceStartTime: Date? = nil
    private var startLocationFor100m: CLLocation? = nil
    private var hasReached100m: Bool = false
    private(set) var harshAccelerationCount: Int = 0
    private(set) var harshBrakingCount: Int = 0
    var overspeedDurationSeconds: Double = 0.0
    private var lastRecordedSpeed: Double = 0.0
    @Published var currentLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isNavigating: Bool = false
    @Published var routePolyline: MKPolyline? = nil
    @Published var currentInstruction: String = "搜尋目的地開始導航"
    @Published var distanceToNextStep: Double = 0.0
    @Published var destinationCoordinate: CLLocationCoordinate2D? = nil
    @Published var destinationName: String = ""
    @Published var nearestCameraAlert: String? = nil
    @Published var cameraAlertDistance: Double = UserDefaults.standard.object(forKey: "cameraAlertDistance") as? Double ?? 400
    @Published var directionFilteringEnabled: Bool = UserDefaults.standard.object(forKey: "directionFilteringEnabled") as? Bool ?? true
    @Published var transportMode: TransportMode = TransportMode(rawValue: UserDefaults.standard.string(forKey: "transportMode") ?? "汽車") ?? .car
    private(set) var recordedPath: [CLLocationCoordinate2D] = []
    @Published private(set) var speedCameras: [SpeedCamera] = [
        SpeedCamera(latitude: 25.0330, longitude: 121.5654, speedLimit: 50, description: "台北信義路固定測速"),
        SpeedCamera(latitude: 25.0400, longitude: 121.5700, speedLimit: 60, description: "台北忠孝東路固定測速")
    ]
    @Published var speechManager = SpeechManager()
    private var lastSpokenCameraId: UUID? = nil
    private var lastLocation: CLLocation? = nil
    private var lastRecordedPathLocation: CLLocation? = nil
    private var activeDirections: MKDirections?
    private var lastCloudFetch: Date = .distantPast
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 3.0
        locationManager.headingFilter = 1.0
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        startMotionUpdates()
        loadTemporaryCameras()
        OfficialCameraStore.shared.load { [weak self] cameras in
            guard let self, !cameras.isEmpty else { return }
            self.speedCameras = cameras + self.speedCameras.filter { $0.isTemporary && ($0.expiresAt ?? .distantFuture) > Date() }
            self.persistTemporaryCameras()
        }
    }
    func setTransportMode(_ mode: TransportMode) {
        transportMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "transportMode")
    }
    func setCameraAlertDistance(_ distance: Double) { cameraAlertDistance = distance; UserDefaults.standard.set(distance, forKey: "cameraAlertDistance") }
    func setDirectionFiltering(_ enabled: Bool) { directionFilteringEnabled = enabled; UserDefaults.standard.set(enabled, forKey: "directionFilteringEnabled") }
    private func loadTemporaryCameras() {
        guard let data = UserDefaults.standard.data(forKey: "temporary-speed-cameras-v2"), let saved = try? JSONDecoder().decode([SpeedCamera].self, from: data) else { return }
        speedCameras.append(contentsOf: saved.filter { $0.isTemporary && ($0.expiresAt ?? .distantFuture) > Date() })
    }
    private func persistTemporaryCameras() {
        let active = speedCameras.filter { $0.isTemporary && ($0.expiresAt ?? .distantFuture) > Date() }
        if let data = try? JSONEncoder().encode(active) { UserDefaults.standard.set(data, forKey: "temporary-speed-cameras-v2") }
    }
    func updateLocationAccuracy(isNetworkBoostEnabled: Bool) {
        locationManager.desiredAccuracy = isNetworkBoostEnabled ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyBest
        locationManager.distanceFilter = isNetworkBoostEnabled ? 1.0 : 3.0
    }
    func resetData() {
        tripDistance = 0; maxSpeed = 0; maxGForce = 0
        zeroToOneHundredTime = 0; isTesting0_100 = false; hasReached100 = false; accelStartTime = nil
        zeroTo100mTime = 0; isTesting0_100m = false; hasReached100m = false
        distanceStartTime = nil; startLocationFor100m = nil
        lastLocation = nil; lastRecordedPathLocation = nil
        recordedPath.removeAll(keepingCapacity: true); lastSpokenCameraId = nil
        harshAccelerationCount = 0; harshBrakingCount = 0
        overspeedDurationSeconds = 0; lastRecordedSpeed = 0
    }
func addCurrentLocationAsCamera(speedLimit: Double, description: String) {
        let cam = SpeedCamera(
        latitude: currentLocation.latitude,
        longitude: currentLocation.longitude,
        speedLimit: speedLimit,
        description: description.isEmpty ? "手動回報測速點" : description,
            isTemporary: true, expiresAt: Date().addingTimeInterval(3 * 60 * 60)
    )

        speedCameras.append(cam)
        persistTemporaryCameras()
    nearestCameraAlert = "已成功加入目前測速點！"
    AudioServicesPlaySystemSound(1016)
    speechManager.speak("已成功加入目前測速點")
}
    func removeNearestCamera() {
        guard let loc = lastLocation else { speechManager.speak("目前沒有定位資訊"); return }
        if let idx = speedCameras.firstIndex(where: {
            loc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= 150
        }) {
            let removed = speedCameras.remove(at: idx)
            persistTemporaryCameras()
            nearestCameraAlert = "已移除最近測速點：\(removed.description)"
            AudioServicesPlaySystemSound(1016); speechManager.speak("已移除最近測速點")
        } else {
            nearestCameraAlert = "附近 150 公尺內沒有測速點可移除"
            speechManager.speak("附近沒有找到可移除的測速點")
        }
    }
    func setDestination(_ coordinate: CLLocationCoordinate2D, name: String = "") {
        destinationCoordinate = coordinate; destinationName = name; isNavigating = true
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        req.transportType = .automobile
        activeDirections?.cancel()
        let directions = MKDirections(request: req)
        activeDirections = directions
        directions.calculate { [weak self] resp, _ in
            DispatchQueue.main.async {
                guard let self = self, self.activeDirections === directions else { return }
                self.activeDirections = nil
                guard let route = resp?.routes.first else {
                    self.currentInstruction = "路線計算失敗"
                    return
                }
                self.routePolyline = route.polyline
                if let step = route.steps.first(where: { !$0.instructions.isEmpty }) {
                    self.currentInstruction = step.instructions
                    self.distanceToNextStep = step.distance
                }
            }
        }
        speechManager.speak(name.isEmpty ? "開始導航" : "導航至 \(name)")
    }
    func cancelNavigation() {
        activeDirections?.cancel(); activeDirections = nil
        isNavigating = false; routePolyline = nil; destinationCoordinate = nil
        destinationName = ""; currentInstruction = "搜尋目的地開始導航"; distanceToNextStep = 0
        speechManager.speak("導航已結束")
    }
    private func startMotionUpdates() {
        guard motionManager.isAccelerometerAvailable, !motionManager.isAccelerometerActive else { return }
        motionManager.accelerometerUpdateInterval = 0.2
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let acc = data?.acceleration else { return }
            self.currentGForceX = acc.x; self.currentGForceY = acc.y
            let g = sqrt(acc.x*acc.x+acc.y*acc.y)
            if g > self.maxGForce { self.maxGForce = g }
        }
    }
    func setMotionUpdatesActive(_ isActive: Bool) {
        if isActive { startMotionUpdates() }
        else { motionManager.stopAccelerometerUpdates() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last,
              loc.horizontalAccuracy >= 0,
              loc.horizontalAccuracy <= 100 else { return }

        let displayedLocation = CLLocation(latitude: currentLocation.latitude, longitude: currentLocation.longitude)
        if displayedLocation.distance(from: loc) >= 1.0 {
            currentLocation = loc.coordinate
        }
        if lastRecordedPathLocation == nil || loc.distance(from: lastRecordedPathLocation!) >= 3.0 {
            if recordedPath.count >= 20_000 {
                recordedPath = recordedPath.enumerated().compactMap { index, coordinate in
                    index.isMultiple(of: 2) ? coordinate : nil
                }
            }
            recordedPath.append(loc.coordinate)
            lastRecordedPathLocation = loc
        }

        let kmh = max(0, loc.speed*3.6)
        if abs(speed - kmh) >= 0.1 { speed = kmh }
        let delta = kmh - lastRecordedSpeed
        if delta > 18 { harshAccelerationCount += 1 } else if delta < -18 { harshBrakingCount += 1 }
        lastRecordedSpeed = kmh
        checkSpeedCameras(currentLoc: loc, currentSpeed: kmh)
        if kmh > maxSpeed { maxSpeed = kmh }
        if let last = lastLocation {
            let d = loc.distance(from: last)
            if d >= 1.0 && d <= 1_000 { tripDistance += d/1000.0 }
        }
        lastLocation = loc

        if kmh < 5 && !isTesting0_100 && !hasReached100 {
            isTesting0_100 = true; accelStartTime = Date(); zeroToOneHundredTime = 0
        } else if isTesting0_100, let t = accelStartTime {
            zeroToOneHundredTime = Date().timeIntervalSince(t)
            if kmh >= 100 { isTesting0_100 = false; hasReached100 = true }
            else if zeroToOneHundredTime > 30 { isTesting0_100 = false }
        }
        if kmh < 3 && !isTesting0_100m && !hasReached100m {
            isTesting0_100m = true; distanceStartTime = Date(); startLocationFor100m = loc; zeroTo100mTime = 0
        } else if isTesting0_100m, let sl = startLocationFor100m, let st = distanceStartTime {
            zeroTo100mTime = Date().timeIntervalSince(st)
            if loc.distance(from: sl) >= 100 { isTesting0_100m = false; hasReached100m = true }
            else if zeroTo100mTime > 30 { isTesting0_100m = false }
        }
    }
    private func checkSpeedCameras(currentLoc: CLLocation, currentSpeed: Double) {
        speedCameras.removeAll { $0.isTemporary && ($0.expiresAt ?? .distantPast) <= Date() }
        persistTemporaryCameras()
        for cam in speedCameras {
            if transportMode == .bicycle && cam.speedLimit > 60 { continue }
            let camLoc = CLLocation(latitude: cam.latitude, longitude: cam.longitude)
            let dist = currentLoc.distance(from: camLoc)
            if directionFilteringEnabled && heading >= 0 {
                let bearing = currentLoc.course >= 0 ? currentLoc.course : heading
                let target = bearingTo(currentLoc.coordinate, cam.coordinate)
                let delta = abs(((target - bearing + 540).truncatingRemainder(dividingBy: 360)) - 180)
                if delta > 75 { continue }
            }
            if dist <= cameraAlertDistance {
                nearestCameraAlert = "\(cam.description) 剩 \(Int(dist))m (速限 \(Int(cam.speedLimit))km)"
                if dist <= 300, lastSpokenCameraId != cam.id {
                    lastSpokenCameraId = cam.id
                    speechManager.announceWarning(speedLimit: Int(cam.speedLimit), isOverspeed: currentSpeed > cam.speedLimit)
                    if currentSpeed > cam.speedLimit { AudioServicesPlaySystemSound(1007) }
                }
                return
            }
        }
        if let id = lastSpokenCameraId, let cam = speedCameras.first(where: { $0.id == id }) {
            if currentLoc.distance(from: CLLocation(latitude: cam.latitude, longitude: cam.longitude)) > 500 {
                lastSpokenCameraId = nil
            }
        }
        if nearestCameraAlert?.contains("已成功") == false && nearestCameraAlert?.contains("已移除") == false {
            nearestCameraAlert = nil
        }
    }
    private func bearingTo(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Double {
        let p1 = from.latitude * .pi / 180, p2 = to.latitude * .pi / 180
        let dl = (to.longitude - from.longitude) * .pi / 180
        return (atan2(sin(dl) * cos(p2), cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        heading = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}

// MARK: - 骷髏開場粒子
private struct SkullBootParticles: View {
    let progress: CGFloat
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<48, id: \.self) { i in
                    let angle = Double(i)*(Double.pi*2.0/48.0)
                    let baseR = 50.0+Double(i%5)*30.0
                    let r = CGFloat(baseR)+progress*CGFloat(130+(i%4)*50)
                    let x = geo.size.width/2+CGFloat(cos(angle))*r
                    let y = geo.size.height/2+CGFloat(sin(angle))*r
                    let fade = max(0.0, 1.0-Double(progress)*1.4)
                    let sz = CGFloat(2.0+Double(i%4))
                    Circle().fill(i%3==0 ? Color.white : Color.red)
                        .frame(width:sz*2,height:sz*2).position(x:x,y:y).opacity(fade*0.9)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 賽伯全息掃描框
private struct CyberHoloScanFrame: View {
    let progress: CGFloat; let color: Color
    var body: some View {
        if #available(iOS 15.0, *) { CyberHoloScanFrameCanvas(progress: progress, color: color) }
        else { CyberHoloScanFrameFallback(progress: progress, color: color) }
    }
}
@available(iOS 15.0, *)
private struct CyberHoloScanFrameCanvas: View {
    let progress: CGFloat; let color: Color
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width; let h = geo.size.height
            Canvas { ctx, size in
                let corners: [(CGPoint,CGPoint,CGPoint)] = [
                    (CGPoint(x:0,y:0),CGPoint(x:60,y:0),CGPoint(x:0,y:60)),
                    (CGPoint(x:w,y:0),CGPoint(x:w-60,y:0),CGPoint(x:w,y:60)),
                    (CGPoint(x:0,y:h),CGPoint(x:60,y:h),CGPoint(x:0,y:h-60)),
                    (CGPoint(x:w,y:h),CGPoint(x:w-60,y:h),CGPoint(x:w,y:h-60))
                ]
                for (pivot,e1,e2) in corners {
                    var p = Path(); p.move(to:e1); p.addLine(to:pivot); p.addLine(to:e2)
                    ctx.opacity = 0.9
                    ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth:2.5, lineCap:.square))
                }
                let scanY = h*CGFloat(progress)
                var sp = Path(); sp.move(to: CGPoint(x:0,y:scanY)); sp.addLine(to: CGPoint(x:w,y:scanY))
                ctx.opacity = 0.7*Double(1.0-abs(progress-0.5)*2)
                ctx.stroke(sp, with: .color(color), style: StrokeStyle(lineWidth:1.5))
                ctx.opacity = 0.15
                ctx.fill(Path(CGRect(x:0,y:scanY-30,width:w,height:30)), with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }
}
private struct CyberHoloScanFrameFallback: View {
    let progress: CGFloat; let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    let isRight = i%2==1; let isBottom = i>=2
                    VStack(spacing:0) {
                        if isBottom { Spacer() }
                        HStack(spacing:0) {
                            if isRight { Spacer() }
                            Path { p in
                                p.move(to: .zero)
                                p.addLine(to: CGPoint(x: isRight ? -55 : 55, y: 0))
                                p.move(to: .zero)
                                p.addLine(to: CGPoint(x: 0, y: isBottom ? -55 : 55))
                            }.stroke(color, lineWidth:2.5).frame(width:60,height:60)
                            if !isRight { Spacer() }
                        }
                        if !isBottom { Spacer() }
                    }
                }
                Rectangle().fill(color.opacity(0.5)).frame(height:2)
                    .position(x: geo.size.width/2, y: geo.size.height*progress)
                    .opacity(0.7*Double(1.0-abs(progress-0.5)*2))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 掃描線
private struct ScanlineOverlay: View {
    let color: Color; let offset: CGFloat
    var body: some View {
        if #available(iOS 15.0, *) { ScanlineCanvas(color:color, offset:offset) }
        else { ScanlineFallback(color:color, offset:offset) }
    }
}
@available(iOS 15.0, *)
private struct ScanlineCanvas: View {
    let color: Color; let offset: CGFloat
    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                let spacing: CGFloat = 8
                var y = (offset*size.height).truncatingRemainder(dividingBy: spacing)
                while y < size.height {
                    var line = Path(); line.move(to: CGPoint(x:0,y:y)); line.addLine(to: CGPoint(x:size.width,y:y))
                    ctx.opacity = 0.04
                    ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth:1))
                    y += spacing
                }
            }
        }
        .blendMode(.screen).allowsHitTesting(false).ignoresSafeArea()
    }
}
private struct ScanlineFallback: View {
    let color: Color; let offset: CGFloat
    var body: some View {
        GeometryReader { geo in
            VStack(spacing:0) {
                ForEach(0..<60, id: \.self) { _ in
                    Rectangle().fill(color.opacity(0.035)).frame(height:1)
                    Spacer(minLength:7)
                }
            }
            .offset(y: offset*geo.size.height)
        }
        .blendMode(.screen).allowsHitTesting(false).ignoresSafeArea()
    }
}

// MARK: - 賽車速度線
private struct RacingSpeedLines: View {
    let color: Color; let progress: CGFloat; let intensity: CGFloat
    struct SpeedLine: Identifiable {
        let id: Int; let x: CGFloat; let y: CGFloat; let length: CGFloat; let thickness: CGFloat; let delay: CGFloat
    }
    static func makeLines() -> [SpeedLine] {
        var result: [SpeedLine] = []
        for i in 0..<28 {
            let xVal: CGFloat   = CGFloat((i*37)%100)/100.0
            let yVal: CGFloat   = CGFloat((i*61)%100)/100.0
            let lenVal: CGFloat = CGFloat(60+(i*29)%130)
            let thkVal: CGFloat = CGFloat(1+i%3)
            let dlyVal: CGFloat = CGFloat((i*17)%100)/100.0
            result.append(SpeedLine(id:i,x:xVal,y:yVal,length:lenVal,thickness:thkVal,delay:dlyVal))
        }
        return result
    }
    private let lines = RacingSpeedLines.makeLines()
    var body: some View {
        if #available(iOS 15.0, *) { RacingSpeedLinesCanvas(color:color,progress:progress,intensity:intensity,lines:lines) }
        else { RacingSpeedLinesFallback(color:color,progress:progress,intensity:intensity,lines:lines) }
    }
}
@available(iOS 15.0, *)
private struct RacingSpeedLinesCanvas: View {
    let color: Color; let progress: CGFloat; let intensity: CGFloat
    let lines: [RacingSpeedLines.SpeedLine]
    var body: some View {
        Canvas { ctx, size in
            for line in lines {
                let x = size.width*line.x
                let y = size.height*(line.y+progress*(0.25+line.delay*0.35))
                var path = Path(); path.move(to: CGPoint(x:x,y:y))
                path.addLine(to: CGPoint(x:x+line.length,y:y+line.length*0.14))
                ctx.opacity = Double(0.55*intensity)
                ctx.stroke(path, with: .linearGradient(Gradient(colors:[.clear,color.opacity(0.85),.clear]),
                    startPoint:CGPoint(x:x,y:y),endPoint:CGPoint(x:x+line.length,y:y)),
                    style:StrokeStyle(lineWidth:line.thickness))
            }
        }
        .clipped().allowsHitTesting(false)
    }
}
private struct RacingSpeedLinesFallback: View {
    let color: Color; let progress: CGFloat; let intensity: CGFloat
    let lines: [RacingSpeedLines.SpeedLine]
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(lines) { line in
                    Rectangle()
                        .fill(LinearGradient(colors:[.clear,color.opacity(0.85*Double(intensity)),.clear],startPoint:.leading,endPoint:.trailing))
                        .frame(width:line.length,height:line.thickness)
                        .position(x:geo.size.width*line.x,y:geo.size.height*(line.y+progress*(0.25+line.delay*0.35)))
                        .rotationEffect(.degrees(-8))
                }
            }
        }
        .clipped().allowsHitTesting(false)
    }
}

// MARK: - 統一警告語結尾面板
private struct JapaneseWarningEndView: View {
    let themeColor: Color
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.red).frame(height: 6)
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Rectangle().fill(Color.red).frame(width: 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("危険　警告")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.red).kerning(6)
                        Text("超速度走行は厳禁です")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white).kerning(2)
                        Text("OVER SPEED IS STRICTLY PROHIBITED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4)).kerning(1)
                    }
                    Spacer()
                    VStack(spacing: 4) {
                        Text("⚠").font(.system(size: 28))
                        Text("速").font(.system(size: 11, weight: .black, design: .rounded)).foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16)
                HStack(spacing: 0) {
                    ForEach(["走行注意","安全第一","速度遵守","法規厳守"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .frame(maxWidth: .infinity)
                        if label != "法規厳守" {
                            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 20)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
            }
            .background(Color.black.opacity(0.92))
            Rectangle().fill(Color.red).frame(height: 6)
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.red.opacity(0.7), lineWidth: 1))
        .shadow(color: .red.opacity(0.6), radius: 20)
    }
}

// MARK: - 開場動畫
struct MultiThemeBootLoadingView: View {
    @Binding var isFinished: Bool
    @Binding var selectedTheme: DashboardTheme
    @State private var bootStep = 0
    @State private var rotation: Double = 0
    @State private var speed: CGFloat = 0
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var logoBlur: CGFloat = 16
    @State private var flashOpacity: Double = 0
    @State private var shake: CGFloat = 0
    @State private var ringScale: CGFloat = 0.3
    @State private var ringOpacity: Double = 0
    @State private var scanOffset: CGFloat = 0
    @State private var pulse = false
    @State private var particleProgress: CGFloat = 0
    @State private var showParticles = false
    @State private var didStart = false
    @State private var glitchOffset: CGFloat = 0
    @State private var matrixOpacity: Double = 0
    @State private var holoScanProgress: CGFloat = 0
    @State private var textReveal: Double = 0
    @State private var ringPulse: CGFloat = 1.0
    @State private var goldBurst: Double = 0
    @State private var showWarningEnd = false
    @State private var warningEndOpacity: Double = 0
    @State private var crackOpacity: Double = 0
    @State private var bloodDripProgress: CGFloat = 0
    @State private var circuitOpacity: Double = 0
    @State private var dataStreamOffset: CGFloat = 0
    @State private var petalBurst: Double = 0
    @State private var toriiOpacity: Double = 0

    private var themeColor: Color {
        switch selectedTheme {
        case .skull:     return .red
        case .cyberpunk: return .safeCyan
        case .sakura:    return Color(red:1.0,green:0.3,blue:0.4)
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                switch selectedTheme {
                case .skull:     skullBoot(in: geo.size)
                case .cyberpunk: cyberBoot(in: geo.size)
                case .sakura:    sakuraBoot(in: geo.size)
                }
                ScanlineOverlay(color: themeColor, offset: scanOffset).opacity(0.45).allowsHitTesting(false)
                if flashOpacity > 0 {
                    Rectangle().fill(Color.white).opacity(flashOpacity).ignoresSafeArea().allowsHitTesting(false)
                }
                if showParticles {
                    BootParticlesView(color: themeColor, progress: particleProgress).allowsHitTesting(false)
                }
                if showWarningEnd {
                    VStack {
                        Spacer()
                        JapaneseWarningEndView(themeColor: themeColor)
                            .padding(.horizontal, 20)
                            .padding(.bottom, geo.size.height * 0.2)
                            .opacity(warningEndOpacity)
                    }
                    .zIndex(80)
                }
                VStack {
                    HStack {
                        Spacer()
                        Button("SKIP") { finishBoot() }
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.black.opacity(0.5)).cornerRadius(8)
                            .padding(.top, 18).padding(.trailing, 18)
                    }
                    Spacer()
                }
            }
            .offset(x: shake)
            .onAppear {
                guard !didStart else { return }
                didStart = true; startBoot()
            }
        }
    }

    @ViewBuilder
    private func skullBoot(in size: CGSize) -> some View {
        ZStack {
            RadialGradient(gradient: Gradient(colors: [
                Color(red:0.4,green:0,blue:0).opacity(0.9), Color(red:0.15,green:0,blue:0), Color.black]),
                center: .center, startRadius: 10, endRadius: max(size.width,size.height))
            .ignoresSafeArea()
            if crackOpacity > 0 {
                GeometryReader { geo in
                    ZStack {
                        ForEach(0..<8, id: \.self) { i in
                            let angle = Double(i)*45.0*Double.pi/180.0
                            let len = CGFloat(60+i*20)
                            Path { p in
                                p.move(to: CGPoint(x: geo.size.width/2, y: geo.size.height/2))
                                p.addLine(to: CGPoint(x: geo.size.width/2+CGFloat(cos(angle))*len,
                                                      y: geo.size.height/2+CGFloat(sin(angle))*len))
                                let branchAngle = angle+Double(i%2==0 ? 1 : -1)*0.4
                                p.addLine(to: CGPoint(x: geo.size.width/2+CGFloat(cos(angle))*len+CGFloat(cos(branchAngle))*25,
                                                      y: geo.size.height/2+CGFloat(sin(angle))*len+CGFloat(sin(branchAngle))*25))
                            }
                            .stroke(Color.red.opacity(0.7), lineWidth: CGFloat(2-i%2))
                        }
                    }
                }
                .opacity(crackOpacity).allowsHitTesting(false)
            }
            if bloodDripProgress > 0 {
                GeometryReader { geo in
                    ForEach(0..<6, id: \.self) { i in
                        let xPos = geo.size.width*CGFloat([0.2,0.35,0.5,0.62,0.75,0.88][i])
                        let dripLen = CGFloat(40+i*15)*bloodDripProgress
                        Path { p in
                            p.move(to: CGPoint(x: xPos, y: 0))
                            p.addLine(to: CGPoint(x: xPos, y: dripLen))
                        }
                        .stroke(LinearGradient(colors: [Color.red.opacity(0.8),Color.red.opacity(0)],
                            startPoint:.top,endPoint:.bottom), lineWidth: CGFloat(2+i%3))
                        .opacity(0.7)
                    }
                }
                .allowsHitTesting(false)
            }
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(AngularGradient(gradient: Gradient(colors:[.clear,.red,Color(red:1,green:0.7,blue:0.7),.red,.clear]),center:.center),
                            lineWidth: CGFloat(3-i))
                    .frame(width:CGFloat(320+i*30),height:CGFloat(320+i*30))
                    .rotationEffect(.degrees(rotation*(i==0 ? 1 : -0.7)))
                    .opacity(0.65-Double(i)*0.15)
            }
            Circle()
                .fill(RadialGradient(gradient:Gradient(colors:[Color.red.opacity(0.3),.clear]),
                                     center:.center,startRadius:0,endRadius:130))
                .frame(width:260,height:260).scaleEffect(ringPulse)
            ZStack {
                Image(systemName:"skull.fill")
                    .font(.system(size:min(size.width,size.height)*0.22,weight:.black))
                    .foregroundColor(Color.red.opacity(0.4)).blur(radius:20)
                Image(systemName:"skull.fill")
                    .font(.system(size:min(size.width,size.height)*0.22,weight:.black))
                    .foregroundColor(.white)
                    .shadow(color:.red,radius:18)
                    .shadow(color:Color(red:1,green:0.3,blue:0.3).opacity(0.5),radius:35)
            }
            .scaleEffect(logoScale).opacity(logoOpacity).blur(radius:logoBlur).offset(x:glitchOffset)
            VStack(spacing:6) {
                Spacer().frame(height:min(size.width,size.height)*0.44)
                Text("CHEN").font(.system(size:42,weight:.black,design:.rounded))
                    .kerning(10).foregroundColor(.white).shadow(color:.red,radius:10).opacity(textReveal)
                Text("SYSTEM ONLINE").font(.system(size:11,weight:.bold,design:.monospaced))
                    .kerning(5).foregroundColor(Color.red.opacity(0.9)).opacity(textReveal*0.9)
                Text("極限走行モード起動").font(.system(size:10,weight:.bold,design:.rounded))
                    .kerning(2).foregroundColor(Color.red.opacity(0.7)).opacity(textReveal*0.75)
            }
        }
    }

    @ViewBuilder
    private func cyberBoot(in size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors:[Color(red:0.0,green:0.05,blue:0.18),Color.black],
                           startPoint:.top,endPoint:.bottom).ignoresSafeArea()
            if circuitOpacity > 0 {
                GeometryReader { geo in
                    ZStack {
                        ForEach(0..<12, id: \.self) { i in
                            let startX = CGFloat((i*73)%100)/100*geo.size.width
                            let startY = CGFloat((i*47)%100)/100*geo.size.height
                            Path { p in
                                p.move(to: CGPoint(x:startX,y:startY))
                                p.addLine(to: CGPoint(x:startX+CGFloat((i%3+1)*40),y:startY))
                                p.addLine(to: CGPoint(x:startX+CGFloat((i%3+1)*40),y:startY+CGFloat((i%4+1)*30)))
                                p.addLine(to: CGPoint(x:startX+CGFloat((i%3+1)*40+20),y:startY+CGFloat((i%4+1)*30)))
                            }
                            .stroke(Color.safeCyan.opacity(0.25),lineWidth:0.8)
                            Circle().fill(Color.safeCyan.opacity(0.5)).frame(width:4,height:4)
                                .position(x:startX+CGFloat((i%3+1)*40+20),y:startY+CGFloat((i%4+1)*30))
                        }
                    }
                }
                .opacity(circuitOpacity).allowsHitTesting(false)
            }
            GeometryReader { geo in
                ForEach(0..<4, id: \.self) { i in
                    let yPos = geo.size.height*CGFloat([0.25,0.42,0.58,0.75][i])
                    Rectangle()
                        .fill(LinearGradient(colors:[.clear,Color.safeCyan.opacity(0.6),.clear],
                            startPoint:.leading,endPoint:.trailing))
                        .frame(width:geo.size.width*0.6,height:1.5)
                        .position(x:geo.size.width*(dataStreamOffset+CGFloat(i)*0.15).truncatingRemainder(dividingBy:1.0),y:yPos)
                        .opacity(matrixOpacity*0.5)
                }
            }
            .allowsHitTesting(false)
            CyberpunkMatrixRainView(tick:Double(speed)*3.0).opacity(matrixOpacity*0.6)
            CyberHoloScanFrame(progress:holoScanProgress,color:.safeCyan).opacity(0.85)
            RoundedRectangle(cornerRadius:20)
                .stroke(LinearGradient(colors:[Color.safeCyan.opacity(0.8),Color.white.opacity(0.3),Color.safeCyan.opacity(0.8)],
                    startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1.5)
                .frame(width:min(size.width*0.82,420),height:min(size.height*0.5,390))
                .opacity(logoOpacity)
            VStack(spacing:16) {
                Text("CHEN // DRIVE").font(.system(size:32,weight:.black,design:.monospaced))
                    .kerning(3).foregroundColor(.safeCyan)
                    .shadow(color:.safeCyan,radius:10).shadow(color:.safeCyan.opacity(0.3),radius:20)
                    .offset(x:glitchOffset*0.4).opacity(textReveal)
                HStack(spacing:12) {
                    ForEach(["GPS:ON","RADAR:ON","AI:BOOT","NET:OK"],id:\.self) { item in
                        Text(item).font(.system(size:8,weight:.bold,design:.monospaced)).foregroundColor(.safeCyan)
                            .padding(.horizontal,7).padding(.vertical,4)
                            .background(Color.safeCyan.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius:4).stroke(Color.safeCyan.opacity(0.4),lineWidth:0.8))
                            .cornerRadius(4)
                    }
                }
                .opacity(textReveal*0.9)
                Rectangle()
                    .fill(LinearGradient(colors:[.clear,.safeCyan,.clear],startPoint:.leading,endPoint:.trailing))
                    .frame(width:min(size.width*0.55,260),height:1).opacity(textReveal*0.7)
                Text("NEURAL VEHICLE INTERFACE").font(.system(size:9,weight:.bold,design:.monospaced))
                    .kerning(3).foregroundColor(.white.opacity(0.5)).opacity(textReveal*0.8)
                Text("神経接続完了　走行開始").font(.system(size:10,weight:.bold,design:.rounded))
                    .kerning(2).foregroundColor(Color.safeCyan.opacity(0.65)).opacity(textReveal*0.7)
                ZStack(alignment:.leading) {
                    RoundedRectangle(cornerRadius:2).fill(Color.white.opacity(0.1))
                        .frame(width:min(size.width*0.55,260),height:2)
                    RoundedRectangle(cornerRadius:2)
                        .fill(LinearGradient(colors:[.safeCyan,.white],startPoint:.leading,endPoint:.trailing))
                        .frame(width:min(size.width*0.55,260)*speed,height:2)
                        .shadow(color:.safeCyan,radius:4)
                }
                .opacity(textReveal*0.9)
            }
            .scaleEffect(logoScale).opacity(logoOpacity).blur(radius:logoBlur)
        }
    }

    @ViewBuilder
    private func sakuraBoot(in size: CGSize) -> some View {
        ZStack {
            RadialGradient(gradient:Gradient(colors:[Color(red:0.18,green:0.0,blue:0.03).opacity(0.9),Color.black]),
                center:.center,startRadius:20,endRadius:max(size.width,size.height))
            .ignoresSafeArea()
            RacingSpeedLines(color:.red,progress:speed,intensity:bootStep>=2 ? 0.9 : 0.35)
            if toriiOpacity > 0 {
                GeometryReader { geo in
                    let cx=geo.size.width/2; let cy=geo.size.height*0.42
                    let w:CGFloat=160; let h:CGFloat=180
                    ZStack {
                        Path { p in
                            p.move(to:CGPoint(x:cx-w/2-15,y:cy-h/2)); p.addLine(to:CGPoint(x:cx+w/2+15,y:cy-h/2))
                            p.move(to:CGPoint(x:cx-w/2,y:cy-h/2+22)); p.addLine(to:CGPoint(x:cx+w/2,y:cy-h/2+22))
                            p.move(to:CGPoint(x:cx-w/2+12,y:cy-h/2+22)); p.addLine(to:CGPoint(x:cx-w/2+12,y:cy+h/2))
                            p.move(to:CGPoint(x:cx+w/2-12,y:cy-h/2+22)); p.addLine(to:CGPoint(x:cx+w/2-12,y:cy+h/2))
                        }
                        .stroke(Color(red:0.9,green:0.1,blue:0.1).opacity(0.75),lineWidth:8)
                        Path { p in
                            p.move(to:CGPoint(x:cx-w/2-15,y:cy-h/2))
                            p.addQuadCurve(to:CGPoint(x:cx+w/2+15,y:cy-h/2),control:CGPoint(x:cx,y:cy-h/2-12))
                        }
                        .stroke(Color(red:0.9,green:0.1,blue:0.1).opacity(0.75),lineWidth:8)
                    }
                }
                .opacity(toriiOpacity).allowsHitTesting(false)
            }
            if petalBurst > 0 {
                GeometryReader { geo in
                    ForEach(0..<20, id: \.self) { i in
                        let seed = Double(i)*137.5
                        let angle = seed*0.11
                        let dist = CGFloat(60+i*18)*CGFloat(petalBurst)
                        let x = geo.size.width/2+dist*CGFloat(cos(angle))
                        let y = geo.size.height/2+dist*CGFloat(sin(angle))-CGFloat(i*8)*CGFloat(petalBurst)
                        let fade = max(0.0,1.0-petalBurst*0.7)
                        let petalR = CGFloat(i%3); let petalB = CGFloat(i%2)
                        let rotDeg = angle*180.0/Double.pi+Double(i)*25.0
                        Ellipse()
                            .fill(Color(red:1.0,green:0.4+petalR*0.1,blue:0.5+petalB*0.1))
                            .frame(width:10+petalR*4,height:7+petalB*3)
                            .rotationEffect(.degrees(rotDeg))
                            .position(x:x,y:y)
                            .opacity(Double(fade)*0.85)
                    }
                }
                .allowsHitTesting(false)
            }
            if goldBurst > 0 {
                ForEach(0..<3,id:\.self) { i in
                    Circle()
                        .stroke(Color(red:1,green:0.85,blue:0.3).opacity(max(0,0.6-goldBurst*0.8-Double(i)*0.15)),
                                lineWidth:CGFloat(3-i))
                        .frame(width:CGFloat(180+i*55)*CGFloat(goldBurst+0.2))
                        .opacity(max(0,1-goldBurst))
                }
            }
            if bootStep <= 1 {
                VStack(spacing:12) {
                    Text("極速").font(.system(size:72,weight:.black,design:.rounded))
                        .foregroundColor(.white).kerning(8)
                        .shadow(color:.red.opacity(0.8),radius:16)
                        .shadow(color:Color(red:1,green:0.8,blue:0.8).opacity(0.3),radius:30)
                    Rectangle().fill(LinearGradient(colors:[.clear,.red,.clear],startPoint:.leading,endPoint:.trailing))
                        .frame(width:200,height:2)
                    Text("超速走行禁止　危険").font(.system(size:12,weight:.bold,design:.rounded))
                        .foregroundColor(.red.opacity(0.9)).kerning(4)
                    Text("EXTREME SPEED ZONE").font(.system(size:9,weight:.bold,design:.monospaced))
                        .foregroundColor(.white.opacity(0.4)).kerning(3)
                }
                .padding(.horizontal,36).padding(.vertical,32)
                .background(ZStack {
                    RoundedRectangle(cornerRadius:14).fill(Color.black.opacity(0.88))
                    RoundedRectangle(cornerRadius:14).stroke(Color.red.opacity(pulse ? 0.9:0.3),lineWidth:pulse ? 2.5:1)
                    LinearGradient(colors:[Color.white.opacity(0.06),.clear],startPoint:.top,endPoint:.center)
                        .clipShape(RoundedRectangle(cornerRadius:14))
                })
                .scaleEffect(logoScale).opacity(logoOpacity).blur(radius:logoBlur)
            }
            if bootStep == 2 {
                ZStack {
                    ForEach(0..<2,id:\.self) { i in
                        Circle()
                            .stroke(AngularGradient(gradient:Gradient(colors:[.clear,Color(red:1,green:0.85,blue:0.3),.white,Color(red:1,green:0.85,blue:0.3),.clear]),center:.center),
                                    lineWidth:CGFloat(3-i))
                            .frame(width:CGFloat(min(size.width*0.65,330))+CGFloat(i)*22)
                            .rotationEffect(.degrees(rotation*(i==0 ? 1:-0.65)))
                            .opacity(0.75-Double(i)*0.2)
                    }
                    VStack(spacing:8) {
                        Text("極").font(.system(size:min(size.width,size.height)*0.28,weight:.black,design:.rounded))
                            .foregroundColor(.white).shadow(color:.red,radius:20)
                            .shadow(color:Color(red:1,green:0.85,blue:0.3).opacity(0.4),radius:40)
                        Text("EXTREME").font(.system(size:12,weight:.black,design:.monospaced))
                            .kerning(5).foregroundColor(Color(red:1,green:0.85,blue:0.3))
                    }
                    .scaleEffect(logoScale).opacity(logoOpacity).blur(radius:logoBlur)
                }
                VStack {
                    Spacer()
                    Text("CHEN").font(.system(size:32,weight:.black,design:.rounded))
                        .kerning(10).foregroundColor(.white).shadow(color:.red,radius:8)
                    Text("極限走行モード").font(.system(size:10,weight:.bold,design:.rounded))
                        .kerning(4).foregroundColor(.red).padding(.top,2).padding(.bottom,50)
                }
                .opacity(logoOpacity*Double(textReveal))
            }
            if bootStep >= 3 {
                VStack(spacing:12) {
                    Text("全系統起動").font(.system(size:34,weight:.black,design:.rounded))
                        .foregroundColor(.white).shadow(color:.red,radius:12)
                    Text("ALL SYSTEMS GO").font(.system(size:10,weight:.bold,design:.monospaced))
                        .kerning(4).foregroundColor(Color(red:1,green:0.85,blue:0.3).opacity(0.8))
                    HStack(spacing:12) {
                        Capsule().fill(Color.red).frame(width:40,height:3)
                        Capsule().fill(Color.white).frame(width:40,height:3)
                        Capsule().fill(Color.red).frame(width:40,height:3)
                    }
                }
                .scaleEffect(logoScale).opacity(logoOpacity).blur(radius:logoBlur)
            }
        }
    }

    private func finishBoot() {
        withAnimation(.easeOut(duration: 0.3)) { isFinished = true }
    }
    private func showWarning(then finish: Bool = true) {
        showWarningEnd = true
        withAnimation(.easeOut(duration: 0.35)) { warningEndOpacity = 1 }
        if finish {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeIn(duration: 0.3)) { warningEndOpacity = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.75) { finishBoot() }
        }
    }
    private func startBoot() {
        bootStep=0; speed=0; logoScale=0.6; logoOpacity=0; logoBlur=16
        flashOpacity=0; shake=0; ringScale=0.3; ringOpacity=0
        scanOffset=0; pulse=false; particleProgress=0; showParticles=false
        glitchOffset=0; matrixOpacity=0; holoScanProgress=0
        textReveal=0; ringPulse=1.0; goldBurst=0
        showWarningEnd=false; warningEndOpacity=0
        crackOpacity=0; bloodDripProgress=0
        circuitOpacity=0; dataStreamOffset=0
        petalBurst=0; toriiOpacity=0

        withAnimation(.linear(duration:1.2).repeatForever(autoreverses:false)) { rotation=360 }
        withAnimation(.linear(duration:1.0).repeatForever(autoreverses:true)) { scanOffset=1 }
        withAnimation(.easeInOut(duration:0.25).repeatForever(autoreverses:true)) { pulse=true }
        withAnimation(.easeInOut(duration:2.0).repeatForever(autoreverses:true)) { ringPulse=1.15 }
        withAnimation(.linear(duration:1.5).repeatForever(autoreverses:false)) { dataStreamOffset=1 }
        withAnimation(.spring(response:0.5,dampingFraction:0.7)) { logoOpacity=1; logoScale=1.0; logoBlur=0 }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.4) { withAnimation(.easeInOut(duration:0.9)) { speed=1 } }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.55) { withAnimation(.easeOut(duration:0.55)) { textReveal=1 } }

        switch selectedTheme {
        case .skull:
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { withAnimation(.easeIn(duration:0.4)) { crackOpacity=1 } }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.7) { withAnimation(.easeIn(duration:0.6)) { bloodDripProgress=1 } }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.8) { glitch() }
            DispatchQueue.main.asyncAfter(deadline:.now()+1.3) { glitch() }
            DispatchQueue.main.asyncAfter(deadline:.now()+1.7) { withAnimation(.easeIn(duration:0.15)) { flashOpacity=0.8; logoOpacity=0 } }
            DispatchQueue.main.asyncAfter(deadline:.now()+1.9) {
                withAnimation(.easeIn(duration:0.15)) { flashOpacity=0 }
                showWarning()
            }
        case .cyberpunk:
            withAnimation(.easeIn(duration:0.5).delay(0.3)) { matrixOpacity=1 }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { withAnimation(.easeIn(duration:0.6)) { circuitOpacity=1 } }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.45) { withAnimation(.linear(duration:0.85)) { holoScanProgress=1 } }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.85) { glitch() }
            DispatchQueue.main.asyncAfter(deadline:.now()+1.4) { glitch() }
            DispatchQueue.main.asyncAfter(deadline:.now()+1.8) { withAnimation(.easeIn(duration:0.18)) { flashOpacity=0.85; logoOpacity=0 } }
            DispatchQueue.main.asyncAfter(deadline:.now()+2.0) {
                withAnimation(.easeIn(duration:0.15)) { flashOpacity=0 }
                showWarning()
            }
        case .sakura:
            DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { withAnimation(.easeOut(duration:0.5)) { toriiOpacity=0.8 } }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.9) {
                bootStep=2; ringScale=1.0; ringOpacity=1; logoScale=1.0; logoOpacity=0; logoBlur=20; textReveal=0
                withAnimation(.spring(response:0.35,dampingFraction:0.65)) { logoOpacity=1; logoBlur=0; ringScale=1.25; ringOpacity=0 }
                withAnimation(.easeOut(duration:0.055)) { shake = -9 }
                DispatchQueue.main.asyncAfter(deadline:.now()+0.06) { withAnimation(.easeOut(duration:0.055)) { shake=8 } }
                DispatchQueue.main.asyncAfter(deadline:.now()+0.12) { withAnimation(.spring(response:0.12,dampingFraction:0.5)) { shake=0 } }
                withAnimation(.easeOut(duration:0.15)) { flashOpacity=0.7 }
                withAnimation(.easeIn(duration:0.3).delay(0.04)) { flashOpacity=0 }
            }
            DispatchQueue.main.asyncAfter(deadline:.now()+1.15) { withAnimation(.easeOut(duration:0.4)) { textReveal=1 } }
            DispatchQueue.main.asyncAfter(deadline:.now()+1.2) { withAnimation(.easeOut(duration:0.8)) { petalBurst=1 } }
            DispatchQueue.main.asyncAfter(deadline:.now()+1.25) { withAnimation(.easeOut(duration:0.7)) { goldBurst=1 } }
            DispatchQueue.main.asyncAfter(deadline:.now()+2.0) {
                withAnimation(.easeInOut(duration:0.2)) { bootStep=3; logoScale=0.9; logoOpacity=1; logoBlur=0; speed=0.2 }
            }
            DispatchQueue.main.asyncAfter(deadline:.now()+2.5) {
                showParticles=true; particleProgress=0
                withAnimation(.easeOut(duration:0.1)) { flashOpacity=0.85; shake=5 }
                withAnimation(.easeIn(duration:0.3).delay(0.02)) { flashOpacity=0; shake=0 }
                withAnimation(.easeOut(duration:0.5)) { particleProgress=1 }
            }
            DispatchQueue.main.asyncAfter(deadline:.now()+3.0) { withAnimation(.easeIn(duration:0.25)) { logoOpacity=0; logoBlur=6 } }
            DispatchQueue.main.asyncAfter(deadline:.now()+3.3) { showWarning() }
        }
    }
    private func glitch() {
        withAnimation(.easeOut(duration:0.055)) { glitchOffset = -10 }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.06) { withAnimation(.easeOut(duration:0.055)) { glitchOffset=8 } }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.12) { withAnimation(.spring(response:0.1,dampingFraction:0.6)) { glitchOffset=0 } }
    }
}

// MARK: - 爆閃粒子
private struct BootParticlesView: View {
    let color: Color; let progress: CGFloat
    struct Particle: Identifiable {
        let id: Int; let angle: Double; let radius: CGFloat; let size: CGFloat
    }
    static func makeParticles() -> [Particle] {
        var result: [Particle] = []
        for i in 0..<40 {
            let angleVal: Double   = Double(i)*(Double.pi*2.0/40.0)
            let radiusVal: CGFloat = CGFloat(80+(i*31)%190)
            let sizeVal: CGFloat   = CGFloat(1.5+Double(i%4))
            result.append(Particle(id:i,angle:angleVal,radius:radiusVal,size:sizeVal))
        }
        return result
    }
    private let particles = BootParticlesView.makeParticles()
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { p in
                    let x = geo.size.width/2+CGFloat(cos(p.angle))*p.radius*progress
                    let y = geo.size.height/2+CGFloat(sin(p.angle))*p.radius*progress
                    let fade = max(0.0,1.0-Double(progress)*1.1)
                    Circle().fill(color).frame(width:p.size*2,height:p.size*2)
                        .position(x:x,y:y).opacity(fade)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 櫻花飄落
struct SakuraFallingView: View {
    var density: Double
    var body: some View {
        if #available(iOS 15.0, *) { SakuraFallingContentView(density: density) }
        else { SakuraFallingFallback(density: density) }
    }
}
@available(iOS 15.0, *)
private struct SakuraFallingContentView: View {
    var density: Double
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.animation(paused: scenePhase != .active)) { tl in
            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { ctx, size in
                let count = Int(density); let t = tl.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    let seed = Double(i)*99.0; let time = t+seed
                    let x = (sin(time*0.5+seed)*0.5+0.5)*size.width
                    let y = fmod(time*28.0+seed*50.0,size.height+60)-30
                    let scale = CGFloat(0.4+sin(seed)*0.4)
                    let rot = sin(time*1.5+seed)*0.8
                    ctx.opacity = 0.7
                    let transform = CGAffineTransform(translationX: x, y: y).rotated(by: CGFloat(rot))
                    let petal = Path(ellipseIn:CGRect(x:-6*scale,y:-4*scale,width:12*scale,height:8*scale))
                        .applying(transform)
                    ctx.fill(petal, with:.color(Color(red:1.0,green:0.4,blue:0.5)))
                }
            }
        }
        .allowsHitTesting(false).ignoresSafeArea()
    }
}
private struct SakuraFallingFallback: View {
    var density: Double; @State private var phase: CGFloat = 0
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<Int(min(density,20)), id:\.self) { i in
                    let seed = Double(i)*99.0
                    let x = CGFloat(sin(seed*0.5)*0.5+0.5)*geo.size.width
                    let y = (phase*geo.size.height+CGFloat(seed*50).truncatingRemainder(dividingBy:geo.size.height+60))-30
                    Ellipse().fill(Color(red:1.0,green:0.4,blue:0.5)).frame(width:12,height:8)
                        .position(x:x,y:y).opacity(0.6)
                }
            }
        }
        .allowsHitTesting(false).ignoresSafeArea()
        .onAppear { withAnimation(.linear(duration:6).repeatForever(autoreverses:false)) { phase=1 } }
    }
}

// MARK: - 霓虹邊緣光
struct BackgroundNeonFlowView: View {
    var primaryColor: Color; var borderWidth: Double; var animSpeed: Double
    @State private var isAnimating = false
    var body: some View {
        ZStack {
            LinearGradient(colors:[primaryColor.opacity(isAnimating ? 0.35:0.15),.clear],
                           startPoint:.top,endPoint:UnitPoint(x:0.5,y:0.12))
            .ignoresSafeArea().blendMode(.screen)
            LinearGradient(colors:[primaryColor.opacity(isAnimating ? 0.3:0.12),.clear],
                           startPoint:.bottom,endPoint:UnitPoint(x:0.5,y:0.88))
            .ignoresSafeArea().blendMode(.screen)
            HStack {
                LinearGradient(colors:[primaryColor.opacity(isAnimating ? 0.2:0.08),.clear],
                               startPoint:.leading,endPoint:UnitPoint(x:0.08,y:0.5))
                .ignoresSafeArea().blendMode(.screen)
                Spacer()
                LinearGradient(colors:[primaryColor.opacity(isAnimating ? 0.2:0.08),.clear],
                               startPoint:.trailing,endPoint:UnitPoint(x:0.92,y:0.5))
                .ignoresSafeArea().blendMode(.screen)
            }
        }
        .allowsHitTesting(false).ignoresSafeArea()
        .onAppear {
            let duration = max(0.8,5.0-animSpeed)
            withAnimation(Animation.easeInOut(duration:duration).repeatForever(autoreverses:true)) { isAnimating=true }
        }
    }
}

// MARK: - 互動導航地圖（★ 藍色路線）
struct InteractiveNavigationMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    var routePolyline: MKPolyline?
    var destinationCoordinate: CLLocationCoordinate2D?
    var historyPath: [CLLocationCoordinate2D]?
    var cameraPoints: [SpeedCamera] = []
    var isInteractive: Bool = true
    var onMapTap: (CLLocationCoordinate2D) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.showsUserLocation = true
        map.userTrackingMode = isInteractive ? .followWithHeading : .none
        map.isZoomEnabled = isInteractive; map.isScrollEnabled = isInteractive
        map.isRotateEnabled = isInteractive; map.showsCompass = false; map.showsTraffic = false
        map.delegate = context.coordinator
        if isInteractive {
            let tap = UITapGestureRecognizer(target:context.coordinator, action:#selector(Coordinator.handleTap(_:)))
            map.addGestureRecognizer(tap)
        }
        return map
    }
    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.parent = self
        if isInteractive && uiView.userTrackingMode != .followWithHeading {
            uiView.setUserTrackingMode(.followWithHeading, animated:true)
        }
        if !isInteractive {
            context.coordinator.updateCenter(coordinate, on: uiView)
        }
        context.coordinator.updateRoute(routePolyline, on: uiView)
        context.coordinator.updateHistory(historyPath, on: uiView)
        context.coordinator.updateDestination(destinationCoordinate, on: uiView)
        context.coordinator.updateCameras(cameraPoints, on: uiView)
    }
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: InteractiveNavigationMapView
        private var routeOverlay: MKPolyline?
        private var historyOverlay: MKPolyline?
        private var historyCount = 0
        private var historyStart: CLLocationCoordinate2D?
        private var historyEnd: CLLocationCoordinate2D?
        private var destinationAnnotation: MKPointAnnotation?
        private var centeredCoordinate: CLLocationCoordinate2D?
        private var cameraAnnotations: [MKPointAnnotation] = []
        init(_ p: InteractiveNavigationMapView) { self.parent = p }

        func updateCenter(_ coordinate: CLLocationCoordinate2D, on map: MKMapView) {
            let animated = centeredCoordinate != nil
            if let previous = centeredCoordinate {
                let old = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                let new = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                guard old.distance(from: new) >= 10 else { return }
            }
            centeredCoordinate = coordinate
            map.setRegion(
                MKCoordinateRegion(center: coordinate, latitudinalMeters: 1_200, longitudinalMeters: 1_200),
                animated: animated
            )
        }

        func updateRoute(_ route: MKPolyline?, on map: MKMapView) {
            if let current = routeOverlay, let route = route, current === route { return }
            if routeOverlay == nil && route == nil { return }
            if let old = routeOverlay { map.removeOverlay(old) }
            routeOverlay = route
            if let route = route { map.addOverlay(route) }
        }

        func updateHistory(_ path: [CLLocationCoordinate2D]?, on map: MKMapView) {
            let count = path?.count ?? 0
            let start = path?.first
            let end = path?.last
            guard count != historyCount || !sameCoordinate(start, historyStart) || !sameCoordinate(end, historyEnd) else { return }

            if let old = historyOverlay { map.removeOverlay(old) }
            historyOverlay = nil
            historyCount = count
            historyStart = start
            historyEnd = end
            if let path = path, !path.isEmpty {
                let overlay = MKPolyline(coordinates: path, count: path.count)
                historyOverlay = overlay
                map.addOverlay(overlay)
                if parent.historyPath != nil {
                    map.setVisibleMapRect(
                        overlay.boundingMapRect,
                        edgePadding: UIEdgeInsets(top: 40, left: 30, bottom: 40, right: 30),
                        animated: false
                    )
                }
            }
        }

        func updateDestination(_ coordinate: CLLocationCoordinate2D?, on map: MKMapView) {
            guard !sameCoordinate(destinationAnnotation?.coordinate, coordinate) else { return }
            if let old = destinationAnnotation { map.removeAnnotation(old) }
            destinationAnnotation = nil
            if let coordinate = coordinate {
                let annotation = MKPointAnnotation()
                annotation.coordinate = coordinate
                annotation.title = "目的地"
                destinationAnnotation = annotation
                map.addAnnotation(annotation)
            }
        }
        func updateCameras(_ cameras: [SpeedCamera], on map: MKMapView) {
            map.removeAnnotations(cameraAnnotations); cameraAnnotations.removeAll()
            for camera in cameras {
                let a = MKPointAnnotation(); a.coordinate = camera.coordinate
                a.title = camera.isTemporary ? "臨時測速 (Int(camera.speedLimit))" : "固定測速 (Int(camera.speedLimit))"
                a.subtitle = camera.description; cameraAnnotations.append(a)
            }
            map.addAnnotations(cameraAnnotations)
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let v = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "camera")
            v.markerTintColor = ((annotation.title ?? "").contains("臨時")) ? .systemOrange : .systemRed
            v.glyphImage = UIImage(systemName: "camera.fill")
            return v
        }

        private func sameCoordinate(_ lhs: CLLocationCoordinate2D?, _ rhs: CLLocationCoordinate2D?) -> Bool {
            switch (lhs, rhs) {
            case (nil, nil): return true
            case let (lhs?, rhs?):
                return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
            default: return false
            }
        }
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            let map = g.view as! MKMapView
            parent.onMapTap(map.convert(g.location(in:map), toCoordinateFrom:map))
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let p = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: p)
                if p === historyOverlay {
                    r.strokeColor = .systemOrange
                    r.lineWidth = 5
                } else {
                    // ★ 導航路線：藍色
                    r.strokeColor = UIColor.navigationBlue
                    r.lineWidth = 7
                    r.lineDashPattern = nil
                    r.lineCap = .round
                    r.lineJoin = .round
                }
                return r
            }
            return MKOverlayRenderer()
        }
    }
}

// MARK: - 速度儀表環
struct NeonSpeedGaugeRing: View {
    var speed: Double; var maxDisplaySpeed: Double = 220.0
    var color: Color; var outerBorderWidth: Double; var animSpeed: Double
    @State private var isOuterRotating = false
    var progress: Double { min(max(speed/maxDisplaySpeed,0),1) }
    var glowIntensity: Double { 0.3+progress*0.7 }
    var outerGlowSize: CGFloat { CGFloat(310+progress*40) }
    var pulseSize: CGFloat { CGFloat(280+progress*60) }
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    gradient:Gradient(colors:[color.opacity(glowIntensity*0.4),color.opacity(glowIntensity*0.15),color.opacity(0.04),.clear]),
                    center:.center,startRadius:80,endRadius:outerGlowSize/2))
                .frame(width:outerGlowSize,height:outerGlowSize)
                .blendMode(.screen)
            if progress > 0.1 {
                Circle()
                    .fill(RadialGradient(gradient:Gradient(colors:[.clear,color.opacity(glowIntensity*0.25),.clear]),
                        center:.center,startRadius:110,endRadius:160))
                    .frame(width:pulseSize,height:pulseSize)
                    .blendMode(.screen)
            }
            Circle()
                .stroke(AngularGradient(gradient:Gradient(stops:[
                    .init(color:color.opacity(0.05),location:0),
                    .init(color:color.opacity(0.5+progress*0.5),location:0.25),
                    .init(color:.white,location:0.5),
                    .init(color:color.opacity(0.5+progress*0.5),location:0.75),
                    .init(color:color.opacity(0.05),location:1)
                ]),center:.center,angle:.degrees(0)),
                       lineWidth:CGFloat(outerBorderWidth+progress*3))
                .frame(width:299,height:299)
                .shadow(color:color.opacity(glowIntensity),radius:CGFloat(8+progress*16))
                .shadow(color:color.opacity(0.3+progress*0.4),radius:CGFloat(20+progress*20))
                .rotationEffect(.degrees(isOuterRotating ? 360:0))
            Circle()
                .stroke(LinearGradient(colors:[Color.white.opacity(0.15),color.opacity(0.05),Color.white.opacity(0.12),color.opacity(0.03)],
                    startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:10)
                .frame(width:259,height:259)
            Circle().stroke(Color.white.opacity(0.07),lineWidth:12).frame(width:257,height:257)
            Circle().trim(from:0,to:CGFloat(progress))
                .stroke(color.opacity(0.25+progress*0.2),style:StrokeStyle(lineWidth:24,lineCap:.round))
                .frame(width:257,height:257).rotationEffect(.degrees(-90))
                .blur(radius:CGFloat(8+progress*8))
            Circle().trim(from:0,to:CGFloat(progress))
                .stroke(AngularGradient(gradient:Gradient(colors:[color.opacity(0.4),color,.white]),center:.center),
                        style:StrokeStyle(lineWidth:12,lineCap:.round))
                .frame(width:257,height:257).rotationEffect(.degrees(-90))
                .shadow(color:color,radius:CGFloat(10+progress*8))
                .shadow(color:color.opacity(0.4),radius:CGFloat(20+progress*15))
            if progress > 0.01 {
                let angle = (progress*360.0-90.0)*Double.pi/180.0
                Circle().fill(Color.white)
                    .frame(width:10+CGFloat(progress*4),height:10+CGFloat(progress*4))
                    .offset(x:CGFloat(cos(angle))*128.5,y:CGFloat(sin(angle))*128.5)
                    .shadow(color:.white,radius:6+CGFloat(progress*6))
                    .shadow(color:color,radius:10+CGFloat(progress*10))
            }
            ForEach(0..<12,id:\.self) { i in
                let lit = i < Int(progress*12)
                Rectangle().fill(lit ? color : Color.white.opacity(0.12))
                    .frame(width:lit ? 4:2.5,height:lit ? 12:8)
                    .offset(y:-124).rotationEffect(.degrees(Double(i)*30))
                    .shadow(color:lit ? color:.clear,radius:lit ? CGFloat(6+progress*4):0)
            }
        }
        .drawingGroup()
        .onAppear {
            let duration = max(0.3,5.0-animSpeed-progress*2)
            withAnimation(Animation.linear(duration:duration).repeatForever(autoreverses:false)) { isOuterRotating=true }
        }
    }
}

// MARK: - 轉速燈
struct ShiftLightsView: View {
    let speed: Double
    var body: some View {
        HStack(spacing:4) {
            ForEach(0..<8,id:\.self) { i in
                let lit = speed >= Double(i+1)*25.0
                RoundedRectangle(cornerRadius:3).fill(lightColor(for:i,lit:lit))
                    .frame(width:16,height:7)
                    .shadow(color:lit ? lightColor(for:i,lit:true):.clear,radius:lit ? 6:0)
            }
        }
    }
    private func lightColor(for i: Int, lit: Bool) -> Color {
        guard lit else { return Color.gray.opacity(0.2) }
        if i<4 { return .green }; if i<6 { return .yellow }; return .red
    }
}

// MARK: - 玻璃態 HUD 資訊卡
struct GlassInfoCard: View {
    let title: String; let value: String; let valueColor: Color; let icon: String
    var isActive: Bool = false
    @State private var breathe = false
    var body: some View {
        HStack(spacing:6) {
            Image(systemName:icon).font(.system(size:9,weight:.bold))
                .foregroundColor(valueColor.opacity(0.8)).frame(width:14)
            VStack(alignment:.leading,spacing:1) {
                Text(title).font(.system(size:7,weight:.bold,design:.monospaced)).foregroundColor(.gray)
                Text(value).font(.system(size:10,weight:.black,design:.monospaced)).foregroundColor(valueColor)
            }
        }
        .padding(.horizontal,7).padding(.vertical,5)
        .background(ZStack {
            RoundedRectangle(cornerRadius:8).fill(Color.white.opacity(0.06))
            LinearGradient(colors:[Color.white.opacity(0.12),.clear],startPoint:.top,endPoint:.center)
                .clipShape(RoundedRectangle(cornerRadius:8))
        })
        .overlay(RoundedRectangle(cornerRadius:8)
            .stroke(LinearGradient(colors:[Color.white.opacity(0.25),valueColor.opacity(0.3),Color.white.opacity(0.1)],
                                   startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.8))
        .scaleEffect(isActive && breathe ? 1.02:1.0)
        .onAppear {
            if isActive { withAnimation(.easeInOut(duration:1.4).repeatForever(autoreverses:true)) { breathe=true } }
        }
    }
}

// MARK: - 小地圖
struct MiniMapView: View {
    let coordinate: CLLocationCoordinate2D
    var routePolyline: MKPolyline?; var destinationCoordinate: CLLocationCoordinate2D?
    var primaryColor: Color; var onTap: () -> Void
    var body: some View {
        Button(action:onTap) {
            ZStack(alignment:.bottomTrailing) {
                InteractiveNavigationMapView(coordinate:coordinate,routePolyline:routePolyline,
                    destinationCoordinate:destinationCoordinate,isInteractive:false,onMapTap:{_ in})
                .clipShape(RoundedRectangle(cornerRadius:18))
                .overlay(RoundedRectangle(cornerRadius:18)
                    .stroke(LinearGradient(colors:[primaryColor,primaryColor.opacity(0.4)],
                                          startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1.5))
                Image(systemName:"arrow.up.left.and.arrow.down.right")
                    .font(.system(size:10,weight:.bold)).foregroundColor(.white)
                    .padding(6).background(Color.black.opacity(0.75)).clipShape(Circle()).padding(7)
            }
        }
        .frame(width:110,height:110)
        .shadow(color:primaryColor.opacity(0.5),radius:10)
    }
}

// MARK: - 效能測試
struct PerformanceTestDashboardView: View {
    @ObservedObject var vehicleManager: VehicleManager; var primaryColor: Color
    var body: some View {
        TabView {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing:24) {
                    Text("0 - 100 KM/H 加速測試").font(.system(size:20,weight:.black,design:.monospaced)).foregroundColor(.white)
                    ZStack {
                        Circle().stroke(primaryColor.opacity(0.3),lineWidth:12).frame(width:200,height:200)
                        VStack(spacing:4) {
                            Text(String(format:"%.2f",vehicleManager.zeroToOneHundredTime))
                                .font(.system(size:48,weight:.black,design:.monospaced)).foregroundColor(.white)
                            Text("秒 (SEC)").font(.system(size:12,weight:.bold)).foregroundColor(primaryColor)
                        }
                    }
                    Text(vehicleManager.isTesting0_100 ? "測試中...全油門加速！":"靜止後自動重置")
                        .font(.system(size:12,design:.monospaced)).foregroundColor(.gray)
                }
            }.tabItem { Label("0-100加速",systemImage:"timer") }
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing:24) {
                    Text("0 - 100 公尺短距加速").font(.system(size:20,weight:.black,design:.monospaced)).foregroundColor(.white)
                    ZStack {
                        Circle().stroke(Color.orange.opacity(0.3),lineWidth:12).frame(width:200,height:200)
                        VStack(spacing:4) {
                            Text(String(format:"%.2f",vehicleManager.zeroTo100mTime))
                                .font(.system(size:48,weight:.black,design:.monospaced)).foregroundColor(.orange)
                            Text("秒 / 100M").font(.system(size:12,weight:.bold)).foregroundColor(.orange)
                        }
                    }
                    Text(vehicleManager.isTesting0_100m ? "0-100公尺計測中...":"起步自動開始")
                        .font(.system(size:12,design:.monospaced)).foregroundColor(.gray)
                }
            }.tabItem { Label("100公尺測試",systemImage:"flag.checkered") }
        }
        .accentColor(primaryColor).navigationTitle("車輛效能測試").ignoresSafeArea()
    }
}

// MARK: - 歷史紀錄
struct HistoryRecordsView: View {
    @Binding var records: [HistoryRecord]
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            List {
                ForEach(records) { rec in
                    NavigationLink(destination:HistoryDetailMapView(record:rec)) {
                        VStack(alignment:.leading) {
                            Text(rec.date,formatter:Self.dateFormatter).font(.system(size:12)).foregroundColor(.gray)
                            Text(String(format:"極速: %.0f km/h | 0-100: %.2fs | %.2f km",
                                rec.maxSpeed,rec.zeroToOneHundredTime,rec.tripDistance))
                            .font(.system(size:14,weight:.bold)).foregroundColor(.white)
                        }
                    }.listRowBackground(Color.black)
                }
                .onDelete { records.remove(atOffsets:$0) }
            }
        }
        .navigationTitle("行車歷史封存")
    }
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .medium; return df
    }()
}
struct HistoryDetailMapView: View {
    let record: HistoryRecord
    var body: some View {
        InteractiveNavigationMapView(
            coordinate:record.routeCoordinates.first?.coordinate ?? CLLocationCoordinate2D(latitude:25.033,longitude:121.565),
            historyPath:record.routeCoordinates.map{$0.coordinate},
            isInteractive:true,onMapTap:{_ in})
        .ignoresSafeArea().navigationTitle("軌跡回放")
    }
}

// MARK: - 設定頁面
struct SettingsView: View {
    @ObservedObject var vehicleManager: VehicleManager
    @Binding var selectedTheme: DashboardTheme; @Binding var speedLimit: Double
    @Binding var isHudMode: Bool; @Binding var useCustomColor: Bool; @Binding var customColor: Color
    @Binding var isNetworkBoostEnabled: Bool; @Binding var simulatedSpeed: Double
    @Binding var enableSakuraBackground: Bool; @Binding var sakuraDensity: Double
    @Binding var borderWidth: Double; @Binding var animSpeed: Double
    var body: some View {
        Form {
            Section(header: Text("使用車種")) {
                Picker("車種", selection: Binding(get: { vehicleManager.transportMode }, set: { vehicleManager.setTransportMode($0) })) {
                    ForEach(TransportMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Text("腳踏車模式會忽略高速公路等不適用的高限速測速點。")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Section(header:Text("霓虹邊緣光設定")) {
                VStack(alignment:.leading,spacing:8) {
                    Text("光暈強度: \(Int(borderWidth)) 級").font(.system(size:14,weight:.bold,design:.monospaced))
                    Slider(value:$borderWidth,in:2...12,step:1)
                }
                VStack(alignment:.leading,spacing:8) {
                    Text("呼吸速度: \(Int(animSpeed)) 級").font(.system(size:14,weight:.bold,design:.monospaced))
                    Slider(value:$animSpeed,in:1...5,step:1)
                }
            }
            Section(header:Text("語音播報")) {
                Picker("語音語言",selection:$vehicleManager.speechManager.currentLanguage) {
                    Text("繁體中文").tag("zh-TW"); Text("English").tag("en-US"); Text("日本語").tag("ja-JP")
                }.pickerStyle(SegmentedPickerStyle())
                Button("測試語音播報") { vehicleManager.speechManager.announceWarning(speedLimit:60,isOverspeed:true) }.foregroundColor(.blue)
            }
            Section(header:Text("測速點位管理")) {
                VStack(alignment:.leading) {
                    Text("提醒距離: \(Int(vehicleManager.cameraAlertDistance)) 公尺")
                    Slider(value: Binding(get:{ vehicleManager.cameraAlertDistance }, set:{ vehicleManager.setCameraAlertDistance($0) }), in:100...1000, step:50)
                }
                Toggle("依行進方向過濾", isOn: Binding(get:{ vehicleManager.directionFilteringEnabled }, set:{ vehicleManager.setDirectionFiltering($0) }))
                Button("新增目前位置為測速點") { vehicleManager.addCurrentLocationAsCamera(speedLimit:speedLimit,description:"手動回報") }
                Button("移除最近測速點 (150m內)") { vehicleManager.removeNearestCamera() }.foregroundColor(.red)
            }
            Section(header:Text("視覺主題")) {
                Picker("佈景主題",selection:$selectedTheme) {
                    ForEach(DashboardTheme.allCases) { t in Text(t.rawValue).tag(t) }
                }.pickerStyle(SegmentedPickerStyle())
                Toggle("啟用自定義霓虹色",isOn:$useCustomColor)
                if useCustomColor { ColorPicker("自定義主色調",selection:$customColor) }
            }
            if selectedTheme == .sakura {
                Section(header:Text("日本櫻花背景")) {
                    Toggle("啟用櫻花飄落背景",isOn:$enableSakuraBackground)
                    if enableSakuraBackground {
                        VStack(alignment:.leading,spacing:8) {
                            Text("密度: \(Int(sakuraDensity)) 片").font(.system(size:13,weight:.bold))
                            Slider(value:$sakuraDensity,in:5...50,step:5)
                        }
                    }
                }
            }
            Section(header:Text("模擬速度測試")) {
                VStack(alignment:.leading,spacing:8) {
                    Text("模擬車速: \(Int(simulatedSpeed)) km/h").font(.system(size:14,weight:.bold,design:.monospaced))
                    Slider(value:$simulatedSpeed,in:0...220,step:5)
                }
            }
            Section(header:Text("速限與警告")) {
                VStack(alignment:.leading) {
                    Text("超速閾值: \(Int(speedLimit)) km/h").font(.system(size:14,weight:.bold,design:.monospaced))
                    Slider(value:$speedLimit,in:10...180,step:5)
                }
            }
            Section(header:Text("導航與定位")) { Toggle("網路定位增強",isOn:$isNetworkBoostEnabled) }
            Section(header:Text("顯示模式")) { Toggle("HUD 投影模式 (鏡像)",isOn:$isHudMode) }
        }
        .navigationTitle("儀表板設定")
    }
}

// MARK: - 主畫面 ContentView
struct ContentView: View {
    @StateObject private var vehicleManager = VehicleManager()
    @StateObject private var searchManager = MapSearchManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isBootLoaded: Bool = false

    @AppStorage("selectedTheme") private var storedThemeRaw: String = DashboardTheme.sakura.rawValue
    @AppStorage("speedLimit") private var speedLimit: Double = 120.0
    @AppStorage("isHudMode") private var isHudMode: Bool = false
    @AppStorage("showMap") private var showMap: Bool = false
    @AppStorage("useCustomColor") private var useCustomColor: Bool = false
    @AppStorage("customColorRaw") private var customColorRaw: String = "1.0,0.3,0.4"
    @AppStorage("isNetworkBoostEnabled") private var isNetworkBoostEnabled: Bool = false
    @AppStorage("enableSakuraBackground") private var enableSakuraBackground: Bool = true
    @AppStorage("sakuraDensity") private var sakuraDensity: Double = 20.0
    @AppStorage("borderWidth") private var borderWidth: Double = 4.0
    @AppStorage("animSpeed") private var animSpeed: Double = 3.0

    @State private var overspeedLogs: [OverspeedRecord] = []
    @State private var historyRecords: [HistoryRecord] = []
    @State private var showSettings: Bool = false
    @State private var showHistoryRecords: Bool = false
    @State private var showPerformanceView: Bool = false
    @State private var flashWarning: Bool = false
    @State private var simulatedSpeed: Double = 0.0
    @State private var showJapaneseOverspeedAlert: Bool = false
    @State private var overspeedTimer: Timer? = nil
    @State private var overspeedStartedAt: Date? = nil
    @State private var showSearchOverlay: Bool = false

    var customColor: Color {
        get { Color(rawValue:customColorRaw) ?? Color(red:1.0,green:0.3,blue:0.4) }
        set { customColorRaw = newValue.rawValue }
    }
    var effectiveSpeed: Double { simulatedSpeed > 0 ? simulatedSpeed : vehicleManager.speed }
    var selectedTheme: DashboardTheme {
        get { DashboardTheme(rawValue:storedThemeRaw) ?? .sakura }
        set { storedThemeRaw = newValue.rawValue }
    }
    var currentPrimaryColor: Color {
        selectedTheme.primaryColor(custom: useCustomColor ? customColor : nil)
    }

    var body: some View {
        NavigationView {
            ZStack {
                if isBootLoaded && !showMap {
                    AnimatedBackgroundView(
                        themeColors: selectedTheme.backgroundGradientColors,
                        primaryColor: currentPrimaryColor,
                        theme: selectedTheme
                    )
                } else {
                    Color.black.ignoresSafeArea()
                }

                if isBootLoaded && !showMap && selectedTheme == .sakura && enableSakuraBackground {
                    SakuraFallingView(density: sakuraDensity).ignoresSafeArea().zIndex(1)
                }

                if !isBootLoaded {
                    MultiThemeBootLoadingView(
                        isFinished: $isBootLoaded,
                        selectedTheme: Binding(get: { self.selectedTheme }, set: { self.storedThemeRaw = $0.rawValue })
                    )
                    .transition(.opacity).zIndex(50)
                } else {
                    ZStack {
                        BackgroundNeonFlowView(primaryColor:currentPrimaryColor,borderWidth:borderWidth,animSpeed:animSpeed)
                            .ignoresSafeArea().zIndex(0)

                        if flashWarning { Color.red.opacity(0.28).ignoresSafeArea().zIndex(10) }

                        if showJapaneseOverspeedAlert {
                            VStack {
                                Spacer()
                                HStack(spacing:10) {
                                    Image(systemName:"exclamationmark.triangle.fill").foregroundColor(.yellow).font(.system(size:22))
                                    VStack(alignment:.leading,spacing:3) {
                                        Text("オービス警報発動").font(.system(size:15,weight:.black,design:.monospaced)).foregroundColor(.white)
                                        Text("速度超過！減速してください！").font(.system(size:12,weight:.bold,design:.monospaced)).foregroundColor(.orange)
                                    }
                                }
                                .padding(.horizontal,22).padding(.vertical,13)
                                .background(ZStack {
                                    RoundedRectangle(cornerRadius:14).fill(Color.black.opacity(0.93))
                                    LinearGradient(colors:[Color.white.opacity(0.06),.clear],startPoint:.top,endPoint:.bottom)
                                        .clipShape(RoundedRectangle(cornerRadius:14))
                                })
                                .overlay(RoundedRectangle(cornerRadius:14).stroke(Color.red,lineWidth:2))
                                .shadow(color:.red.opacity(0.85),radius:16)
                                .padding(.bottom,60)
                            }
                            .zIndex(60)
                        }

                        ZStack(alignment:.top) {
                            if showMap {
                                ZStack(alignment:.topLeading) {
                                    InteractiveNavigationMapView(
                                        coordinate:vehicleManager.currentLocation,
                                        routePolyline:vehicleManager.routePolyline,
                                        destinationCoordinate:vehicleManager.destinationCoordinate,
                                        cameraPoints: vehicleManager.speedCameras,
                                        isInteractive:true,
                                                                                onMapTap: { coord in
                                            if !showSearchOverlay {
                                                vehicleManager.setDestination(coord, name: "地圖點選位置")
                                            }
                                        }
                                    )
                                    .ignoresSafeArea()
                                    .onChange(of: vehicleManager.currentLocation.latitude) { _ in
                                        searchManager.currentRegion = MKCoordinateRegion(
                                            center: vehicleManager.currentLocation,
                                            latitudinalMeters: 8000, longitudinalMeters: 8000)
                                    }

                                    if !showSearchOverlay {
                                        VStack(spacing: 0) {
                                            HStack(alignment: .top, spacing: 10) {
                                                Button(action: { showMap = false }) {
                                                    Image(systemName: "gauge.with.needle")
                                                        .font(.system(size: 15, weight: .bold))
                                                        .frame(width: 42, height: 42)
                                                        .background(Color.black.opacity(0.82))
                                                        .foregroundColor(currentPrimaryColor)
                                                        .cornerRadius(21)
                                                        .overlay(Circle().stroke(currentPrimaryColor.opacity(0.6), lineWidth: 1.5))
                                                }
                                                Button(action: { withAnimation(.easeInOut(duration: 0.22)) { showSearchOverlay = true } }) {
                                                    HStack(spacing: 8) {
                                                        Image(systemName: "magnifyingglass")
                                                            .font(.system(size: 13, weight: .semibold))
                                                            .foregroundColor(currentPrimaryColor)
                                                        Text(vehicleManager.isNavigating && !vehicleManager.destinationName.isEmpty
                                                             ? vehicleManager.destinationName : "搜尋目的地")
                                                            .font(.system(size: 13, weight: .medium))
                                                            .foregroundColor(vehicleManager.isNavigating ? .white : .white.opacity(0.55))
                                                            .lineLimit(1)
                                                        Spacer()
                                                        if vehicleManager.isNavigating {
                                                            Circle().fill(currentPrimaryColor).frame(width: 7, height: 7)
                                                        }
                                                    }
                                                    .padding(.horizontal, 12).padding(.vertical, 11)
                                                    .background(Color.black.opacity(0.82))
                                                    .cornerRadius(12)
                                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                                        .stroke(currentPrimaryColor.opacity(vehicleManager.isNavigating ? 0.8 : 0.4), lineWidth: 1))
                                                }
                                                HStack(spacing: 4) {
                                                    Text(String(format: "%.0f", effectiveSpeed))
                                                        .font(.system(size: 20, weight: .black, design: .monospaced)).foregroundColor(.white)
                                                    Text("km/h").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(currentPrimaryColor)
                                                }
                                                .padding(.horizontal, 10).frame(height: 42)
                                                .background(Color.black.opacity(0.82)).cornerRadius(12)
                                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(currentPrimaryColor.opacity(0.5), lineWidth: 1))
                                            }
                                            .padding(.horizontal, 16).padding(.top, 18)

                                            if vehicleManager.isNavigating {
                                                HStack(spacing: 10) {
                                                    Image(systemName: "arrow.turn.up.right")
                                                        .font(.system(size: 16, weight: .bold)).foregroundColor(currentPrimaryColor)
                                                    Text(vehicleManager.currentInstruction)
                                                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(2)
                                                    Spacer()
                                                    if vehicleManager.distanceToNextStep > 0 {
                                                        Text(vehicleManager.distanceToNextStep >= 1000
                                                             ? String(format: "%.1f km", vehicleManager.distanceToNextStep/1000)
                                                             : "\(Int(vehicleManager.distanceToNextStep)) m")
                                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                            .foregroundColor(currentPrimaryColor)
                                                    }
                                                    Button(action: { vehicleManager.cancelNavigation() }) {
                                                        Image(systemName: "xmark.circle.fill")
                                                            .font(.system(size: 22)).foregroundColor(.red.opacity(0.9))
                                                    }
                                                }
                                                .padding(.horizontal, 16).padding(.vertical, 10)
                                                .background(Color.black.opacity(0.82)).cornerRadius(14)
                                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(currentPrimaryColor.opacity(0.35), lineWidth: 1))
                                                .padding(.horizontal, 16).padding(.top, 8)
                                            }
                                        }
                                    }

                                    if showSearchOverlay {
                                        MapSearchOverlayView(
                                            searchManager: searchManager,
                                            vehicleManager: vehicleManager,
                                            primaryColor: currentPrimaryColor,
                                            onSelectDestination: { coord, name in
                                                withAnimation(.easeOut(duration: 0.2)) { showSearchOverlay = false }
                                                searchManager.updateSearch("")
                                                vehicleManager.setDestination(coord, name: name)
                                            },
                                            onDismiss: {
                                                withAnimation(.easeOut(duration: 0.2)) { showSearchOverlay = false }
                                                searchManager.updateSearch("")
                                            }
                                        )
                                        .transition(.opacity).zIndex(100)
                                    }
                                }
                                .ignoresSafeArea()

                            } else {
                                HStack(spacing: 12) {
                                    VStack(spacing: 10) {
                                        sideButton(icon:"map.fill",label:"地圖",bg:Color.white.opacity(0.12),fg:.white) { showMap = true }
                                        sideButton(icon:"gearshape.fill",label:"設定",bg:currentPrimaryColor.opacity(0.15),fg:currentPrimaryColor,border:currentPrimaryColor.opacity(0.5)) { showSettings = true }
                                        sideButton(icon:"timer",label:"測試",bg:Color.orange.opacity(0.2),fg:.orange) { showPerformanceView = true }
                                        sideButton(icon:"list.bullet.rectangle.portrait.fill",label:"紀錄",bg:Color.white.opacity(0.12),fg:.white) { showHistoryRecords = true }
                                        Spacer()
                                        sideButton(icon:"arrow.counterclockwise.circle.fill",label:"重置",bg:Color.red.opacity(0.2),fg:.red) {
                                            let h = HistoryRecord(id:UUID(),date:Date(),maxSpeed:vehicleManager.maxSpeed,
                                                zeroToOneHundredTime:vehicleManager.zeroToOneHundredTime,maxGForce:vehicleManager.maxGForce,
                                                tripDistance:vehicleManager.tripDistance,
                                                routeCoordinates:vehicleManager.recordedPath.map{CodableCoordinate($0)})
                                            historyRecords.append(h); vehicleManager.resetData(); simulatedSpeed = 0
                                        }
                                    }
                                    .frame(width: 54)

                                    ZStack {
                                        NeonSpeedGaugeRing(
                                            speed: effectiveSpeed,
                                            color: currentPrimaryColor,
                                            outerBorderWidth: borderWidth,
                                            animSpeed: animSpeed
                                        )
                                        VStack(spacing: 4) {
                                            Text(simulatedSpeed > 0 ? "SIMULATED" : "GPS SPEED")
                                                .font(.system(size:9,weight:.black,design:.monospaced))
                                                .foregroundColor(simulatedSpeed > 0 ? .orange : .gray).kerning(2)
                                            Text(String(format:"%.0f",effectiveSpeed))
                                                .font(.system(size:80,weight:.black,design:.monospaced)).foregroundColor(.white)
                                                .shadow(color:currentPrimaryColor,radius:14)
                                                .shadow(color:currentPrimaryColor.opacity(0.4),radius:28)
                                            Text("KM/H").font(.system(size:13,weight:.bold,design:.monospaced))
                                                .foregroundColor(currentPrimaryColor).shadow(color:currentPrimaryColor,radius:6)
                                        }
                                    }
                                    .frame(maxWidth:.infinity,maxHeight:.infinity)

                                    VStack(spacing: 8) {
                                        MiniMapView(
                                            coordinate:vehicleManager.currentLocation,
                                            routePolyline:vehicleManager.routePolyline,
                                            destinationCoordinate:vehicleManager.destinationCoordinate,
                                            primaryColor:currentPrimaryColor
                                        ) { showMap = true }

                                        VStack(spacing: 3) {
                                            ShiftLightsView(speed:effectiveSpeed)
                                            Text("RPM SHIFT").font(.system(size:7,weight:.bold,design:.monospaced)).foregroundColor(.gray)
                                        }

                                        VStack(spacing: 5) {
                                            GlassInfoCard(title:"0-100加速",
                                                value:String(format:"%.2fs",vehicleManager.zeroToOneHundredTime),
                                                valueColor:vehicleManager.isTesting0_100 ? .yellow : currentPrimaryColor,
                                                icon:"speedometer",isActive:vehicleManager.isTesting0_100)
                                            GlassInfoCard(title:"0-100m距",
                                                value:String(format:"%.2fs",vehicleManager.zeroTo100mTime),
                                                valueColor:vehicleManager.isTesting0_100m ? .yellow : .orange,
                                                icon:"flag.checkered",isActive:vehicleManager.isTesting0_100m)
                                            GlassInfoCard(title:"行車里程",
                                                value:String(format:"%.2fkm",vehicleManager.tripDistance),
                                                valueColor:.green,icon:"road.lanes")
                                            GlassInfoCard(title:"最高極速",
                                                value:String(format:"%.0fkm/h",max(vehicleManager.maxSpeed,simulatedSpeed)),
                                                valueColor:.white,icon:"flame.fill")
                                        }
                                        Spacer()
                                    }
                                    .frame(width: 135)
                                }
                                .padding(.horizontal,18).padding(.vertical,14)
                            }

                            if let alert = vehicleManager.nearestCameraAlert {
                                HStack(spacing:8) {
                                    Image(systemName:"camera.fill").foregroundColor(.yellow)
                                    Text(alert).font(.system(size:12,weight:.bold,design:.monospaced)).foregroundColor(.white)
                                }
                                .padding(.horizontal,16).padding(.vertical,9)
                                .background(ZStack {
                                    Capsule().fill(Color.red.opacity(0.93))
                                    LinearGradient(colors:[Color.white.opacity(0.12),.clear],startPoint:.top,endPoint:.bottom)
                                        .clipShape(Capsule())
                                })
                                .shadow(color:.red,radius:12)
                                .padding(.top,16).zIndex(50)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth:.infinity,maxHeight:.infinity)
            .navigationBarHidden(true)
            .statusBarHidden(true)
            .ignoresSafeArea()
            .scaleEffect(x:isHudMode ? -1.0:1.0, y:1.0)
            .onAppear {
                vehicleManager.updateLocationAccuracy(isNetworkBoostEnabled:isNetworkBoostEnabled)
                searchManager.currentRegion = MKCoordinateRegion(
                    center:vehicleManager.currentLocation,latitudinalMeters:8000,longitudinalMeters:8000)
            }
            .onChange(of:effectiveSpeed) { newVal in
                updateOverspeedState(for: newVal)
            }
            .onChange(of:speedLimit) { _ in
                updateOverspeedState(for: effectiveSpeed)
            }
            .onChange(of:scenePhase) { phase in
                vehicleManager.setMotionUpdatesActive(phase == .active)
            }
            .onDisappear {
                overspeedTimer?.invalidate()
                overspeedTimer = nil
                showJapaneseOverspeedAlert = false
            }
            .background(
                Group {
                    NavigationLink(destination:SettingsView(
                        vehicleManager:vehicleManager,
                        selectedTheme:Binding(get:{selectedTheme},set:{storedThemeRaw=$0.rawValue}),
                        speedLimit:$speedLimit,isHudMode:$isHudMode,useCustomColor:$useCustomColor,
                        customColor:Binding(
                            get:{Color(rawValue:customColorRaw) ?? Color(red:1.0,green:0.3,blue:0.4)},
                            set:{customColorRaw=$0.rawValue}),
                        isNetworkBoostEnabled:$isNetworkBoostEnabled,simulatedSpeed:$simulatedSpeed,
                        enableSakuraBackground:$enableSakuraBackground,sakuraDensity:$sakuraDensity,
                        borderWidth:$borderWidth,animSpeed:$animSpeed
                    ),isActive:$showSettings) { EmptyView() }
                    NavigationLink(destination:HistoryRecordsView(records:$historyRecords),isActive:$showHistoryRecords) { EmptyView() }
                    NavigationLink(destination:PerformanceTestDashboardView(vehicleManager:vehicleManager,primaryColor:currentPrimaryColor),isActive:$showPerformanceView) { EmptyView() }
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        .statusBarHidden(true)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func sideButton(icon:String,label:String,bg:Color,fg:Color,border:Color? = nil,action:@escaping()->Void) -> some View {
        Button(action:action) {
            VStack(spacing:3) {
                Image(systemName:icon).font(.system(size:14))
                Text(label).font(.system(size:8,weight:.bold,design:.monospaced))
            }
            .frame(width:50,height:50).background(bg).foregroundColor(fg).cornerRadius(14)
            .overlay(Group {
                if let b = border { RoundedRectangle(cornerRadius:14).stroke(b,lineWidth:1) }
            })
        }
    }

    private func updateOverspeedState(for speed: Double) {
        if speed > speedLimit {
            guard !flashWarning else { return }
            flashWarning = true
            overspeedStartedAt = Date()
            AudioServicesPlaySystemSound(1005)
            overspeedLogs.append(OverspeedRecord(id:UUID(),date:Date(),speed:speed,speedLimit:speedLimit))
            if overspeedLogs.count > 1_000 { overspeedLogs.removeFirst(overspeedLogs.count - 1_000) }
            overspeedTimer?.invalidate()
            withAnimation { showJapaneseOverspeedAlert = true }
            overspeedTimer = Timer.scheduledTimer(withTimeInterval:7.0,repeats:false) { _ in
                withAnimation { showJapaneseOverspeedAlert = false }
            }
        } else {
            if let startedAt = overspeedStartedAt {
                vehicleManager.overspeedDurationSeconds += Date().timeIntervalSince(startedAt)
                overspeedStartedAt = nil
            }
            flashWarning = false
        }
    }
}
