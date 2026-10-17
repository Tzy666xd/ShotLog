import SwiftUI
import Charts
import Photos
import PhotosUI
import Foundation
import AppKit
import CoreLocation
import ImageIO

// MARK: - colours
extension Color {
    init(hex: UInt) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255.0,
                  green: Double((hex >> 8) & 0xff) / 255.0,
                  blue: Double(hex & 0xff) / 255.0, opacity: 1.0)
    }
}

enum Luma {
    static let accent = Color(hex: 0x27A07F)
    static let aiEstimate = Color(hex: 0xC2410C)
    static let ok = Color(hex: 0x1F7F69)
    static let warn = Color(hex: 0xE07A3E)
    static let danger = Color(hex: 0xB45309)
    static let ink = Color(hex: 0x22323B)
    static let muted = Color(hex: 0x9AA3AC)
    static let cardLight = Color(hex: 0xFCFAF6)
    static let bgLight = Color(hex: 0xFBFAF4)
    static let cardDark = Color(hex: 0x2A2B2E)
    static let bgDark = Color(hex: 0x1B1C1E)
    static let sp4: CGFloat = 4
    static let sp16: CGFloat = 16
    static let sp32: CGFloat = 32
    static let sp24: CGFloat = 24
    static let radius: CGFloat = 18
}
private func schemeCard(_ cs: ColorScheme) -> Color { cs == .dark ? Luma.cardDark : Luma.cardLight }
private func schemeBg(_ cs: ColorScheme) -> Color { cs == .dark ? Luma.bgDark : Luma.bgLight }

// MARK: - enum domain
enum LightEnvironment: String, CaseIterable, Equatable {
    case daylight = "日光", dusk = "黄昏", night = "夜间", dim = "室内弱光"
    var id: String { rawValue }
    var icon: String {
        switch self { case .daylight: return "sun.max"; case .dusk: return "sunrise";
        case .night: return "moon.stars"; case .dim: return "lightswitch" }
    }
}
enum SceneType: String, CaseIterable, Equatable {
    case portrait = "人像", landscape = "风景", night = "夜景", indoor = "室内", action = "运动抓拍"
    var id: String { rawValue }
    var icon: String {
        switch self { case .portrait: return "person.crop.rectangle"; case .landscape: return "mountain.2";
        case .night: return "moon.stars"; case .indoor: return "house"; case .action: return "figure.run" }
    }
}
enum ShotSupport: String, CaseIterable, Equatable { case handheld = "手持", tripod = "三脚架"; var id: String { rawValue } }
enum ExposureResult: String, CaseIterable, Equatable { case normal = "正常", blown = "过曝", under = "欠曝"; var id: String { rawValue } }
enum MetaSource: String, CaseIterable, Equatable, Codable { case exif = "EXIF 原始拍摄数据", ai = "AI 估算"; var id: String { rawValue } }
enum Grant: String { case notDetermined, restricted, denied, authorized, limited
    static func fromPH(_ s: PHAuthorizationStatus) -> Grant {
        switch s { case .authorized: return .authorized; case .limited: return .limited;
        case .denied: return .denied; case .restricted: return .restricted; case .notDetermined: return .notDetermined;
        @unknown default: return .restricted } }
}
/// 「照片」页列表的展示密度——可自由切换，每档对应不同的 ui 布局。
enum ListDensity: String, CaseIterable, Identifiable {
    case compact = "紧凑", comfortable = "适中", grid = "网格", gallery = "画廊"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .compact: return "list.bullet"
        case .comfortable: return "list.bullet.indent"
        case .grid: return "rectangle.grid.2x2"
        case .gallery: return "rectangle.grid.3x2"
        }
    }
    /// 列表/网格里每张缩略图的边长（按方形）
    var thumbEdge: CGFloat {
        switch self {
        case .compact: return 56
        case .comfortable: return 88
        case .grid: return 140
        case .gallery: return 220
        }
    }
}

// MARK: - Tag / [小标记]
struct Tag: Identifiable, Equatable {
    let id = UUID()
    let text: String, icon: String?, tint: Color, source: TagSource
    init(_ text: String, icon: String? = nil, tint: Color = Luma.muted, source: TagSource = .exif) {
        self.text = text; self.icon = icon; self.tint = tint; self.source = source
    }
}
enum TagSource: Equatable { case exif, ai }
extension Tag {
    static func env(_ l: LightEnvironment) -> Tag { Tag(l.rawValue, icon: l.icon, tint: Luma.accent) }
    static func scene(_ s: SceneType) -> Tag { Tag(s.rawValue, icon: s.icon, tint: Luma.accent) }
    static func support(_ s: ShotSupport) -> Tag { Tag(s.rawValue, icon: "camera", tint: Luma.muted) }
    static func lens(_ t: String) -> Tag { Tag(t, icon: "camera.lens", tint: Luma.muted) }
    static func param(_ k: String, _ v: String) -> Tag { Tag("\(k) \(v)", icon: "dial.max.fill") }
    static func ok(_ t: String) -> Tag { Tag(t, tint: Luma.ok) }
    static func ai(_ t: String) -> Tag { Tag(t, tint: Luma.aiEstimate) }
    static func danger(_ t: String) -> Tag { Tag(t, tint: Luma.danger) }
}
/// 流式标签布局：芯片按内容宽度从左到右排满换行（macOS 13+ Layout 协议）。
struct FlowLayout: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, contentWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                contentWidth = max(contentWidth, x - hSpacing)
                x = 0; y += rowHeight + vSpacing; rowHeight = 0
            }
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
        contentWidth = max(contentWidth, x - hSpacing)
        return CGSize(width: proposal.width ?? contentWidth, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + vSpacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct TagView: View {
    let tag: Tag
    var body: some View {
        HStack(spacing: 5) {
            if let icon = tag.icon { Image(systemName: icon).font(.caption2) }
            Text(tag.text).font(.caption).fontWeight(.medium)
            if tag.source == .ai {
                Text("AI").font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1.5)
                    .background(Luma.aiEstimate, in: Capsule())
            }
        }
        .foregroundStyle(tag.tint)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(tag.tint.opacity(0.12), in: Capsule())
    }
}
struct TagsList: View {
    let tags: [Tag]
    var body: some View {
        FlowLayout { ForEach(tags) { TagView(tag: $0) } }
    }
}

// MARK: - shared card container
/// 苹果原生的分组卡片：标题 + 内容，圆角 16、描边加浅投影。
struct Card<Content: View>: View {
    let title: String?
    var trailing: String? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var cs
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.headline)
                    Spacer()
                    if let trailing { Text(trailing).font(.caption).foregroundStyle(.secondary) }
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Luma.ink.opacity(cs == .dark ? 0.12 : 0.06)))
        .shadow(color: .black.opacity(cs == .dark ? 0 : 0.05), radius: 10, y: 3)
    }
    private var cardBackground: Color { schemeCard(cs) }
}

// MARK: - liquid glass segmented control
/// macOS 26+ 原生「液态玻璃」分段控件——照片/统计/成长/提示那种，且**支持拖动切换**。
/// - 外层轨道是一个 `.glassEffect(.regular)` 的胶囊，承担「承载玻璃」的角色；
/// - 整块放进 `GlassEffectContainer` 让容器对内部玻璃形状做正确合成（折射、融合）；
/// - **滑块可拖**：拖动时玻璃胶囊用 `.offset(x:)` 实时跟手，松手吸附到最近档位；
/// - 三种输入都支持：点击档位、横向拖动滑块、方向键左右切档。
/// **不要自己用 `.ultraThinMaterial` + 圆角矩形拼**——既拿不到官方玻璃的折射/高光，
/// 也不会有跟手拖动的手感。
/// 分段控件的几何常量。放在文件作用域——Swift 不允许泛型类型里有 `static let` 存储属性。
private enum SegMetrics {
    static let trackPad: CGFloat = 4      // 轨道内边距
    static let sliderH: CGFloat = 32      // 滑块高
    static let controlH: CGFloat = 40     // 控件总高 = 4 + 32 + 4
}

struct LiquidGlassSegmented<Selection: Hashable & Sendable>: View {
    @Binding var selection: Selection
    let options: [(label: String, tag: Selection)]
    @Environment(\.colorScheme) private var cs

    /// 拖动位移。`@GestureState` 松手后自动归零，不用手动清理。
    @GestureState private var dragX: CGFloat = 0

    private var count: CGFloat { CGFloat(max(options.count, 1)) }
    private var currentIndex: Int { options.firstIndex { $0.tag == selection } ?? 0 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let segW = max(1, w / count)
            let pillW = max(0, segW - SegMetrics.trackPad * 2)
            let pad = SegMetrics.trackPad
            ZStack(alignment: .leading) {
                // ① 唯一的滑块：普通视图（不是玻璃），严格位于文字之下 → 绝不遮字
                Capsule()
                    .fill(Luma.accent.opacity(cs == .dark ? 0.30 : 0.22))
                    .overlay(Capsule().strokeBorder(Luma.accent.opacity(0.40), lineWidth: 0.5))
                    .frame(width: pillW, height: SegMetrics.sliderH)
                    .offset(x: pillX(total: w, pillW: pillW))
                    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: currentIndex)

                // ② 文字层，永远在最上面：选中项用主题色 + 加粗强调
                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                        Text(opt.label)
                            .font(.system(size: 13, weight: selection == opt.tag ? .semibold : .medium))
                            .foregroundStyle(selection == opt.tag ? Luma.accent : Luma.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: SegMetrics.sliderH)
                            .contentShape(Rectangle())
                    }
                }
            }
            .frame(width: w, height: SegMetrics.controlH)
            // ③ 整条控件的液态玻璃底：玻璃是「背景」，文字是它的内容，所以不会被盖
            .glassEffect(.regular, in: Capsule())
            .contentShape(Rectangle())
            .onMoveCommand { direction in
                switch direction {
                case .left:  commit(currentIndex - 1)
                case .right: commit(currentIndex + 1)
                default: break
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragX) { value, state, _ in state = value.translation.width }
                    .onEnded { value in
                        let moved = value.translation.width
                        let idx: Int
                        if abs(moved) < 6 {
                            // 点击：按落点选档
                            idx = Int((value.startLocation.x - pad) / segW)
                        } else {
                            // 拖动：按滑块最终落点吸附到最近一档
                            let finalX = pad + CGFloat(currentIndex) * segW + moved
                            idx = Int(round((finalX - pad) / segW))
                        }
                        commit(idx)
                    }
            )
        }
        .frame(height: SegMetrics.controlH)
        .focusable()
        .focusEffectDisabled()    // 保留键盘聚焦（左右方向键切档），但去掉系统蓝框焦点环
    }

    /// 滑块 X 落点 = 内边距 + 当前档位偏移 + 拖动位移，再夹进轨道内。
    private func pillX(total: CGFloat, pillW: CGFloat) -> CGFloat {
        let segW = max(1, total / count)
        let pad = SegMetrics.trackPad
        let maxX = max(pad, total - pillW - pad)
        return min(max(pad + CGFloat(currentIndex) * segW + dragX, pad), maxX)
    }

    /// 统一入口：夹到合法范围 → 弹簧动画切档。
    private func commit(_ index: Int) {
        let clamped = max(0, min(options.count - 1, index))
        guard clamped != currentIndex, options.indices.contains(clamped) else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            selection = options[clamped].tag
        }
    }
}

// MARK: - capture row
struct GroundTruthLocation: Codable, Equatable {
    let latitude: Double, longitude: Double
    init(_ la: Double, _ lo: Double) { self.latitude = la; self.longitude = lo }
}
struct ExifEntry: Identifiable, Codable, Equatable {
    let id = UUID()
    // id 是运行时标识，不参与编解码
    enum CodingKeys: String, CodingKey {
        case assetIdentifier, localURL, capturedAt, location, phoneModel, lens
        case focalLengthMm, aperture, shutterSpeed, iso, exposureComp, whiteBalance
        case flashOn, origin
    }
    let assetIdentifier: String
    let localURL: URL?
    let capturedAt: Date
    let location: GroundTruthLocation?
    let phoneModel: String?
    let lens: String?
    let focalLengthMm: Double?
    let aperture: Double?
    let shutterSpeed: String?
    let iso: Int?
    let exposureComp: Double?
    let whiteBalance: String?
    let flashOn: Bool?
    let origin: MetaSource
    var isAI: Bool { origin == .ai }
}

// MARK: - services (real Photos scanning + analyzers)
private enum Helper {
    struct AdviceItem: Identifiable, Equatable {
        let id = UUID()
        let title: String, text: String
    }

    /// 「只 fire 一次」的轻量哨兵，给 PHImageManager 这类「结果 handler 会被触发多次」的回调用，
    /// 防止 CheckedContinuation 被 resume 两次（第二次会触发 Swift 断言失败 + EXC_BREAKPOINT 闪退）。
    /// 用类包装（而不是 `var Bool`）是为了让多个 closure 实例共享同一份状态；
    /// PHImageManager 回调都在 main queue 派发，所以 read-modify-write 实际上串行安全，
    /// 但用类包装更稳，且不依赖未来的派发策略。
    final class ResumeOnce {
        private var fired = false
        func fire(_ block: () -> Void) {
            guard !fired else { return }
            fired = true
            block()
        }
    }

    /// 只负责扫描；相册授权由 ShotStore 统一处理，避免重复触发授权请求。
    static func scanPhotoLibrary() async -> [ExifEntry] {
        Helper.scanAssets()
    }
    static func scanAssets() -> [ExifEntry] {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        // 只取图片，避免 fetchLimit 被视频占满后一张图都扫不到
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        opts.fetchLimit = 500
        let assets = PHAsset.fetchAssets(with: opts)
        var out: [ExifEntry] = []
        for idx in 0 ..< assets.count {
            let asset = assets.object(at: idx)
            guard asset.mediaType == .image else { continue }
            if let entry = Helper.makeRealExifEntry(asset: asset) { out.append(entry) }
        }
        return out
    }
    static func makeRealExifEntry(asset: PHAsset) -> ExifEntry? {
        let opts = PHImageRequestOptions()
        // 同步模式在调用线程直接返回结果，避免用信号量阻塞协程线程池
        opts.isSynchronous = true
        opts.isNetworkAccessAllowed = true
        var data: Data?
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { d, _, _, _ in
            data = d
        }
        guard let data else { return nil }
        return Helper.makeEntry(asset: asset, image: data)
    }
    static func makeEntry(asset: PHAsset, image: Data) -> ExifEntry? {
        guard let src = CGImageSourceCreateWithData(image as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, [kCGImageSourceShouldCache as String: false] as CFDictionary) as? [String: Any]
        else { return nil }
        let location = asset.location.map { GroundTruthLocation($0.coordinate.latitude, $0.coordinate.longitude) }
        return Helper.parseEntry(props: props, capturedAt: asset.creationDate ?? Date(),
            location: location, assetIdentifier: asset.localIdentifier, localURL: nil)
    }

    /// 从 CGImageSource 属性字典生成分析条目。
    /// 机型在 {TIFF} 字典、拍摄参数在 {Exif} 字典——顶层键只能读到像素尺寸等少数信息。
    static func parseEntry(props: [String: Any], capturedAt: Date, location: GroundTruthLocation?,
                           assetIdentifier: String, localURL: URL?) -> ExifEntry {
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let focal = Helper.number(exif, "FocalLength")
        let aperture = Helper.number(exif, "FNumber")
        let iso = (exif["ISOSpeedRatings"] as? [NSNumber])?.first?.intValue
        let shutterCaptured = Helper.number(exif, "ExposureTime")
        let ev = Helper.number(exif, "ExposureBiasValue")
        // Flash 位 0 才代表“已触发”，整值转 Bool 会把 0x10（未触发）误判为开启
        let flashNum = (exif["Flash"] as? NSNumber).map { ($0.intValue & 0x1) == 1 }
        let camera = tiff["Model"] as? String
        let shutter: String? = { s in
            guard let s, s > 0 else { return nil }
            if s >= 1.0 { return String(format: "%.1fs", s) }
            return String(format: "1/%.0f", 1.0 / s)
        }(shutterCaptured)
        let lensModel = exif["LensModel"] as? String
        let lens = { (l: String?, f: Double?) -> String? in
            if let l, !l.isEmpty { return l }
            if let f { return String(format: "%.0fmm", f) }
            return nil
        }(lensModel, focal)
        let wb = (exif["WhiteBalance"] as? NSNumber).map { $0.intValue == 0 ? "自动" : "手动" }
        return ExifEntry(assetIdentifier: assetIdentifier, localURL: localURL,
            capturedAt: capturedAt, location: location,
            phoneModel: camera, lens: lens, focalLengthMm: focal,
            aperture: aperture, shutterSpeed: shutter, iso: iso,
            exposureComp: ev, whiteBalance: wb, flashOn: flashNum,
            origin: .exif)
    }

    /// 先选照片再读信息：用户在导入视图里勾选了 asset 标识符后，由这里并发解析 EXIF。
    /// 每张照片开一张 Task，互不阻塞；的结果在调用方合并去重。
    static func parseSelection(_ identifiers: [String]) async -> [ExifEntry] {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: opts)
        guard fetched.count > 0 else { return [] }
        return await withTaskGroup(of: (PHAsset, Data?).self) { group in
            for idx in 0 ..< fetched.count {
                let a = fetched.object(at: idx)
                group.addTask { await Helper._imageDataFor(a) }
            }
            var results: [(PHAsset, Data?)] = []
            for await pair in group { results.append(pair) }
            return results.compactMap { pair -> ExifEntry? in
                guard let data = pair.1 else { return nil }
                return Helper.makeEntry(asset: pair.0, image: data)
            }
        }
    }

    /// PHImageManager.requestImageDataAndOrientation 的 async 适配器。
    /// 用 CheckedContinuation 替掉 DispatchSemaphore（后者阻塞 Swift Task 系统线程会卡死）。
    /// 允许联网下载 iCloud 照片，否则“优化存储”开启时勾选的照片会静默解析失败。
    /// 关键：`PHImageRequestOptions.deliveryMode` 默认就是 `.opportunistic`，
    /// 意味着 PHImageManager 会在「拿到低清版」和「拿到高清版」时各回调一次——结果 handler 会被触发两次。
    /// CheckedContinuation 第二次 `resume` 会直接 `_assertionFailure` + `EXC_BREAKPOINT` 闪退。
    /// 用 `Once` 哨兵守住只 resume 一次（取最后一次的高清版）。
    static func _imageDataFor(_ asset: PHAsset) async -> (PHAsset, Data?) {
        await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.isSynchronous = false
            opts.isNetworkAccessAllowed = true
            let once = ResumeOnce()
            let block: @convention(block) (Data?, String?, CGImagePropertyOrientation, [AnyHashable: Any]?) -> Void = { d, _, _, _ in
                once.fire { cont.resume(returning: (asset, d)) }
            }
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts, resultHandler: block)
        }
    }

    /// 相册网格用缩略图：async 版本的 requestImage 适配器。
    static func thumbnail(for asset: PHAsset, size: CGFloat) async -> Image? {
        await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            // 关键三件事，把「糊到看不出是张照片」的概率压到最低：
            // 1. deliveryMode = .opportunistic：回调会先到一次 fastFormat（让 UI 立刻有东西），
            //    再到一次 highQualityFormat（清晰版）——所以必须用 ResumeOnce 守住只 resume 一次，
            //    否则第二次 resume 会触发 Swift assertionFailure 直接 SIGTRAP 闪退。
            // 2. isNetworkAccessAllowed = true：iCloud 优化照片在本地只存缩略图，不开网络就只能
            //    拿到那张「蒙了马赛克」的小图。
            // 3. resizeMode = .exact：按 targetSize 精确缩放，避免 fast 模式按比例放大取错尺寸。
            opts.deliveryMode = .opportunistic
            opts.isNetworkAccessAllowed = true
            opts.resizeMode = .exact
            opts.version = .current
            let once = ResumeOnce()
            PHImageManager.default().requestImage(for: asset,
                targetSize: .init(width: Int(size), height: Int(size)),
                contentMode: .aspectFill, options: opts) { image, _ in
                once.fire { cont.resume(returning: image.map { Image(nsImage: $0) }) }
            }
        }
    }
    static func thumbnailForAsset(id: String, size: CGFloat) async -> Image? {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard fetched.count > 0 else { return nil }
        return await thumbnail(for: fetched.object(at: 0), size: size)
    }
    static func number(_ d: [String: Any], _ key: String) -> Double? { (d[key] as? NSNumber)?.doubleValue }

    // --- formatters ---
    static func fmtAperture(_ v: Double?) -> String { v.map { "f/\($0)" } ?? "—" }
    static func fmtFocal(_ v: Double?) -> String { v.map { String(format: "%.0fmm", $0) } ?? "—" }
    static func fmtISO(_ v: Int?) -> String { v.map { "ISO \($0)" } ?? "—" }
    static func fmtComp(_ v: Double?) -> String { v.map { String(format: "%.1f EV", $0) } ?? "—" }
    static func fmtShutter(_ v: String?) -> String { v ?? "—" }

    /// 列表行的参数摘要：光圈 · 快门 · ISO，缺省的自动略过。
    static func paramSummary(_ e: ExifEntry) -> String {
        var parts: [String] = []
        if let a = e.aperture {
            parts.append(a == a.rounded() ? String(format: "f/%.0f", a) : String(format: "f/%.1f", a))
        }
        if let s = e.shutterSpeed { parts.append(s) }
        if let iso = e.iso { parts.append("ISO \(iso)") }
        return parts.isEmpty ? "无拍摄参数" : parts.joined(separator: " · ")
    }

    static func secondsOf(_ s: String?) -> Double? {
        guard let s else { return nil }
        if s.contains("/"), let slash = s.firstIndex(of: "/") {
            let num = s[s.startIndex ..< slash]
            let den = s[s.index(after: slash) ..< s.endIndex]
            guard let n = Double(num), let d = Double(den), d != 0 else { return nil }
            return n / d
        }
        // 兼容长曝光格式 "2.0s"
        if s.hasSuffix("s") { return Double(String(s.dropLast())) }
        return Double(s)
    }

    static func analyzeLight(_ e: ExifEntry) -> LightEnvironment {
        let hour = Calendar.current.component(.hour, from: e.capturedAt)
        if hour >= 20 || hour < 6 { return .night }
        if hour >= 17 { return .dusk }
        if hour >= 9 { return .daylight }
        return .dim
    }
    static func analyzeScene(_ e: ExifEntry) -> SceneType {
        let hour = Calendar.current.component(.hour, from: e.capturedAt)
        if hour >= 20 || hour < 6 { return .night }
        if e.flashOn == true { return .indoor }
        if let f = e.focalLengthMm {
            if f >= 50 { return .portrait }
            if f <= 20 { return .landscape }
        }
        return .landscape
    }
    static func analyzeSupport(_ e: ExifEntry) -> ShotSupport? {
        if e.isAI { return nil }
        // 只有整秒及以上的长曝光才推断为三脚架；1/30 这类慢门手持也很常见
        let sec = Helper.secondsOf(e.shutterSpeed) ?? 0
        return sec >= 1.0 ? .tripod : .handheld
    }
    static func adviseFor(_ e: ExifEntry) -> [AdviceItem] {
        var out: [AdviceItem] = []
        if let iso = e.iso, iso > 1600 {
            out.append(AdviceItem(title: "高ISO噪点风险", text: String(format: "ISO %d 容易产生噪点", iso)))
        }
        if let sec = Helper.secondsOf(e.shutterSpeed), sec > 1.0 / 30.0 {
            out.append(AdviceItem(title: "慢快门糊片风险", text: String(format: "%.2f 秒快门对手持较慢", sec)))
        }
        if let ev = e.exposureComp, (ev > 1.3 || ev < -1.3) {
            out.append(AdviceItem(title: ev > 1.3 ? "过曝" : "欠曝",
                text: String(format: "曝光补偿 %.1f EV", ev)))
        }
        if out.isEmpty { out.append(AdviceItem(title: "曝光正常", text: "各项指标健康")) }
        return out
    }

    static func lensLabel(_ e: ExifEntry) -> String {
        guard let f = e.focalLengthMm else { return "其他" }
        if f < 24 { return "超广角" }
        if f >= 50 { return "长焦" }
        return "主摄"
    }
}

// MARK: - stats models
/// 统计页的时间范围过滤。
enum StatsRange: String, CaseIterable, Identifiable, Sendable {
    case all = "全部", y1 = "近 1 年", d90 = "近 90 天", d30 = "近 30 天", d7 = "近 7 天"
    var id: String { rawValue }
    var days: Int? {
        switch self {
        case .all: return nil
        case .y1: return 365
        case .d90: return 90
        case .d30: return 30
        case .d7: return 7
        }
    }
}
struct TimeBucket: Identifiable, Equatable {
    let id = UUID()
    let hour: Int, label: String, count: Int
}
struct LensUsage: Identifiable, Equatable {
    let id = UUID()
    let label: String, count: Int
}
/// 直方图的一根柱子。
struct DistBucket: Identifiable, Equatable {
    let id = UUID()
    let label: String, count: Int
}
/// 通用「名称 + 次数」，用于机型、焦段等排行。
struct NamedCount: Identifiable, Equatable {
    let id = UUID()
    let name: String, count: Int
}
/// 月度趋势上的一个点。
struct MonthPoint: Identifiable, Equatable {
    let date: Date, label: String, count: Int
    /// 用日期做稳定 id。**不能写 `let id = UUID()`**——每次实例化都生成新值，
    /// SwiftUI Charts 会把每帧都当成全新数据、整张图重建（白白的滚动开销）。
    var id: TimeInterval { date.timeIntervalSince1970 }
}
/// 健康度的一个分项。
/// 用 struct 而不是元组——ForEach 的 id 键路径取不到元组元素。
struct HealthRow: Identifiable, Equatable {
    let id = UUID()
    let name: String, value: Int, weight: Int, hint: String
}
/// 拍摄习惯健康度：五个分项加权得总分，越高越好。
/// 焦段与题材分开计分——焦段看「用了几个焦段档」，题材看「场景分布是否又广又匀」。
/// 两者都用香农熵而不是单纯数档位个数：只数个数的话，一张冷门片就能把分刷上去。
struct HealthScore: Equatable {
    let exposure: Int, stability: Int, coverage: Int, focal: Int, subject: Int
    var total: Int {
        Int(Double(exposure)  * 0.25
          + Double(stability) * 0.20
          + Double(coverage)  * 0.15
          + Double(focal)     * 0.20
          + Double(subject)   * 0.20)
    }
    var grade: String {
        switch total {
        case 85...: return "优秀"
        case 70...: return "良好"
        case 55...: return "一般"
        default: return "待提升"
        }
    }
    var tint: Color {
        switch total {
        case 85...: return Luma.ok
        case 70...: return Luma.accent
        case 55...: return Luma.warn
        default: return Luma.danger
        }
    }
    var rows: [HealthRow] {
        [HealthRow(name: "曝光控制", value: exposure,  weight: 25, hint: "过曝 / 欠曝越少越好"),
         HealthRow(name: "手持稳定", value: stability, weight: 20, hint: "慢门糊片风险越低越好"),
         HealthRow(name: "焦段多样", value: focal,     weight: 20, hint: "用到的焦段档位越丰富越好"),
         HealthRow(name: "题材多样", value: subject,   weight: 20, hint: "场景分布又广又匀才得分"),
         HealthRow(name: "数据完整", value: coverage,  weight: 15, hint: "EXIF 原始参数占比")]
    }
    /// 最拖后腿的一项，用于在评分卡上给一句直接的建议。
    var weakest: HealthRow? { rows.min(by: { $0.value < $1.value }) }
}
struct GlobalStats: Equatable {
    let total: Int, aiCount: Int, exifCount: Int
    let buckets: [TimeBucket]
    let sceneCounts: [SceneType: Int]
    let lightCounts: [LightEnvironment: Int]
    let supportCounts: [ShotSupport: Int]
    let lensUsage: [LensUsage]
    let cameraModels: [NamedCount]
    let meanISO: Double, slowShutterRate: Double
    let blurRate: Double, blownRate: Double, underRate: Double
    let flashRate: Double, goldenRate: Double
    /// 连续参数直方图
    let isoBuckets: [DistBucket]
    let apertureBuckets: [DistBucket]
    let shutterBuckets: [DistBucket]
    let focalBuckets: [DistBucket]
    let evBuckets: [DistBucket]
    /// 星期分布，下标 0 = 周一 … 6 = 周日
    let weekday: [Int]
    /// 热力图 [周一…周日][3 小时档 0…7]
    let heat: [[Int]]
    let monthly: [MonthPoint]
    let activeDays: Int
    let perDay: Double
    let busiestDay: Date?
    let busiestCount: Int
    let topSceneLabel: String?
    let topFocalLabel: String?
    let health: HealthScore
}
private enum StatUtility {
    /// 把一组数值按给定区间切成直方图。
    private static func dist(_ values: [Double], _ bands: [(String, (Double) -> Bool)]) -> [DistBucket] {
        bands.map { label, test in DistBucket(label: label, count: values.filter(test).count) }
    }

    /// 分布多样性：0…1，越大越「又广又匀」。
    /// `ceiling` = 拿满分需要覆盖的档位数（焦段取 4，题材取 5）。
    /// spread 防止「只拍一类但分布均匀」骗到高分，uniformity 防止「每类各一张」骗到高分。
    private static func evenness(_ counts: [Int], ceiling: Int) -> Double {
        let total = counts.reduce(0, +)
        guard total > 0, ceiling > 1 else { return 0 }
        let h = counts.reduce(0.0) { acc, c in
            guard c > 0 else { return acc }
            let p = Double(c) / Double(total)
            return acc - p * log(p)
        }
        let spread = min(1.0, Double(counts.filter { $0 > 0 }.count) / Double(ceiling))
        let uniformity = h / log(Double(ceiling))
        return min(1.0, spread * 0.45 + uniformity * 0.55)
    }

    static func compute(_ es: [ExifEntry], range: StatsRange = .all) -> GlobalStats {
        let cal = Calendar.current
        // —— 时间范围过滤 ——
        let list: [ExifEntry] = {
            guard let d = range.days,
                  let from = cal.date(byAdding: .day, value: -d, to: Date()) else { return es }
            return es.filter { $0.capturedAt >= from }
        }()

        let total = list.count
        let real = list.filter { !$0.isAI }
        let aiCount = total - real.count
        // 失误率的分母用 EXIF 条目数，避免 AI 估算条目把比率稀释
        let realCount = max(real.count, 1)

        // —— 曝光与失误 ——
        let isoValues = real.compactMap { e in e.iso }.map { v in Double(v) }
        let secList = real.compactMap { e in Helper.secondsOf(e.shutterSpeed) }
        let slowCount = secList.filter { $0 > 1.0 / 60.0 }.count
        let blurCount = real.filter { ($0.iso ?? 0) > 1600 || (Helper.secondsOf($0.shutterSpeed) ?? 0) > 1.0 / 30.0 }.count
        let blownCount = real.filter { ($0.exposureComp ?? 0) > 1.3 }.count
        let underCount = real.filter { ($0.exposureComp ?? 0) < -1.3 }.count
        let flashCount = real.filter { $0.flashOn == true }.count

        let meanISO = isoValues.isEmpty ? 0 : isoValues.reduce(0, +) / Double(isoValues.count)
        let slowShutterRate = Double(slowCount) / Double(realCount)
        let blurRate = Double(blurCount) / Double(realCount)
        let blownRate = Double(blownCount) / Double(realCount)
        let underRate = Double(underCount) / Double(realCount)
        let flashRate = Double(flashCount) / Double(realCount)

        // —— 时段（4 小时档）+ 黄金时刻 ——
        let starts = [0, 4, 8, 12, 16, 20]
        var tCounts = Array(repeating: 0, count: 6)
        var golden = 0
        for e in list {
            let h = cal.component(.hour, from: e.capturedAt)
            tCounts[max(0, min(h / 4, 5))] += 1
            // 日出后 / 日落前，用整点近似
            if (h >= 5 && h < 8) || (h >= 16 && h < 19) { golden += 1 }
        }
        let buckets = starts.enumerated().map { i, hour in
            TimeBucket(hour: hour, label: "\(hour)-\(i == 5 ? 24 : starts[i + 1])", count: tCounts[i])
        }
        let goldenRate = total == 0 ? 0 : Double(golden) / Double(total)

        // —— 星期 + 热力图（7 天 × 8 个 3 小时档）——
        var weekday = Array(repeating: 0, count: 7)
        var heat = Array(repeating: Array(repeating: 0, count: 8), count: 7)
        var dayCounter: [String: (Date, Int)] = [:]
        for e in list {
            // Calendar 的 weekday 以周日为 1，(w + 5) % 7 转成周一为 0
            let mondayFirst = (cal.component(.weekday, from: e.capturedAt) + 5) % 7
            weekday[mondayFirst] += 1
            let h = cal.component(.hour, from: e.capturedAt)
            heat[mondayFirst][max(0, min(h / 3, 7))] += 1
            let c = cal.dateComponents([.year, .month, .day], from: e.capturedAt)
            let key = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
            if let cur = dayCounter[key] { dayCounter[key] = (cur.0, cur.1 + 1) }
            else { dayCounter[key] = (e.capturedAt, 1) }
        }
        let activeDays = dayCounter.count
        let perDay = activeDays == 0 ? 0 : Double(total) / Double(activeDays)
        let busiest = dayCounter.values.max(by: { $0.1 < $1.1 })
        let busiestDay = busiest?.0
        let busiestCount = busiest?.1 ?? 0

        // —— 月度趋势（最多 12 个月）——
        var monthMap: [String: (Date, Int)] = [:]
        for e in list {
            let c = cal.dateComponents([.year, .month], from: e.capturedAt)
            guard let y = c.year, let m = c.month,
                  let first = cal.date(from: DateComponents(year: y, month: m, day: 1)) else { continue }
            let key = "\(y)-\(m)"
            if let cur = monthMap[key] { monthMap[key] = (cur.0, cur.1 + 1) }
            else { monthMap[key] = (first, 1) }
        }
        let monthly = monthMap.values.sorted { $0.0 < $1.0 }.suffix(12).map { d, n in
            MonthPoint(date: d, label: "\(cal.component(.month, from: d))月", count: n)
        }

        // —— 连续参数分布 ——
        let apValues = real.compactMap { e in e.aperture }
        let focalValues = real.compactMap { e in e.focalLengthMm }
        let evValues = real.compactMap { e in e.exposureComp }
        let isoBuckets = dist(isoValues, [
            ("≤100", { $0 <= 100 }),
            ("101-400", { $0 > 100 && $0 <= 400 }),
            ("401-800", { $0 > 400 && $0 <= 800 }),
            ("801-1600", { $0 > 800 && $0 <= 1600 }),
            ("1601-3200", { $0 > 1600 && $0 <= 3200 }),
            (">3200", { $0 > 3200 })
        ])
        let apertureBuckets = dist(apValues, [
            ("≤1.8", { $0 <= 1.8 }),
            ("1.8-2.8", { $0 > 1.8 && $0 <= 2.8 }),
            ("2.8-4", { $0 > 2.8 && $0 <= 4 }),
            ("4-5.6", { $0 > 4 && $0 <= 5.6 }),
            ("5.6-8", { $0 > 5.6 && $0 <= 8 }),
            (">8", { $0 > 8 })
        ])
        let shutterBuckets = dist(secList, [
            ("≤1/1000", { $0 <= 1.0 / 1000 }),
            ("1/1000-1/250", { $0 > 1.0 / 1000 && $0 <= 1.0 / 250 }),
            ("1/250-1/60", { $0 > 1.0 / 250 && $0 <= 1.0 / 60 }),
            ("1/60-1/15", { $0 > 1.0 / 60 && $0 <= 1.0 / 15 }),
            ("1/15-1s", { $0 > 1.0 / 15 && $0 <= 1.0 }),
            (">1s", { $0 > 1.0 })
        ])
        let focalBuckets = dist(focalValues, [
            ("<16", { $0 < 16 }),
            ("16-24", { $0 >= 16 && $0 < 24 }),
            ("24-35", { $0 >= 24 && $0 < 35 }),
            ("35-50", { $0 >= 35 && $0 < 50 }),
            ("50-85", { $0 >= 50 && $0 < 85 }),
            ("85-135", { $0 >= 85 && $0 < 135 }),
            (">135", { $0 >= 135 })
        ])
        let evBuckets = dist(evValues, [
            ("≤-2", { $0 <= -2 }),
            ("-2~-1", { $0 > -2 && $0 <= -1 }),
            ("-1~-0.3", { $0 > -1 && $0 <= -0.3 }),
            ("±0.3", { $0 > -0.3 && $0 < 0.3 }),
            ("0.3~1", { $0 >= 0.3 && $0 < 1 }),
            ("1~2", { $0 >= 1 && $0 < 2 }),
            ("≥2", { $0 >= 2 })
        ])

        // —— 题材 / 光线 / 支撑 ——
        var scene: [SceneType: Int] = [:]
        var light: [LightEnvironment: Int] = [:]
        var support: [ShotSupport: Int] = [:]
        for e in list {
            scene[Helper.analyzeScene(e), default: 0] += 1
            light[Helper.analyzeLight(e), default: 0] += 1
            if let s = Helper.analyzeSupport(e) { support[s, default: 0] += 1 }
        }
        var lensC: [String: Int] = [:]
        for e in list { lensC[Helper.lensLabel(e), default: 0] += 1 }
        let orderedLens = lensC.sorted { $0.value > $1.value }.map { LensUsage(label: $0.key, count: $0.value) }
        var camC: [String: Int] = [:]
        for e in list {
            if let m = e.phoneModel?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
                camC[m, default: 0] += 1
            }
        }
        let cameraModels = camC.sorted { $0.value > $1.value }.map { NamedCount(name: $0.key, count: $0.value) }

        let topSceneLabel = scene.max(by: { $0.value < $1.value })?.key.rawValue
        let topFocalLabel = orderedLens.first?.label

        // —— 健康度评分 ——
        let exposureScore = Int(max(0, min(100, 100 - (blownRate + underRate) * 200)))
        let stabilityScore = Int(max(0, min(100, 100 - blurRate * 150)))
        let coverageScore = Int(min(100, Double(real.count) / Double(max(total, 1)) * 100))
        // 焦段多样：focalBuckets 共 7 档，用到 4 档即视为满分档位覆盖
        let focalScore = Int((evenness(focalBuckets.map(\.count), ceiling: 4) * 100).rounded())
        // 题材多样：5 种场景，覆盖 + 均匀各占一部分
        let sceneCounts = SceneType.allCases.map { scene[$0] ?? 0 }
        let subjectScore = Int((evenness(sceneCounts, ceiling: 5) * 100).rounded())
        let health = HealthScore(exposure: exposureScore, stability: stabilityScore,
                                 coverage: coverageScore, focal: focalScore, subject: subjectScore)

        return GlobalStats(
            total: total, aiCount: aiCount, exifCount: real.count,
            buckets: buckets, sceneCounts: scene,
            lightCounts: light, supportCounts: support,
            lensUsage: orderedLens, cameraModels: cameraModels,
            meanISO: meanISO, slowShutterRate: slowShutterRate,
            blurRate: blurRate, blownRate: blownRate, underRate: underRate,
            flashRate: flashRate, goldenRate: goldenRate,
            isoBuckets: isoBuckets, apertureBuckets: apertureBuckets,
            shutterBuckets: shutterBuckets, focalBuckets: focalBuckets, evBuckets: evBuckets,
            weekday: weekday, heat: heat, monthly: monthly,
            activeDays: activeDays, perDay: perDay,
            busiestDay: busiestDay, busiestCount: busiestCount,
            topSceneLabel: topSceneLabel, topFocalLabel: topFocalLabel,
            health: health
        )
    }
}

// MARK: - growth persistence
struct GrowSummary: Codable, Hashable {
    /// 快照取在每天 00:00，记录的是「这一天」而非「这一周」——历史最多留 8 条。
    let snapshotDay: Date, total: Int, aiCount: Int, meanISO: Double
    let blurRate: Double, blownRate: Double, underRate: Double
}
private enum GrowthStore {
    private static let base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ShotLog", isDirectory: true)
    private static let path: URL = base.appendingPathComponent("growth.json")
    static var all: [GrowSummary] {
        get {
            guard let data = try? Data(contentsOf: path) else { return [] }
            return (try? JSONDecoder().decode([GrowSummary].self, from: data)) ?? []
        }
        set {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
            if let data = try? JSONEncoder().encode(newValue) { try? data.write(to: path) }
        }
    }
    static func append(_ g: GrowSummary) {
        var all = GrowthStore.all
        // 去重：同一天多次调用只保留最新一份，避免重复堆项
        if let idx = all.firstIndex(where: { $0.snapshotDay == g.snapshotDay }) { all[idx] = g }
        else { all.append(g) }
        GrowthStore.all = all
    }
}

// MARK: - 选片记忆
/// 一次「选片」的快照：记住用户当时选了哪些照片，下次打开可以直接一键重新载入。
struct SavedSelection: Identifiable, Codable, Hashable {
    /// 来源：手动在选片器里勾选的，还是一键扫描全库的。
    enum Kind: String, Codable, CaseIterable { case manual = "手动选择", scan = "自动扫描" }

    let id: UUID
    var createdAt: Date
    var identifiers: [String]      // PHAsset.localIdentifier
    var kind: Kind

    init(identifiers: [String], kind: Kind) {
        self.id = UUID()
        self.createdAt = Date()
        self.identifiers = identifiers
        self.kind = kind
    }
    var count: Int { identifiers.count }
    /// 判定「同一批照片」：顺序无关，只看集合是否一致。
    var fingerprint: Set<String> { Set(identifiers) }
}

/// 选片记忆的持久化。最多留 6 条，最旧的自动挤出。
private enum SelectionMemory {
    private static let base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ShotLog", isDirectory: true)
    private static let path: URL = base.appendingPathComponent("selections.json")
    static let limit = 6

    static var all: [SavedSelection] {
        get {
            guard let data = try? Data(contentsOf: path) else { return [] }
            return (try? JSONDecoder().decode([SavedSelection].self, from: data)) ?? []
        }
        set {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
            if let data = try? JSONEncoder().encode(newValue) { try? data.write(to: path) }
        }
    }
    /// 记录一次选片。同一批照片（集合相同）只更新时间并提到最前，不重复堆积。
    static func remember(_ identifiers: [String], kind: SavedSelection.Kind) {
        guard !identifiers.isEmpty else { return }
        var all = SelectionMemory.all
        let fp = Set(identifiers)
        if let idx = all.firstIndex(where: { $0.fingerprint == fp }) {
            var existing = all.remove(at: idx)
            existing.createdAt = Date()
            existing.kind = kind
            all.insert(existing, at: 0)
        } else {
            all.insert(SavedSelection(identifiers: identifiers, kind: kind), at: 0)
            if all.count > limit { all = Array(all.prefix(limit)) }
        }
        SelectionMemory.all = all
    }
    static func remove(_ id: UUID) {
        var all = SelectionMemory.all
        all.removeAll { $0.id == id }
        SelectionMemory.all = all
    }
    static func clear() { SelectionMemory.all = [] }
}

// MARK: - store
@MainActor final class ShotStore: ObservableObject {
    @Published var entries: [ExifEntry] = []
    @Published var grant: Grant = .notDetermined
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var statusMessage = ""
    /// 历史选片记忆（落盘持久化，下次启动还在）。
    @Published var savedSelections: [SavedSelection] = SelectionMemory.all

    /// 「优化 app，不要每次打开都要获取权限，获取一次就够了」：
    /// 启动时**同步**读取系统里真实的授权状态并写回 grant，
    /// 这样 RootView 第一次渲染就能落在正确分支——
    /// 已授权的用户直接进 StartView，不会再掉进 PermissionView 又被推开一次。
    /// 注意：这里只读不请求；真正首次未确定时仍由 ensurePermission() 弹系统框。
    init() {
        grant = Grant.fromPH(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    /// 相册授权：只在需要时请求，避免启动即弹窗。
    func ensurePermission() async {
        if grant == .notDetermined {
            grant = Grant.fromPH(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
        } else {
            grant = Grant.fromPH(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        }
    }
    /// 用户在导入视图里勾选了资产标识符后，由这里并发解析 EXIF 并合并去重。
    func parseSelection(_ identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        isScanning = true
        statusMessage = "正在解析 \(identifiers.count) 张照片的 EXIF…"
        let parsed = await Helper.parseSelection(identifiers)
        var seen = Set(entries.map(\.assetIdentifier))
        for e in parsed where !seen.contains(e.assetIdentifier) {
            entries.append(e); seen.insert(e.assetIdentifier)
        }
        rememberSelection(identifiers, kind: .manual)
        hasScanned = true
        isScanning = false
        await persistWeekSnapshot()
    }
    /// 副入口：直接扫描相册最近的 500 张照片。
    func scanWholeLibrary() async {
        await ensurePermission()
        guard grant == .authorized || grant == .limited else { return }
        isScanning = true
        statusMessage = "正在扫描相册照片的 EXIF…"
        let scanned = await Helper.scanPhotoLibrary()
        entries = scanned
        rememberSelection(scanned.map(\.assetIdentifier), kind: .scan)
        hasScanned = true
        isScanning = false
        await persistWeekSnapshot()
    }
    /// 清空当前结果回到选片引导页。
    func reset() {
        entries = []
        hasScanned = false
        grant = Grant.fromPH(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }
    // MARK: 选片记忆
    /// 从记忆里载入一批照片。`replace = true` 先清空当前结果（从引导页进入），
    /// `false` 表示追加到现有分析（从主界面工具栏进入）。
    func loadSelection(_ identifiers: [String], replace: Bool) async {
        if replace { entries = [] }
        await parseSelection(identifiers)
    }
    func rememberSelection(_ identifiers: [String], kind: SavedSelection.Kind) {
        SelectionMemory.remember(identifiers, kind: kind)
        savedSelections = SelectionMemory.all
    }
    func forgetSelection(_ id: UUID) {
        SelectionMemory.remove(id)
        savedSelections = SelectionMemory.all
    }
    func clearSavedSelections() {
        SelectionMemory.clear()
        savedSelections = []
    }
    func persistWeekSnapshot() async {
        let stats = StatUtility.compute(entries)
        let start = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: Date()) ?? Date()
        let grow = GrowSummary(snapshotDay: start, total: stats.total, aiCount: stats.aiCount,
            meanISO: stats.meanISO, blurRate: stats.blurRate,
            blownRate: stats.blownRate, underRate: stats.underRate)
        GrowthStore.append(grow)
    }
}

// MARK: - views
struct PermissionView: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var cs
    var body: some View {
        VStack(spacing: Luma.sp24) {
            HeroBadge(systemName: "camera.aperture")
            VStack(spacing: 6) {
                Text("ShotLog").font(.largeTitle).bold()
                Text("照片拍摄行为分析 · 全程本地计算，数据不上传云端")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Luma.sp16) {
                StepRow(index: 1, title: "授权相册", text: "仅用于读取照片的拍摄参数（EXIF），不会修改或上传任何照片")
                StepRow(index: 2, title: "勾选照片", text: "在相册网格里挑选你想分析的照片，可多选")
                StepRow(index: 3, title: "查看分析", text: "查看每张的机型、镜头、快门、ISO，以及统计画像与拍摄建议")
            }
            .padding(Luma.sp24)
            .frame(maxWidth: 460)
            .background(schemeCard(cs), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Luma.ink.opacity(0.06)))
            Button("允许读取相册，开始", action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(Luma.sp32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(schemeBg(cs))
    }
}

struct AuthorityDeniedView: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var cs
    var body: some View {
        VStack(spacing: Luma.sp24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 52))
                .foregroundStyle(Luma.warn)
                .frame(width: 88, height: 88)
                .background(Luma.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            VStack(spacing: 6) {
                Text("相册权限未开启").font(.title2).bold()
                Text("ShotLog 无法读取相册，也不会上传任何数据到云端。\n可以在系统设置中重新开启访问权限。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("前往系统设置", action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(Luma.sp32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(schemeBg(cs))
    }
}

struct EmptyLibraryView: View {
    let repickAction: () -> Void
    let settingsAction: () -> Void
    @Environment(\.colorScheme) private var cs
    var body: some View {
        VStack(spacing: Luma.sp24) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .frame(width: 88, height: 88)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            VStack(spacing: 6) {
                Text("没能解析出照片").font(.title2).bold()
                Text("勾选的照片可能还没有从 iCloud 下载完成、不是照片文件，\n或受限模式下尚未允许访问。可以重新勾选再试一次。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("重新选择照片", action: repickAction).buttonStyle(.borderedProminent)
                Button("前往设置检查", action: settingsAction).buttonStyle(.bordered)
            }
        }
        .padding(Luma.sp32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(schemeBg(cs))
    }
}

private struct PermsManager {
    static func openSettings() {
        if let url = URL(string: "x-apple-settings:") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct EmptyStateView: View {
    let title: String, text: String
    var body: some View {
        VStack(spacing: Luma.sp16) {
            Image(systemName: "photo.on.photo")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.body).fontWeight(.semibold)
            Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Luma.sp32)
    }
}

/// 详情页顶部大图：异步加载，加载前显示占位底色。
struct HeroPhoto: View {
    let assetIdentifier: String
    @State private var image: Image? = nil
    var body: some View {
        ZStack {
            Rectangle().fill(Luma.muted.opacity(0.18))
            if let image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "photo").font(.title).foregroundStyle(Luma.muted)
            }
        }
        .task { image = await Helper.thumbnailForAsset(id: assetIdentifier, size: 700) }
    }
}

struct SingleShotView: View {
    let entry: ExifEntry
    @Environment(\.colorScheme) private var cs
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                sourceBanner
                Card(title: "拍摄参数") { paramRows }
                listEnvSection
                listAdviceSection
            }
            .padding(20)
        }
        .background(schemeBg(cs))
        .navigationTitle("拍摄解析")
    }
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            HeroPhoto(assetIdentifier: entry.assetIdentifier)
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .bottom, endPoint: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.phoneModel ?? "未知机型")
                    .font(.title3).bold().foregroundStyle(.white)
                Text(entry.capturedAt.formatted(.dateTime.year().month().day().hour().minute()))
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
            }
            .padding(14)
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    private var sourceBanner: some View {
        let isAI = entry.isAI
        return HStack(spacing: 6) {
            Image(systemName: isAI ? "sparkles" : "checkmark.seal.fill")
                .font(.caption)
            Text(isAI ? "本页分析基于 AI 推断，非原始拍摄数据" : "全部数据来自相机 EXIF / 原始拍摄")
            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(isAI ? Luma.aiEstimate : Luma.ok)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background((isAI ? Luma.aiEstimate : Luma.ok).opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private var paramRows: some View {
        VStack(spacing: 0) {
            paramRow("机型", entry.phoneModel ?? "—")
            paramRow("镜头", entry.lens ?? "无镜头数据")
            paramRow("焦距", Helper.fmtFocal(entry.focalLengthMm))
            paramRow("光圈", Helper.fmtAperture(entry.aperture))
            paramRow("快门", Helper.fmtShutter(entry.shutterSpeed))
            paramRow("ISO", Helper.fmtISO(entry.iso))
            paramRow("曝光补偿", Helper.fmtComp(entry.exposureComp))
            paramRow("白平衡", entry.whiteBalance ?? "—")
            paramRow("闪光灯", entry.flashOn.map { $0 ? "开启" : "关闭" } ?? "—")
        }
    }
    private func paramRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.medium)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            if label != "闪光灯" { Rectangle().fill(Luma.ink.opacity(0.06)).frame(height: 0.5) }
        }
    }
    private var listEnvSection: some View {
        let light = Helper.analyzeLight(entry)
        let scene = Helper.analyzeScene(entry)
        let support = Helper.analyzeSupport(entry)
        var tags: [Tag] = [Tag.env(light), Tag.scene(scene)]
        if let s = support { tags.append(Tag.support(s)) }
        if entry.isAI { tags.append(Tag.ai("环境已推测")) }
        return Card(title: "拍摄环境推断") { TagsList(tags: tags) }
    }
    private var listAdviceSection: some View {
        Card(title: "拍摄问题诊断") {
            VStack(spacing: 8) {
                ForEach(Helper.adviseFor(entry)) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Luma.warn)
                            .padding(6)
                            .background(Luma.warn.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline).fontWeight(.semibold)
                            Text(item.text).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Luma.ink.opacity(cs == .dark ? 0.18 : 0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}

struct LibraryView: View {
    @ObservedObject var store: ShotStore
    @State private var compareSheet: Bool = false
    /// macOS 原生 PhotosPicker（PHPickerViewController）选中的资产。
    /// `itemIdentifier` 就是 PHAsset.localIdentifier，可喂给现有的 parseSelection。
    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var segment: Int = 0
    @State private var density: ListDensity = .comfortable
    @Environment(\.colorScheme) private var cs
    var body: some View {
        VStack(spacing: 0) {
            LiquidGlassSegmented(selection: $segment,
                                 options: [("照片", 0), ("统计", 1), ("成长", 2), ("提示", 3)])
                .padding(.horizontal, 16).padding(.vertical, 10)
            Group {
                switch segment {
                case 0: listTab
                case 1: StatsView(store: store)
                case 2: GrowthView()
                default: TipsView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(schemeBg(cs))
        .navigationTitle("ShotLog")
        .navigationSubtitle("\(store.entries.count) 张照片 · 本地解析")
        .toolbar {
            ToolbarItemGroup {
                // 用 macOS 原生 PhotosPicker 替换之前自绘的相册网格。
                // SwiftUI 的 PhotosPicker 在 macOS 13+ 内部就是 PHPickerViewController，
                // 调起的是系统《照片》App 的选片界面——和你在《照片》App 里 Cmd+点击多选是一样的体验。
                PhotosPicker(selection: $pickerSelection,
                             maxSelectionCount: nil,
                             matching: .images,
                             photoLibrary: .shared()) {
                    Label("添加照片", systemImage: "plus")
                }
                .help("继续添加照片到分析中")
                .onChange(of: pickerSelection) { _, items in
                    let ids = items.compactMap(\.itemIdentifier)
                    guard !ids.isEmpty else { return }
                    Task {
                        await store.parseSelection(ids)
                        pickerSelection = []
                    }
                }
                if !store.savedSelections.isEmpty {
                    Menu {
                        ForEach(store.savedSelections) { item in
                            Button {
                                Task { await store.loadSelection(item.identifiers, replace: false) }
                            } label: {
                                Label("\(item.count) 张 · \(item.kind.rawValue)", systemImage: "photo.stack")
                            }
                        }
                        Divider()
                        Button(role: .destructive) { store.clearSavedSelections() } label: {
                            Label("清空选片记忆", systemImage: "trash")
                        }
                    } label: {
                        Label("历史选择", systemImage: "clock.arrow.circlepath")
                    }
                    .help("把之前选过的照片重新载入到当前分析中")
                }
                if segment == 0 { densityMenu }
                Button("对比") { compareSheet = true }
                    .disabled(store.entries.filter { !$0.isAI }.count < 2)
                    .help("至少需要 2 张带 EXIF 的照片才能对比")
            }
        }
        .overlay(alignment: .top) {
            if store.isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(store.statusMessage.isEmpty ? "正在处理…" : store.statusMessage)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                .padding(.top, 8)
            }
        }
        .sheet(isPresented: $compareSheet) { CompareView(store: store) }
    }

    // MARK: 工具栏密度菜单
    private var densityMenu: some View {
        Menu {
            Picker("显示密度", selection: $density) {
                ForEach(ListDensity.allCases) { d in
                    Label(d.rawValue, systemImage: d.icon).tag(d)
                }
            }
        } label: {
            Label(density.rawValue, systemImage: density.icon)
        }
        .help("切换照片列表的密度")
    }

    // MARK: 4 档密度分发
    @ViewBuilder
    private var listTab: some View {
        switch density {
        case .compact:    compactList
        case .comfortable: comfortableList
        case .grid:       gridList
        case .gallery:    galleryList
        }
    }

    // MARK: 紧凑：一行一图，最小信息密度
    private var compactList: some View {
        List {
            Section {
                ForEach(store.entries, id: \.assetIdentifier) { e in
                    NavigationLink(destination: SingleShotView(entry: e)) { compactRow(e) }
                }
            } header: {
                Text("已解析照片").font(.subheadline).fontWeight(.semibold).textCase(nil)
            } footer: {
                Text("点击任意一张查看完整的拍摄参数与问题诊断").font(.caption).textCase(nil)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(schemeBg(cs))
    }
    private func compactRow(_ e: ExifEntry) -> some View {
        HStack(spacing: 12) {
            EntryThumbView(assetIdentifier: e.assetIdentifier, edge: density.thumbEdge)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.phoneModel ?? "无 EXIF 拍摄数据")
                    .font(.body).fontWeight(.medium)
                Text(Helper.paramSummary(e))
                    .font(.caption).foregroundStyle(.secondary)
                Text(e.capturedAt.formatted(.dateTime.year().month().day().hour().minute()))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            sceneBadge(e, size: .small)
        }
        .padding(.vertical, 2)
    }

    // MARK: 适中：每行一图，缩略图更大，参数更突出
    private var comfortableList: some View {
        List {
            Section {
                ForEach(store.entries, id: \.assetIdentifier) { e in
                    NavigationLink(destination: SingleShotView(entry: e)) { comfortableRow(e) }
                }
            } header: {
                Text("已解析照片").font(.subheadline).fontWeight(.semibold).textCase(nil)
            } footer: {
                Text("点击任意一张查看完整的拍摄参数与问题诊断").font(.caption).textCase(nil)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(schemeBg(cs))
    }
    private func comfortableRow(_ e: ExifEntry) -> some View {
        HStack(spacing: 16) {
            EntryThumbView(assetIdentifier: e.assetIdentifier, edge: density.thumbEdge)
            VStack(alignment: .leading, spacing: 5) {
                Text(e.phoneModel ?? "无 EXIF 拍摄数据")
                    .font(.title3).fontWeight(.semibold)
                Text(Helper.paramSummary(e))
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(Luma.ink.opacity(0.85))
                Text(e.capturedAt.formatted(.dateTime.year().month().day().hour().minute()))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            sceneBadge(e, size: .regular)
        }
        .padding(.vertical, 6)
    }

    // MARK: 网格：3 列自适应，中等缩略图
    private var gridList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("已解析照片").font(.subheadline).fontWeight(.semibold)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 14) {
                    ForEach(store.entries, id: \.assetIdentifier) { e in
                        NavigationLink(destination: SingleShotView(entry: e)) { gridCell(e) }
                            .buttonStyle(.plain)
                    }
                }
                Text("点击任意一张查看完整的拍摄参数与问题诊断").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(schemeBg(cs))
    }
    private func gridCell(_ e: ExifEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            EntryThumbView(assetIdentifier: e.assetIdentifier, edge: density.thumbEdge)
            Text(e.phoneModel ?? "无机型信息")
                .font(.callout).fontWeight(.medium).lineLimit(1)
            Text(Helper.paramSummary(e))
                .font(.caption2).monospacedDigit()
                .foregroundStyle(.secondary).lineLimit(1)
            sceneBadge(e, size: .small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 画廊：自适应大列，大缩略图
    private var galleryList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("已解析照片").font(.subheadline).fontWeight(.semibold)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 18)], spacing: 20) {
                    ForEach(store.entries, id: \.assetIdentifier) { e in
                        NavigationLink(destination: SingleShotView(entry: e)) { galleryCell(e) }
                            .buttonStyle(.plain)
                    }
                }
                Text("点击任意一张查看完整的拍摄参数与问题诊断").font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(schemeBg(cs))
    }
    private func galleryCell(_ e: ExifEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            EntryThumbView(assetIdentifier: e.assetIdentifier, edge: density.thumbEdge)
            Text(e.phoneModel ?? "无机型信息")
                .font(.title3).fontWeight(.semibold).lineLimit(1)
            HStack {
                sceneBadge(e, size: .small)
                Spacer()
                Text(e.capturedAt.formatted(.dateTime.month().day()))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Text(Helper.paramSummary(e))
                .font(.subheadline).monospacedDigit()
                .foregroundStyle(Luma.ink.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 通用徽章（AI / 场景）
    @ViewBuilder
    private func sceneBadge(_ e: ExifEntry, size: BadgeSize) -> some View {
        let isAI = e.isAI
        let label: (text: String, icon: String, tint: Color) = isAI
            ? ("AI估算", "sparkles", Luma.aiEstimate)
            : (Helper.analyzeScene(e).rawValue, Helper.analyzeScene(e).icon, Luma.accent)
        Label(label.text, systemImage: label.icon)
            .font(size.font).fontWeight(.medium)
            .foregroundStyle(label.tint)
            .padding(.horizontal, size.padH).padding(.vertical, size.padV)
            .background(label.tint.opacity(0.12), in: Capsule())
    }
}

/// 徽章三档（紧凑/适中网格/适中列表），不同密度下字号和内边距不同。
private enum BadgeSize {
    case small, regular
    var font: Font { self == .small ? .caption2 : .caption }
    var padH: CGFloat { self == .small ? 6 : 8 }
    var padV: CGFloat { self == .small ? 3 : 4 }
}

/// 列表行/网格缩略图：按 assetIdentifier 异步取图。
/// `edge` = 显示边长（按方形裁剪），取图请求按 2× retina 索取以避免糊。
/// 主题适配：底色用 Luma.muted 透明度，浅色/深色背景下都不违和。
struct EntryThumbView: View {
    let assetIdentifier: String
    var edge: CGFloat = 56
    @State private var image: Image? = nil
    var body: some View {
        ZStack {
            Rectangle().fill(Luma.muted.opacity(0.25))
            if let image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: edge * 0.32))
                    .foregroundStyle(Luma.muted)
            }
        }
        .frame(width: edge, height: edge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: assetIdentifier) {
            image = await Helper.thumbnailForAsset(id: assetIdentifier, size: edge * 2)
        }
    }
}
// MARK: - 统计画像
/// 参数分布可切换的五个维度。
private let kDistTabs = ["ISO", "光圈", "快门", "焦距", "曝光"]
private let kDistNotes = [
    "ISO 越低画质越干净；整体偏高说明常在弱光下拍摄。",
    "光圈数值越小进光越多、背景越虚。",
    "快门越慢越容易糊；手机拍摄大多落在中段。",
    "焦距反映你偏爱的视角：广角拍景、长焦拍人。",
    "曝光补偿越集中在 0 附近，说明测光把控越稳。"
]
private let kWeekRows = ["一", "二", "三", "四", "五", "六", "日"]
private let kHourCols = ["0", "3", "6", "9", "12", "15", "18", "21"]

struct StatsView: View {
    @ObservedObject var store: ShotStore
    @Environment(\.colorScheme) private var cs
    @State private var range: StatsRange = .all
    @State private var distTab: Int = 0

    private var stats: GlobalStats { StatUtility.compute(store.entries, range: range) }

    var body: some View {
        let s = stats
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(s)
                rangePicker
                if s.total == 0 { emptyHint } else { content(s) }
            }
            .padding(20)
        }
        .background(schemeBg(cs))
    }

    @ViewBuilder
    private func content(_ s: GlobalStats) -> some View {
        scoreSection(s)
        overviewTiles(s)
        heatSection(s)
        trendSection(s)
        distSection(s)
        timeSection(s)
        deviceSection(s)
        sceneSection(s)
        errorSection(s)
        insightSection(s)
    }

    // MARK: 头部与时间范围
    private func header(_ s: GlobalStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("拍摄统计画像").font(.title2).bold()
            Text("共 \(s.total) 张 · EXIF \(s.exifCount) · AI 推算 \(s.aiCount)")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
    /// 时间范围切换：复用照片页那套液态玻璃分段控件，全 app 观感统一（可点可拖）。
    private var rangePicker: some View {
        LiquidGlassSegmented(
            selection: $range,
            options: StatsRange.allCases.map { (label: $0.rawValue, tag: $0) })
    }
    private var emptyHint: some View {
        Card(title: nil) {
            VStack(alignment: .leading, spacing: 6) {
                Text("这个时间范围内没有照片").font(.headline)
                Text("换一个更长的时间范围，或先在「照片」页添加照片。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 健康度
    private func scoreSection(_ s: GlobalStats) -> some View {
        let h = s.health
        return Card(title: "拍摄习惯健康度", trailing: "5 项加权 · 越高越好") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 20) {
                    ScoreRing(score: h.total, tint: h.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("综合得分").font(.caption).foregroundStyle(.secondary)
                        Text(h.grade).font(.title3).bold().foregroundStyle(h.tint)
                        if let w = h.weakest {
                            Text("短板：\(w.name) \(w.value) 分")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(h.rows) { r in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(r.name).font(.caption).fontWeight(.medium)
                                Text("\(r.weight)%")
                                    .font(.caption2).monospacedDigit()
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text("\(r.value)")
                                    .font(.caption).bold().monospacedDigit()
                                    .foregroundStyle(h.tint)
                            }
                            GeometryReader { geo in
                                Capsule().fill(Luma.ink.opacity(0.10))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(h.tint)
                                            .frame(width: max(3, CGFloat(r.value) / 100 * geo.size.width))
                                    }
                            }
                            .frame(height: 4)
                            Text(r.hint).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: 概览瓷砖
    private func overviewTiles(_ s: GlobalStats) -> some View {
        let tiles: [(String, String, String, Color)] = [
            ("\(s.total)", "张", "解析照片", Luma.accent),
            (String(format: "%.0f", s.meanISO), "", "平均 ISO", Luma.ink),
            (String(format: "%.1f", s.perDay), "张/天", "拍摄节奏", Luma.ok),
            (String(format: "%.0f%%", s.goldenRate * 100), "", "黄金时刻", Luma.warn)
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
            ForEach(0..<tiles.count, id: \.self) { i in
                let (value, unit, label, tint) = tiles[i]
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(value).font(.title2).bold().monospacedDigit().foregroundStyle(tint)
                        if !unit.isEmpty {
                            Text(unit).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(schemeCard(cs), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Luma.ink.opacity(0.06)))
            }
        }
    }

    // MARK: 星期 × 时段 热力图
    private func heatSection(_ s: GlobalStats) -> some View {
        let maxC = max(s.heat.flatMap { $0 }.max() ?? 1, 1)
        return Card(title: "拍摄生物钟", trailing: "星期 × 时段") {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(" ").frame(width: 16)
                    ForEach(kHourCols, id: \.self) { c in
                        Text(c).font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<7, id: \.self) { r in
                    HStack(spacing: 4) {
                        Text(kWeekRows[r]).font(.caption2).foregroundStyle(.secondary)
                            .frame(width: 16)
                        ForEach(0..<8, id: \.self) { c in
                            let v = s.heat[r][c]
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(v == 0
                                      ? Luma.ink.opacity(0.05)
                                      : Luma.accent.opacity(0.18 + 0.82 * (Double(v) / Double(maxC))))
                                .frame(height: 18)
                                .frame(maxWidth: .infinity)
                                .help("周\(kWeekRows[r]) · \(kHourCols[c]) 点后 · \(v) 张")
                        }
                    }
                }
                HStack(spacing: 5) {
                    Text("少").font(.caption2).foregroundStyle(.tertiary)
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Luma.accent.opacity(0.18 + 0.20 * Double(i)))
                            .frame(width: 12, height: 8)
                    }
                    Text("多").font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: 月度趋势
/// 月度趋势折线图（SwiftUI Charts 原生实现，自带悬停交互）。
/// - catmull-rom 平滑曲线 + 渐变面积，气质柔和
/// - 最新点用双层 PointMark 叠出「发光」效果
/// - 鼠标悬停：竖直参考线 + 数值气泡，气泡贴边自动收拢不会溢出卡片
private struct TrendChart: View {
    let points: [MonthPoint]
    @Environment(\.colorScheme) private var cs
    /// 悬停命中的数据点下标。`nil` = 鼠标不在图上。
    @State private var hoverIndex: Int? = nil

    var body: some View {
        Chart(Array(points.enumerated()), id: \.offset) { idx, p in
            AreaMark(
                x: .value("月份", p.date),
                y: .value("数量", p.count)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(LinearGradient(
                colors: [Luma.accent.opacity(0.32), Luma.accent.opacity(0)],
                startPoint: .top, endPoint: .bottom))

            LineMark(
                x: .value("月份", p.date),
                y: .value("数量", p.count)
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .foregroundStyle(Luma.accent)

            // 最新点：外圈半透明 + 内圈实心，营造发光质感
            if idx == points.count - 1 {
                PointMark(
                    x: .value("月份", p.date),
                    y: .value("数量", p.count)
                )
                .symbol(.circle)
                .symbolSize(160)
                .foregroundStyle(Luma.accent.opacity(0.22))

                PointMark(
                    x: .value("月份", p.date),
                    y: .value("数量", p.count)
                )
                .symbol(.circle)
                .symbolSize(70)
                .foregroundStyle(Luma.accent)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack {
                    // 悬停追踪层：用 ChartProxy 把 x 坐标**反查成日期**，再找时间上最近的点。
                    // 比"按索引等分宽度"更准——中间缺某个月时也不会偏到隔壁。
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                guard let d = proxy.value(atX: loc.x, as: Date.self) else { return }
                                hoverIndex = points.indices.min(by: { a, b in
                                    abs(points[a].date.timeIntervalSince(d))
                                        < abs(points[b].date.timeIntervalSince(d))
                                })
                            case .ended:
                                hoverIndex = nil
                            }
                        }

                    if let idx = hoverIndex, points.indices.contains(idx) {
                        let p = points[idx]
                        if let x = proxy.position(forX: p.date) {
                            if let y = proxy.position(forY: p.count) {
                                // 竖直参考线
                                Rectangle()
                                    .fill(Luma.accent.opacity(0.30))
                                    .frame(width: 1, height: max(0, geo.size.height - 28))
                                    .position(x: x, y: geo.size.height / 2)
                                // 悬停点：与最新点同样的双层发光
                                Circle().fill(Luma.accent.opacity(0.22))
                                    .frame(width: 16, height: 16).position(x: x, y: y)
                                Circle().fill(Luma.accent)
                                    .frame(width: 7, height: 7).position(x: x, y: y)
                                // 数值气泡
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.label).font(.caption2).foregroundStyle(.secondary)
                                    Text("\(p.count) 张")
                                        .font(.caption).fontWeight(.semibold).monospacedDigit()
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(schemeCard(cs),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Luma.accent.opacity(0.35), lineWidth: 1))
                                .position(x: min(max(x, 50), geo.size.width - 50),
                                          y: max(y - 32, 18))
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 150)
    }
}

    /// 拍摄量趋势卡片：现代极简风——大数字 + vs 上月变化 + SwiftUI Charts 平滑折线 + 底部摘要。
    /// 用原生 Charts 框架（macOS 13+）：catmull-rom 平滑曲线 + 渐变面积 + 最新点高亮 + 隐藏坐标轴。
    private func trendSection(_ s: GlobalStats) -> some View {
        let pts = s.monthly
        let total = pts.reduce(0) { $0 + $1.count }
        let avg = pts.isEmpty ? 0 : Double(total) / Double(pts.count)
        let last = pts.last
        let prev = pts.count >= 2 ? pts[pts.count - 2] : nil
        // vs 上月的百分比变化：上月为 0 时不计算，避免除零
        let delta: Int? = (last != nil && prev != nil && prev!.count > 0)
            ? Int(round(Double(last!.count - prev!.count) / Double(prev!.count) * 100))
            : nil

        return Card(title: "拍摄量趋势", trailing: pts.isEmpty ? nil : "近 \(pts.count) 个月") {
            if pts.isEmpty {
                Text("暂无数据").font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    // ① 主指标行：大数字 + 单位 + 右侧 vs 上月变化胶囊
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(total)")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("张").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        if let d = delta {
                            let up = d >= 0
                            HStack(spacing: 3) {
                                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                                    .font(.system(size: 10, weight: .bold))
                                Text("\(abs(d))%").font(.caption).fontWeight(.semibold).monospacedDigit()
                            }
                            .foregroundStyle(up ? Luma.accent : Luma.warn)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background((up ? Luma.accent : Luma.warn).opacity(0.14), in: Capsule())
                        }
                    }

                    // ② 图表 / 单点占位
                    if pts.count >= 2 {
                        TrendChart(points: pts)
                    } else {
                        Text("本月共拍 \(pts[0].count) 张 · 继续拍，下个月就有趋势看了。")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 22)
                    }

                    // ③ 底部摘要
                    HStack {
                        Text("月均 \(Int(avg.rounded())) 张").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if let l = last, pts.count > 1 {
                            Text("最新：\(l.label) · \(l.count) 张")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: 参数分布（可切换维度）
    private func distSection(_ s: GlobalStats) -> some View {
        let sets: [[DistBucket]] = [s.isoBuckets, s.apertureBuckets, s.shutterBuckets,
                                    s.focalBuckets, s.evBuckets]
        let idx = min(distTab, sets.count - 1)
        let buckets = sets[idx]
        let maxC = max(buckets.map { $0.count }.max() ?? 1, 1)
        let bucketTotal = buckets.reduce(0) { $0 + $1.count }
        return Card(title: "参数分布", trailing: "共 \(bucketTotal) 张") {
            VStack(alignment: .leading, spacing: 12) {
                LiquidGlassSegmented(
                    selection: $distTab,
                    options: kDistTabs.enumerated().map { (label: $0.element, tag: $0.offset) })
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(buckets) { b in
                        VStack(spacing: 4) {
                            Text("\(b.count)").font(.caption2).monospacedDigit()
                                .foregroundStyle(.secondary)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(b.count > 0 ? Luma.accent.opacity(0.85) : Luma.muted.opacity(0.30))
                                .frame(height: max(3, CGFloat(b.count) / CGFloat(maxC) * 70))
                            Text(b.label).font(.caption2).foregroundStyle(.tertiary)
                                .lineLimit(1).minimumScaleFactor(0.65)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                Text(kDistNotes[idx]).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 拍摄时段
    private func timeSection(_ s: GlobalStats) -> some View {
        let maxCount = max(s.buckets.map { $0.count }.max() ?? 1, 1)
        return Card(title: "拍摄时段", trailing: "按 4 小时分段") {
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(s.buckets) { b in
                    VStack(spacing: 6) {
                        Text("\(b.count)").font(.caption2).monospacedDigit()
                            .foregroundStyle(.secondary)
                        Capsule()
                            .fill(b.count > 0 ? Luma.accent : Luma.muted.opacity(0.35))
                            .frame(width: 26, height: CGFloat(max(b.count, 1)) / CGFloat(maxCount) * 96)
                        Text(b.label).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: 设备与焦段
    private func deviceSection(_ s: GlobalStats) -> some View {
        let camMax = max(s.cameraModels.map { $0.count }.max() ?? 1, 1)
        let lensMax = max(s.lensUsage.map { $0.count }.max() ?? 1, 1)
        return Card(title: "设备与焦段", trailing: s.cameraModels.isEmpty ? nil : "按使用频次") {
            VStack(alignment: .leading, spacing: 12) {
                if s.cameraModels.isEmpty {
                    Text("暂无机型数据").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(s.cameraModels.prefix(4))) { m in
                            shareRow(label: m.name, count: m.count, maxCount: camMax, tint: Luma.ink)
                        }
                    }
                }
                Divider().opacity(0.35)
                if s.lensUsage.isEmpty {
                    Text("暂无焦段数据").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(s.lensUsage) { l in
                            shareRow(label: l.label, count: l.count, maxCount: lensMax, tint: Luma.ok)
                        }
                    }
                }
            }
        }
    }

    // MARK: 题材与光线
    private func sceneSection(_ s: GlobalStats) -> some View {
        let sceneMax = max(SceneType.allCases.map { s.sceneCounts[$0] ?? 0 }.max() ?? 1, 1)
        return Card(title: "题材与光线", trailing: "按占比") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(SceneType.allCases, id: \.self) { st in
                        shareRow(label: st.rawValue, count: s.sceneCounts[st] ?? 0,
                                 maxCount: sceneMax, tint: Luma.accent)
                    }
                }
                Divider().opacity(0.35)
                HStack(alignment: .top, spacing: 10) {
                    ForEach(LightEnvironment.allCases, id: \.self) { le in
                        let n = s.lightCounts[le] ?? 0
                        VStack(spacing: 4) {
                            Image(systemName: le.icon).font(.system(size: 15))
                                .foregroundStyle(n > 0 ? Luma.accent : Luma.muted)
                            Text("\(n)").font(.caption).bold().monospacedDigit()
                            Text(le.rawValue).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Luma.ink.opacity(0.03),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                HStack(spacing: 10) {
                    miniStat("手持", "\(s.supportCounts[.handheld] ?? 0) 张")
                    miniStat("三脚架", "\(s.supportCounts[.tripod] ?? 0) 张")
                    miniStat("用闪光灯", pct(Int(s.flashRate * Double(s.exifCount)), s.exifCount))
                }
            }
        }
    }
    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline).bold().monospacedDigit().foregroundStyle(Luma.ink)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Luma.ink.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: 失误统计
    private func errorSection(_ s: GlobalStats) -> some View {
        let items: [(String, Double, Color)] = [
            ("糊片", s.blurRate, Luma.warn),
            ("过曝", s.blownRate, Luma.danger),
            ("欠曝", s.underRate, Luma.danger)
        ]
        return Card(title: "失误统计", trailing: "基于 EXIF 参数推断") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ForEach(0..<items.count, id: \.self) { i in
                        let (label, rate, tint) = items[i]
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(format: "%.1f%%", rate * 100))
                                .font(.title3).bold().monospacedDigit()
                                .foregroundStyle(rate > 0 ? tint : Luma.muted)
                            Text(label).font(.caption).foregroundStyle(.secondary)
                            Capsule().fill(tint.opacity(0.18)).frame(height: 4)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(tint).frame(width: min(CGFloat(rate) * 120, 120))
                                }
                                .frame(width: 120)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(tint.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                Text("糊片＝ISO > 1600 或快门慢于 1/30s；过曝 / 欠曝＝曝光补偿超出 ±1.3 EV。")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 自动洞察
    private func insightSection(_ s: GlobalStats) -> some View {
        let lines = insights(s)
        return Card(title: "从数据里读出来的", trailing: "自动生成") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<lines.count, id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(Luma.accent)
                            .frame(width: 14)
                        Text(lines[i]).font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: 小工具
    private func shareRow(label: String, count: Int, maxCount: Int, tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.subheadline).lineLimit(1)
                .frame(minWidth: 56, maxWidth: 110, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.12))
                Capsule().fill(count > 0 ? tint : tint.opacity(0.25))
                    .frame(width: max(6, CGFloat(count) / CGFloat(max(maxCount, 1)) * 190))
            }
            .frame(width: 190, height: 8)
            Text("\(count)").font(.subheadline).monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
    }
    private func pct(_ n: Int, _ total: Int) -> String {
        total == 0 ? "0%" : "\(Int(Double(n) / Double(max(total, 1)) * 100))%"
    }
    private func insights(_ s: GlobalStats) -> [String] {
        var out: [String] = []
        if s.total == 0 { return ["这个范围内还没有照片可分析。"] }
        if let top = s.buckets.max(by: { $0.count < $1.count }), top.count > 0 {
            out.append("你最爱在 \(top.label) 点之间按快门，占这个范围的 \(pct(top.count, s.total))。")
        }
        if s.goldenRate >= 0.25 {
            out.append("黄金时刻（日出后 / 日落前）的照片占 \(pct(Int(s.goldenRate * Double(s.total)), s.total))，光线时机把握得不错。")
        } else if s.goldenRate < 0.08, s.total >= 5 {
            out.append("黄金时刻只占 \(pct(Int(s.goldenRate * Double(s.total)), s.total))，试试日出后或日落前一小时出门。")
        }
        if s.meanISO > 1600 {
            out.append("平均 ISO \(Int(s.meanISO)) 偏高，弱光场景偏多，留意噪点。")
        } else if s.meanISO > 0, s.meanISO < 400 {
            out.append("平均 ISO 只有 \(Int(s.meanISO))，多数照片是在光线充足时拍的。")
        }
        let err = s.blurRate + s.blownRate + s.underRate
        if err >= 0.30 {
            out.append("失误率合计 \(Int(err * 100))%，留意快门速度与曝光补偿能快速改善。")
        } else if err < 0.08, s.exifCount >= 5 {
            out.append("失误率仅 \(Int(err * 100))%，曝光与稳定性控制得很好。")
        }
        if let f = s.topFocalLabel, let sc = s.topSceneLabel {
            out.append("最常用的视角是\(f)，拍得最多的是\(sc)题材。")
        }
        if let w = s.health.weakest {
            out.append("五项健康度里「\(w.name)」最低（\(w.value) 分），是当前最值得补的一环。")
        }
        if s.perDay >= 8 {
            out.append("拍摄节奏很密，活跃日平均 \(String(format: "%.1f", s.perDay)) 张。")
        }
        if let d = s.busiestDay, s.busiestCount >= 3 {
            out.append("最高产的一天是 \(d.formatted(.dateTime.month().day()))，一口气拍了 \(s.busiestCount) 张。")
        }
        return Array(out.prefix(6))
    }
}

/// 健康度总分环形图。
struct ScoreRing: View {
    let score: Int, tint: Color
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(score, 100))) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)").font(.title).bold().monospacedDigit().foregroundStyle(tint)
                Text("分").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
    }
}

// MARK: - 对比（并排参数表 + 差异高亮）
/// 对比表里的一行：参数名 + 每张照片的显示值 + 可比较的数值 + 「越大越好 / 越小越好 / 中性」
private struct CompareRow: Identifiable {
    enum Better { case lower, higher, neutral }
    let id: String
    let name: String
    let texts: [String]      // 与选中的照片一一对应
    let numbers: [Double?]   // nil = 该张没有可比数值（如机型、白平衡）
    let better: Better

    /// 这一行的值是否不全相同——决定要不要高亮
    var differs: Bool { Set(texts).count > 1 }

    private var scored: [(Int, Double)] {
        numbers.enumerated().compactMap { i, v in v.map { (i, $0) } }
    }
    /// 最优下标。只有「有优劣方向」且至少两个可比数值时才有意义。
    var bestIndex: Int? {
        guard better != .neutral, scored.count >= 2 else { return nil }
        return better == .lower ? scored.min(by: { $0.1 < $1.1 })?.0
                                : scored.max(by: { $0.1 < $1.1 })?.0
    }
    var worstIndex: Int? {
        guard better != .neutral, scored.count >= 2 else { return nil }
        return better == .lower ? scored.max(by: { $0.1 < $1.1 })?.0
                                : scored.min(by: { $0.1 < $1.1 })?.0
    }
}

struct CompareView: View {
    @ObservedObject var store: ShotStore
    @Environment(\.colorScheme) private var cs
    /// 用户手动挑的照片（存 assetIdentifier）。`nil` = 还没动过，默认最近 2 张带 EXIF 的。
    @State private var chosen: [String]? = nil
    /// 点缩略图看这张的完整解析
    @State private var detail: ExifEntry? = nil

    private var real: [ExifEntry] { store.entries.filter { !$0.isAI } }
    private var activeIDs: [String] { chosen ?? real.suffix(2).map(\.assetIdentifier) }
    private var selected: [ExifEntry] {
        activeIDs.compactMap { id in real.first { $0.assetIdentifier == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if selected.count >= 2 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        pickerStrip
                        tableCard
                        diffCard
                    }
                    .padding(16)
                }
            } else {
                EmptyStateView(title: "至少需要 2 张照片",
                               text: "选择更多带 EXIF 的照片后可进行对比")
            }
        }
        .frame(minWidth: 680, minHeight: 540)
        .background(schemeBg(cs))
        .sheet(item: $detail) { e in SingleShotView(entry: e) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("对比分析").font(.headline)
                Text("选 \(selected.count) 张并排比较 · 有差异的行自动高亮")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.left.arrow.right").foregroundStyle(Luma.accent)
        }
        .padding(16)
    }

    // MARK: 选片条
    /// 已选照片缩略图：点图看详情，右上角 × 移出对比；末尾一个「+」加人（最多 4 张）。
    private var pickerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(selected.enumerated()), id: \.element.id) { i, e in
                    chosenChip(e, index: i)
                }
                if selected.count < 4 { addMenu }
            }
            .padding(.vertical, 2)
        }
    }

    private func chosenChip(_ e: ExifEntry, index i: Int) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Button { detail = e } label: {
                    EntryThumbView(assetIdentifier: e.assetIdentifier, edge: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Luma.accent.opacity(0.45), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .help("查看这张的完整解析")

                Button {
                    guard selected.count > 2 else { return }
                    var next = activeIDs
                    next.removeAll { $0 == e.assetIdentifier }
                    chosen = next
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .background(Circle().fill(schemeBg(cs)))
                }
                .buttonStyle(.plain)
                .opacity(selected.count > 2 ? 1 : 0.4)
                .offset(x: 5, y: -5)
                .help(selected.count > 2 ? "移出对比" : "至少保留 2 张")
            }
            Text("照片 \(i + 1)").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 72)
    }

    private var addMenu: some View {
        // 只列没被选中的；最多翻最近 40 张，避免菜单过长
        let rest = real.filter { e in !activeIDs.contains(e.assetIdentifier) }
        return Menu {
            if rest.isEmpty {
                Text("没有更多照片了")
            } else {
                ForEach(rest.suffix(40)) { e in
                    Button {
                        guard selected.count < 4 else { return }
                        var next = activeIDs
                        next.append(e.assetIdentifier)
                        chosen = next
                    } label: {
                        Label(Helper.paramSummary(e), systemImage: "plus.circle")
                    }
                }
            }
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Luma.ink.opacity(cs == .dark ? 0.14 : 0.06))
                    .frame(width: 72, height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Luma.muted.opacity(0.7),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Luma.accent))
                Text("添加").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 72)
        }
        .menuStyle(.borderlessButton)
        .help("最多同时对比 4 张")
    }

    // MARK: 并排参数表
    private var tableCard: some View {
        Card(title: "参数并排", trailing: "有差异的行会高亮") {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("参数").frame(width: 76, alignment: .leading)
                    ForEach(0 ..< selected.count, id: \.self) { i in
                        Text("照片 \(i + 1)").frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.bottom, 8)
                Divider()
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Text(row.name)
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: 76, alignment: .leading)
                        ForEach(0 ..< selected.count, id: \.self) { i in
                            cell(row: row, index: i)
                        }
                    }
                    .padding(.vertical, 7)
                    Divider()
                }
            }
        }
    }

    private func cell(row: CompareRow, index i: Int) -> some View {
        let best = row.bestIndex == i
        let worst = row.worstIndex == i
        let differs = row.differs
        // 无差异的行整行压暗，让"有差异"的地方自己跳出来
        let tint: Color = best ? Luma.accent : (worst ? Luma.warn : .primary)
        return Text(row.texts[i])
            .font(.system(size: 12, weight: differs && (best || worst) ? .semibold : .regular))
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(differs ? tint : .secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(differs ? tint.opacity(best || worst ? 0.16 : 0.07) : Color.clear))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: [CompareRow] {
        let es = selected
        return [
            CompareRow(id: "aperture", name: "光圈",
                       texts: es.map { Helper.fmtAperture($0.aperture) },
                       numbers: es.map { $0.aperture }, better: .neutral),
            CompareRow(id: "shutter", name: "快门",
                       texts: es.map { Helper.fmtShutter($0.shutterSpeed) },
                       // 秒数越小 = 快门越快 = 越不容易手抖
                       numbers: es.map { Helper.secondsOf($0.shutterSpeed) }, better: .lower),
            CompareRow(id: "iso", name: "ISO",
                       texts: es.map { Helper.fmtISO($0.iso) },
                       numbers: es.map { $0.iso.map(Double.init) }, better: .lower),
            CompareRow(id: "focal", name: "焦距",
                       texts: es.map { Helper.fmtFocal($0.focalLengthMm) },
                       numbers: es.map { $0.focalLengthMm }, better: .neutral),
            CompareRow(id: "ev", name: "曝光补偿",
                       texts: es.map { Helper.fmtComp($0.exposureComp) },
                       // 比较"偏离 0 的绝对值"，偏离越小越好
                       numbers: es.map { $0.exposureComp.map { abs($0) } }, better: .lower),
            CompareRow(id: "wb", name: "白平衡",
                       texts: es.map { $0.whiteBalance ?? "—" },
                       numbers: es.map { _ in nil }, better: .neutral),
            CompareRow(id: "model", name: "机型",
                       texts: es.map { $0.phoneModel ?? "—" },
                       numbers: es.map { _ in nil }, better: .neutral),
            CompareRow(id: "scene", name: "环境 · 题材",
                       texts: es.map { "\(Helper.analyzeLight($0).rawValue) · \(Helper.analyzeScene($0).rawValue)" },
                       numbers: es.map { _ in nil }, better: .neutral)
        ]
    }

    // MARK: 差异解读
    private var diffCard: some View {
        Card(title: "关键差异", trailing: observations.isEmpty ? nil : "\(observations.count) 条") {
            if observations.isEmpty {
                Text("这几张的拍摄参数基本一致。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(observations, id: \.self) { line in
                        HStack(alignment: .top, spacing: 7) {
                            Circle().fill(Luma.accent)
                                .frame(width: 4, height: 4)
                                .padding(.top, 5)
                            Text(line).font(.caption)
                        }
                    }
                }
            }
        }
    }

    /// 把数值差异翻译成人话。都用「档」(stop = log2 倍数) 描述——这是摄影里最直观的单位。
    private var observations: [String] {
        guard selected.count >= 2 else { return [] }
        var out: [String] = []

        let isos = selected.compactMap(\.iso).filter { $0 > 0 }
        if let lo = isos.min(), let hi = isos.max(), hi > lo {
            let stops = log2(Double(hi) / Double(lo))
            if stops >= 1 {
                out.append("ISO 相差 \(String(format: "%.1f", stops)) 档（\(lo) → \(hi)），高感那张噪点会明显更多")
            }
        }

        let secs = selected.compactMap { Helper.secondsOf($0.shutterSpeed) }.filter { $0 > 0 }
        if let fast = secs.min(), let slow = secs.max(), slow > fast {
            let stops = log2(slow / fast)
            if stops >= 1 {
                out.append("快门相差 \(String(format: "%.1f", stops)) 档，慢的那张手持糊片风险更高")
            }
        }

        let aps = selected.compactMap(\.aperture).filter { $0 > 0 }
        if let small = aps.min(), let big = aps.max(), big > small {
            // 光圈档 = log2(f值之比) / 2（进光量与 f 值的平方成反比）
            let stops = log2(big / small) / 2
            if stops >= 1 {
                out.append("光圈相差 \(String(format: "%.1f", stops)) 档，虚化程度和进光量差别明显")
            }
        }

        let focs = selected.compactMap(\.focalLengthMm)
        if let wide = focs.min(), let tele = focs.max(), tele - wide >= 10 {
            out.append("焦距 \(Int(wide))mm → \(Int(tele))mm，视角差异明显")
        }

        let evs = selected.compactMap(\.exposureComp).map(abs).filter { $0 > 0 }
        if let m = evs.max(), m >= 1 {
            out.append("有照片做了 \(String(format: "%.1f", m)) EV 曝光补偿，当时光比应该不小")
        }
        return out
    }
}

struct GrowthView: View {
    @Environment(\.colorScheme) private var cs
    var body: some View {
        let all = Array(GrowthStore.all.reversed().prefix(8))
        Group {
            if all.isEmpty {
                VStack(spacing: Luma.sp16) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("还没有成长记录").font(.title3).bold()
                    Text("解析照片后，ShotLog 每天会存一条参数快照，\n回看就能发现自己拍摄习惯的变化。")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(all, id: \.snapshotDay) { s in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.snapshotDay.formatted(.dateTime.month().day()))
                                        .font(.subheadline).fontWeight(.semibold)
                                    Text(String(format: "共 %d 张 · 平均 ISO %.0f", s.total, s.meanISO))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(String(format: "糊片率 %.1f%%", s.blurRate * 100))
                                    .font(.subheadline).monospacedDigit()
                                    .foregroundStyle(s.blurRate > 0.3 ? Luma.warn : Luma.ok)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("每日快照").font(.subheadline).fontWeight(.semibold).textCase(nil)
                    } footer: {
                        Text("每天记录一条当天的解析汇总，最多保留 8 条").font(.caption).textCase(nil)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(schemeBg(cs))
        .navigationTitle("成长记录")
    }
}

// MARK: - Module 5 延生功能：拍摄提示
/// 基于相册 EXIF 得出的可执行拍摄建议，均纯本地计算、不含任何云端请求。
struct TipItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let message: String
    let tint: Color
}

private enum ShotTips {
    /// sample < 2 张时样本过小，不产出建议。
    static func compute(_ es: [ExifEntry]) -> [TipItem] {
        guard es.count >= 2 else { return [] }
        let real = es.filter { !$0.isAI }
        guard !real.isEmpty else { return [] }
        let rcount = Double(real.count)
        var out: [TipItem] = []

        let high = real.filter { ($0.iso ?? 0) > 1600 }.count
        if Double(high) / rcount > 0.25 {
            let pct = Int(Double(high) / rcount * 100)
            out.append(TipItem(
                icon: "photo", title: "高 ISO 注意",
                message: "约 \(pct)% 的照片 ISO 高于 1600。手持拍摄建议开启夜间模式或选用光学防抖更长的镜头来压住噪点。",
                tint: Luma.warn
            ))
        }

        let slow = real.compactMap { Helper.secondsOf($0.shutterSpeed) }.filter { $0 > 1.0 / 60.0 }
        if Double(slow.count) / rcount > 0.30 {
            out.append(TipItem(
                icon: "camera.viewfinder", title: "快门偏慢",
                message: "有 \(slow.count) 张快门慢于 1/60s。手持时建议架三脚架或切大光圈缩短曝光时间。",
                tint: Luma.warn
            ))
        }

        var counts: [SceneType: Int] = [:]
        for e in real { let s = Helper.analyzeScene(e); counts[s, default: 0] += 1 }
        if let best = counts.max(by: { $0.value < $1.value }) {
            let scene = best.key, scount = best.value
            if Double(scount) / rcount > 0.4 {
                let pct = Int(Double(scount) / rcount * 100)
                out.append(TipItem(
                    icon: scene.icon, title: "偏好取景说明",
                    message: "你近期 \(pct)% 的照片落在「\(scene.rawValue)」场景。这不是问题，但可以尝试把另外两类场景也放进日常。",
                    tint: Luma.accent
                ))
            }
        }

        let aiPct = Int(Double(es.filter { $0.isAI }.count) / Double(es.count) * 100)
        if aiPct > 20 {
            out.append(TipItem(
                icon: "exclamationmark.triangle.fill", title: "AI 补全较多",
                message: "有 \(aiPct)% 的条目缺失原始 EXIF，靠 AI 视觉推断补全。回看这类时留意精度不如原始拍摄数据。",
                tint: Luma.aiEstimate
            ))
        }

        if out.isEmpty {
            out.append(TipItem(
                icon: "checkmark.seal.fill", title: "拍摄状态健康",
                message: "当前相册参数无明显异常，继续保持。",
                tint: Luma.ok
            ))
        }
        return out
    }
}

struct TipsView: View {
    @ObservedObject var store: ShotStore
    @Environment(\.colorScheme) private var cs
    var body: some View {
        let tips = ShotTips.compute(store.entries)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("拍摄提示").font(.title2).bold()
                    Text("基于已解析照片的 EXIF 统计 · 全部本地计算")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if tips.isEmpty {
                    Card(title: nil) {
                        EmptyStateView(
                            title: "样本不足",
                            text: "选择至少 2 张携带 EXIF 的照片后，可得到针对性的拍摄建议。"
                        )
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(tips) { t in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: t.icon)
                                    .font(.body)
                                    .foregroundStyle(t.tint)
                                    .frame(width: 36, height: 36)
                                    .background(t.tint.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(t.title).font(.body).fontWeight(.semibold)
                                    Text(t.message).font(.subheadline).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(schemeCard(cs), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Luma.ink.opacity(0.06)))
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(schemeBg(cs))
    }
}

struct RootView: View {
    @Environment(\.colorScheme) private var cs
    @StateObject private var store = ShotStore()
    var body: some View {
        NavigationStack {
            Group {
                if store.isScanning {
                    VStack(spacing: Luma.sp16) {
                        ProgressView().controlSize(.large)
                        Text(store.statusMessage.isEmpty ? "正在处理…" : store.statusMessage)
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.grant == .denied || store.grant == .restricted {
                    AuthorityDeniedView(action: { PermsManager.openSettings() })
                } else if store.grant == .notDetermined {
                    PermissionView(action: { Task { await store.ensurePermission() } })
                } else if store.entries.isEmpty && !store.hasScanned {
                    StartView(store: store)
                } else if store.hasScanned && store.entries.isEmpty {
                    EmptyLibraryView(
                        repickAction: { store.reset() },
                        settingsAction: { PermsManager.openSettings() })
                } else {
                    LibraryView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(schemeBg(cs))
        }
    }
}

/// 引导页共享的步骤行。
private struct StepRow: View {
    let index: Int, title: String, text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.footnote).bold().foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Luma.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// 引导页共享的 Hero 图标。
private struct HeroBadge: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 40, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 88, height: 88)
            .background(
                LinearGradient(colors: [Luma.accent, Luma.ok], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .shadow(color: Luma.accent.opacity(0.35), radius: 16, y: 8)
    }
}

// MARK: - 选片记忆 UI
/// 记忆里一次选片的缩略图堆叠：最多取前三张叠着显示，看一眼就知道是哪批照片。
private struct ThumbStack: View {
    let ids: [String]
    @State private var images: [Image] = []
    @Environment(\.colorScheme) private var cs
    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(0 ..< 3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Luma.ink.opacity(cs == .dark ? 0.18 : 0.08))
                    .frame(width: 34, height: 34)
                    .overlay {
                        if images.indices.contains(i) {
                            images[i].resizable().scaledToFill()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(schemeCard(cs), lineWidth: 2))
                    .offset(x: CGFloat(i) * 15)
            }
        }
        .frame(width: 34 + 30, height: 34)
        .task { await load() }
    }
    private func load() async {
        var out: [Image] = []
        for id in ids.prefix(3) {
            if let img = await Helper.thumbnailForAsset(id: id, size: 96) { out.append(img) }
        }
        images = out
    }
}

/// 一条选片记忆：缩略图 + 张数 + 时间 + 来源，点一下直接重新载入这批照片。
struct SelectionMemoryRow: View {
    let item: SavedSelection
    let onLoad: () -> Void
    var onDelete: (() -> Void)? = nil
    @Environment(\.colorScheme) private var cs
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            // 点击区不含删除按钮，避免点「忘记」时误触发载入
            HStack(spacing: 12) {
                ThumbStack(ids: item.identifiers)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.count) 张照片").font(.subheadline).fontWeight(.semibold)
                    Text("\(item.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(item.kind.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("载入")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Luma.accent))
            }
            .contentShape(Rectangle())
            .onTapGesture { onLoad() }

            if let onDelete {
                Button { onDelete() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Luma.ink.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .opacity(hovered ? 1 : 0)
                .padding(.leading, 8)
                .help("忘记这次选片")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(schemeCard(cs), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(hovered ? Luma.accent.opacity(0.5) : Luma.ink.opacity(cs == .dark ? 0.14 : 0.07),
                        lineWidth: 1)
        )
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

/// 「先选照片再读信息」的落地页。启动后不必自动扫全库——等用户主动选片。
struct StartView: View {
    @ObservedObject var store: ShotStore
    @Environment(\.colorScheme) private var cs
    @State private var pickerSelection: [PhotosPickerItem] = []
    var body: some View {
        VStack(spacing: Luma.sp24) {
            HeroBadge(systemName: "photo.stack")
            VStack(spacing: 6) {
                Text("开始分析你的拍摄习惯").font(.title2).bold()
                Text("勾选想要解析的照片，ShotLog 会读取它们的 EXIF 拍摄信息。\n照片不会上传到云端。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 12) {
                // PhotosPicker 是 macOS 原生的照片选择器（PHPickerViewController），
                // 会自动处理授权提示、勾选态、加入新相册等细节，体验和《照片》App 一致。
                PhotosPicker(selection: $pickerSelection,
                             maxSelectionCount: nil,
                             matching: .images,
                             photoLibrary: .shared()) {
                    Label("选择照片解析", systemImage: "photo.badge.plus")
                        .frame(width: 240)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .onChange(of: pickerSelection) { _, items in
                    let ids = items.compactMap(\.itemIdentifier)
                    guard !ids.isEmpty else { return }
                    Task {
                        await store.parseSelection(ids)
                        pickerSelection = []
                    }
                }
                Button("或自动扫描最近的 500 张照片") { Task { await store.scanWholeLibrary() } }
                    .buttonStyle(.link)
                    .font(.subheadline)
            }

            if !store.savedSelections.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Label("继续上次的选择", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline).fontWeight(.semibold)
                        Spacer()
                        Button("清空") { store.clearSavedSelections() }
                            .buttonStyle(.link).font(.caption)
                    }
                    ForEach(store.savedSelections) { item in
                        SelectionMemoryRow(
                            item: item,
                            onLoad: { Task { await store.loadSelection(item.identifiers, replace: true) } },
                            onDelete: { store.forgetSelection(item.id) })
                    }
                }
                .frame(maxWidth: 420)
                .padding(.top, Luma.sp16)
            }
            Text("受限模式下只能看到已允许访问的照片，可随时在系统设置里调整")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(Luma.sp32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(schemeBg(cs))
    }
}

/// 选择照片解析入口已统一改用 macOS 原生的 PhotosPicker（PHPickerViewController），
/// 这里保留旧自定义网格是历史代码——已无引用，但留着方便回看取舍过程。
#if false
/// 相册网格多选：勾选 → 返回资产标识符 → 由 store并发解析 EXIF 并合并去重。
/// 注意：macOS 上 sheet 里不能嵌 NavigationView——内容切换时底层的
/// NSSplitViewController 会在约束更新中移除 split item 失败，直接抛异常崩溃，
/// 所以这里用自绘头部栏。
struct ImportView: View {
    @ObservedObject var store: ShotStore
    @Environment(\.dismiss) private var dismiss
    @State private var assets: [PHAsset] = []
    @State private var loaded = false
    @State private var selected: Set<String> = []
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("选择照片").font(.headline)
                    Text("点击勾选要解析的照片（可多选），完成后点右上角「解析」")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("已选 \(selected.count) 张")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Luma.accent.opacity(selected.isEmpty ? 0 : 0.12), in: Capsule())
                Button("取消") { dismiss() }.buttonStyle(.bordered)
                Button(selected.isEmpty ? "解析" : "解析 \(selected.count) 张") {
                    let ids = Array(selected)
                    Task { await store.parseSelection(ids) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
            .padding(14)
            Divider()
            if loaded {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 10)], spacing: 10) {
                        ForEach(0..<assets.count, id: \.self) { i in
                            let a = assets[i]
                            ImageCell(asset: a, selected: selected.contains(a.localIdentifier))
                                .onTapGesture {
                                    if selected.contains(a.localIdentifier) { selected.remove(a.localIdentifier) }
                                    else { selected.insert(a.localIdentifier) }
                                }
                        }
                    }
                    .padding(14)
                }
            } else {
                ProgressView("正在加载相册…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 680, minHeight: 500)
        .task { await loadAssets() }
    }
    private func loadAssets() async {
        let listed = await Task.detached(priority: .userInitiated) { () -> [PHAsset] in
            let opts = PHFetchOptions()
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            opts.fetchLimit = 500
            let fetched = PHAsset.fetchAssets(with: opts)
            var out: [PHAsset] = []
            out.reserveCapacity(fetched.count)
            for i in 0..<fetched.count { out.append(fetched.object(at: i)) }
            return out
        }.value
        assets = listed
        loaded = true
    }
}

/// 带勾选标记的网格缩略图：图片异步加载，点击切换选中态。
struct ImageCell: View {
    let asset: PHAsset
    let selected: Bool
    @State private var image: Image? = nil
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(Luma.muted.opacity(0.15))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if selected {
                ZStack {
                    Circle().fill(Luma.accent).frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    Image(systemName: "checkmark").foregroundStyle(.white).font(.caption2).bold()
                }
                .offset(x: 6, y: -6)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? Luma.accent : Luma.ink.opacity(0.08), lineWidth: selected ? 2.5 : 0.5)
        )
        .contentShape(Rectangle())
        .task { image = await Helper.thumbnail(for: asset, size: 300) }
    }
}
#endif

@main struct ShotLogApp: App {
    init() {
        // 未捕获的 NSException 落盘，之后崩溃可直接在 ~/Library/Logs/ShotLog_exceptions.log 看到原因
        NSSetUncaughtExceptionHandler { ex in
            let m = "[\(Date())] \(ex.name.rawValue): \(ex.reason ?? "-")\n"
                + ex.callStackSymbols.joined(separator: "\n") + "\n\n"
            let url = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Logs/ShotLog_exceptions.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let d = m.data(using: .utf8) { handle.write(d) }
                try? handle.close()
            } else {
                try? m.data(using: .utf8)?.write(to: url)
            }
        }
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 760, minHeight: 540)
        }
    }
}