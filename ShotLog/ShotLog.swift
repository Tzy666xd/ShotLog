import SwiftUI
import Photos
import Foundation
import AppKit
import CoreLocation
import ImageIO
import Vision

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
}
private func schemeCard(_ cs: ColorScheme) -> Color { cs == .dark ? Luma.cardDark : Luma.cardLight }
private func schemeBg(_ cs: ColorScheme) -> Color { cs == .dark ? Luma.bgDark : Luma.bgLight }
/// 卡片内部的嵌入式浅底：给 miniStat、建议行这类「卡中卡」一层轻微的凹陷感，深浅色都清晰可辨。
private func insetFill(_ cs: ColorScheme) -> Color { Luma.ink.opacity(cs == .dark ? 0.12 : 0.04) }

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

/// 统计页的迷你数据瓷砖：与 Card 同一配色体系（自适应底色 + 细描边），圆角 14、无阴影。
/// 可选 tint 给整块瓷砖铺一层强调底色（失误统计的非零项用）。
struct Tile<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var cs
    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                ZStack {
                    shape.fill(schemeCard(cs))
                    if let tint { shape.fill(tint.opacity(cs == .dark ? 0.12 : 0.07)) }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Luma.ink.opacity(cs == .dark ? 0.12 : 0.06)))
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
        case focalLengthMm, focal35mm, aperture, shutterSpeed, iso, exposureComp, whiteBalance
        case flashOn, origin
        case visionLabels, visionConfidence, aesthetics, faceCount, maxFaceArea, isUtilityShot
    }
    let assetIdentifier: String
    let localURL: URL?
    let capturedAt: Date
    let location: GroundTruthLocation?
    let phoneModel: String?
    let lens: String?
    let focalLengthMm: Double?
    /// 35mm 等效焦距。绝大多数手机**不写这个字段**（实测本机相册 400 张里 0 张有），
    /// 有的话就是最可靠的焦段依据；没有则要靠 lensLabel 的机型启发式。
    let focal35mm: Int?
    let aperture: Double?
    let shutterSpeed: String?
    let iso: Int?
    let exposureComp: Double?
    let whiteBalance: String?
    let flashOn: Bool?
    let origin: MetaSource

    // MARK: Vision 视觉事实（系统内置模型算出来的，落盘后可复现）
    /// 分类标签，英文 identifier，按置信度降序
    let visionLabels: [String]?
    let visionConfidence: Double?
    /// 美学分 0…1
    let aesthetics: Double?
    /// 人脸数
    let faceCount: Int?
    /// 最大人脸占画面面积比 0…1
    let maxFaceArea: Double?
    /// 系统判定为「实用图」（文档/表格/收据一类，不是自然照片）
    let isUtilityShot: Bool?

    var isAI: Bool { origin == .ai }
    /// 这一条是否真的跑过视觉模型
    var hasVision: Bool { visionLabels?.isEmpty == false }
    /// 系统明确判为「实用图」（文档 / 截图 / 收据）才在美学统计里剔除。
    ///
    /// 为什么不再用「低美学分」和「低置信度」兜底：拿相册真实数据标定过，
    /// 200 张里有 11 张美学分是负数且主标签是 outdoor / structure ——
    /// 那是暗光、纯色墙、糊片，属于**拍得不好的照片**，不是截图。
    /// 把它们当非照片剔掉，等于把「拍砸了」从统计里藏起来，正好违背这个 app 的用途。
    var isNonPhoto: Bool {
        isUtilityShot == true
    }
}

// MARK: - services (real Photos scanning + analyzers)
private enum Helper {
    struct AdviceItem: Identifiable, Equatable {
        let id = UUID()
        let title: String, text: String
        /// true 表示是「曝光正常」这类正面结论，展示时配绿色对勾而非警告图标。
        var positive: Bool = false
    }

    /// 只负责扫描；相册授权由 ShotStore 统一处理，避免重复触发授权请求。
    static func scanPhotoLibrary(limit: Int = 500) async -> [ExifEntry] {
        let opts = PHFetchOptions()
        // 倒序取「最近」的 limit 张：升序 + fetchLimit 会拿到最老的 500 张，与入口文案不符
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // 只取图片，避免 fetchLimit 被视频占满后一张图都扫不到
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        opts.fetchLimit = limit
        return await Helper.entriesFor(Helper.identifiers(from: PHAsset.fetchAssets(with: opts)))
    }

    /// 把 fetch 结果摊平成标识符数组。PHAsset / PHFetchResult 都不是 Sendable，
    /// 跨并发域只传 [String]；PHAsset 一律在各自函数作用域内取用即弃。
    static func identifiers(from result: PHFetchResult<PHAsset>) -> [String] {
        var out: [String] = []
        out.reserveCapacity(result.count)
        for i in 0 ..< result.count { out.append(result.object(at: i).localIdentifier) }
        return out
    }

    /// 有界并发解析一批照片：最多 maxInFlight 个请求同时在途，结果按下标回填保持输入顺序。
    /// Data 在子任务里就地转成 ExifEntry，不会出现几百张原图同时驻留内存的情况。
    static func entriesFor(_ identifiers: [String], maxInFlight: Int = 8) async -> [ExifEntry] {
        guard !identifiers.isEmpty else { return [] }
        var slots = [ExifEntry?](repeating: nil, count: identifiers.count)
        let first = min(maxInFlight, identifiers.count)
        await withTaskGroup(of: (Int, ExifEntry?).self) { group in
            for i in 0 ..< first {
                let id = identifiers[i]
                group.addTask { (i, await Helper.entry(for: id)) }
            }
            var next = first
            while let (idx, parsed) = await group.next() {
                slots[idx] = parsed
                if next < identifiers.count {
                    let id = identifiers[next]
                    let submit = next
                    group.addTask { (submit, await Helper.entry(for: id)) }
                    next += 1
                }
            }
        }
        return slots.compactMap { $0 }
    }

    /// 单张照片：按 id 取出资产、拉原始数据并就地解析 EXIF。
    /// asset 只在本函数作用域内出现；取不到数据（如 iCloud 下载失败）返回 nil。
    /// 用 CheckedContinuation 适配回调——DispatchSemaphore 会阻塞 Swift Task 系统线程；
    /// 允许联网下载 iCloud 照片，否则“优化存储”开启时会静默解析失败。
    static func entry(for identifier: String) async -> ExifEntry? {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = fetched.firstObject else { return nil }
        let data: Data? = await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { d, _, _, _ in
                cont.resume(returning: d)
            }
        }
        guard let data else { return nil }
        return Helper.makeEntry(asset: asset, image: data)
    }
    static func makeEntry(asset: PHAsset, image: Data) -> ExifEntry? {
        guard let src = CGImageSourceCreateWithData(image as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, [kCGImageSourceShouldCache as String: false] as CFDictionary) as? [String: Any]
        else { return nil }
        // 顺手跑一次系统内置的视觉模型：从同一份 Data 取 512px 缩略图，
        // 分类 + 人脸 + 美学一次前向约 15ms（实测），不额外解码原图。
        let facts = VisionAnalyzer.analyze(source: src)
        let location = asset.location.map { GroundTruthLocation($0.coordinate.latitude, $0.coordinate.longitude) }
        return Helper.parseEntry(props: props, capturedAt: asset.creationDate ?? Date(),
            location: location, assetIdentifier: asset.localIdentifier, localURL: nil, vision: facts)
    }

    /// 从 CGImageSource 属性字典生成分析条目。
    /// 机型在 {TIFF} 字典、拍摄参数在 {Exif} 字典——顶层键只能读到像素尺寸等少数信息。
    static func parseEntry(props: [String: Any], capturedAt: Date, location: GroundTruthLocation?,
                           assetIdentifier: String, localURL: URL?,
                           vision: VisionFacts? = nil) -> ExifEntry {
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let focal = Helper.number(exif, "FocalLength")
        // 35mm 等效焦距：手机基本不写，相机多半也不写，读到就是意外之喜
        let focal35 = (exif["FocalLengthIn35mmFilm"] as? NSNumber)?.intValue
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
            phoneModel: camera, lens: lens, focalLengthMm: focal, focal35mm: focal35,
            aperture: aperture, shutterSpeed: shutter, iso: iso,
            exposureComp: ev, whiteBalance: wb, flashOn: flashNum,
            origin: .exif,
            visionLabels: vision?.labels,
            visionConfidence: vision?.confidence,
            aesthetics: vision?.aesthetics,
            faceCount: vision?.faces,
            maxFaceArea: vision?.maxFaceArea,
            isUtilityShot: vision?.isUtility)
    }

    /// 先选照片再读信息：用户在导入视图里勾选了 asset 标识符后，由这里并发解析 EXIF。
    /// 解析结果由调用方按拍摄时间合并去重。
    static func parseSelection(_ identifiers: [String]) async -> [ExifEntry] {
        guard !identifiers.isEmpty else { return [] }
        return await Helper.entriesFor(identifiers)
    }

    /// 缩略图内存缓存：列表/网格滚动时同一个 cell 会反复出现，命中缓存可避免重复取图解码。
    /// NSCache 官方保证线程安全，包装一层 @unchecked Sendable 以通过严格并发检查。
    private final class ThumbCacheBox: @unchecked Sendable {
        let store: NSCache<NSString, NSImage> = {
            let c = NSCache<NSString, NSImage>()
            c.countLimit = 300
            c.totalCostLimit = 128 * 1024 * 1024
            return c
        }()
    }
    private static let thumbCache = ThumbCacheBox()

    /// 相册网格用缩略图：async 版本的 requestImage 适配器，结果按「id-尺寸」缓存。
    /// NSImage 不是 Sendable，函数只在主线程进出——requestImage 本身立即返回、
    /// 真正的解码在 Photos 队列异步完成，放主线程不会卡 UI。
    @MainActor
    static func thumbnailForAsset(id: String, size: CGFloat) async -> NSImage? {
        let key = "\(id)-\(Int(size))" as NSString
        if let hit = thumbCache.store.object(forKey: key) { return hit }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetched.firstObject else { return nil }
        let ns: NSImage? = await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = false
            opts.deliveryMode = .fastFormat
            PHImageManager.default().requestImage(for: asset,
                targetSize: .init(width: Int(size), height: Int(size)),
                contentMode: .aspectFill, options: opts) { image, _ in
                cont.resume(returning: image)
            }
        }
        if let ns {
            thumbCache.store.setObject(ns, forKey: key, cost: Int(size) * Int(size) * 4)
        }
        return ns
    }

    /// 详情页顶部大图，单独走高质量通道。
    ///
    /// 不能复用 `thumbnailForAsset`：那个是给列表 56–220pt 的小图用的，
    /// `deliveryMode = .fastFormat` 明确要「快而不讲究」，700pt 方形被拉到 900pt 宽就是一片糊。
    /// `.opportunistic` 也不行——它的第一次回调是 degraded 占位图，
    /// 用一次性 continuation 接，接到的永远是那张低清版（注释里写着「取最后一次」，实际取到的是第一次）。
    /// 这里直接 `.highQualityFormat`：只回调最终图，按 Hero 的实际比例要像素。
    @MainActor
    static func heroImageForAsset(id: String, width: Int = 3000, height: Int = 800) async -> NSImage? {
        let key = "hero-\(id)-\(width)" as NSString
        if let hit = thumbCache.store.object(forKey: key) { return hit }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetched.firstObject else { return nil }
        let ns: NSImage? = await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            // iCloud「优化存储」时本地只有占位图，不开网络就只能拿到那张蒙了的
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            opts.resizeMode = .exact
            opts.version = .current
            PHImageManager.default().requestImage(for: asset,
                targetSize: .init(width: width, height: height),
                contentMode: .aspectFill, options: opts) { image, _ in
                cont.resume(returning: image)
            }
        }
        if let ns {
            thumbCache.store.setObject(ns, forKey: key, cost: width * height * 4)
        }
        return ns
    }
    static func number(_ d: [String: Any], _ key: String) -> Double? { (d[key] as? NSNumber)?.doubleValue }

    // --- formatters ---
    static func fmtAperture(_ v: Double?) -> String { v.map { "f/\($0)" } ?? "—" }
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

    /// 手持糊片风险的统一快门阈值：慢于 1/30s 视为慢快门。
    /// 单张诊断、统计页的慢门率 / 糊片率、拍摄提示共用这一个值。
    static let slowShutterSeconds: Double = 1.0 / 30.0

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

    /// 光线判断：Vision 真的看到了什么就报什么，看不到才退回按时钟猜。
    /// 原来的实现只按小时判断，晚上 21 点拍的室内白天照会被当成「夜间」。
    static func analyzeLight(_ e: ExifEntry) -> LightEnvironment {
        if let labels = e.visionLabels, !labels.isEmpty {
            let s = Set(labels)
            if s.contains("night") || s.contains("nighttime") || s.contains("darkness") { return .night }
            if s.contains("sunset") || s.contains("sunrise") { return .dusk }
            if s.contains("indoor") || s.contains("room") || s.contains("furniture")
                || s.contains("table") || s.contains("document") { return .dim }
            if s.contains("sky") || s.contains("blue_sky") || s.contains("outdoor")
                || s.contains("sun") || s.contains("sunlight") { return .daylight }
            // 有视觉结果但没命中光线关键词时，继续走时钟兜底
        }
        let hour = Calendar.current.component(.hour, from: e.capturedAt)
        if hour >= 20 || hour < 6 { return .night }
        if hour >= 17 { return .dusk }
        if hour >= 9 { return .daylight }
        return .dim
    }

    /// 题材判断：先看画面里到底是什么，再用焦段 / 闪光兜底。
    /// 原来 `focal >= 50 → 人像` 会把 50mm 拍的猫、花、建筑全算成人像。
    static func analyzeScene(_ e: ExifEntry) -> SceneType {
        if let labels = e.visionLabels, !labels.isEmpty {
            let s = Set(labels)
            if s.contains("night") || s.contains("nighttime") { return .night }
            if s.contains("indoor") || s.contains("room") || s.contains("furniture")
                || s.contains("table") { return .indoor }
            if s.contains("running") || s.contains("sport") || s.contains("athletics")
                || s.contains("basketball") || s.contains("cycling") { return .action }
            // 人像：标签本身说是「人」最可靠
            if s.contains("people") || s.contains("adult") || s.contains("child")
                || s.contains("portrait") { return .portrait }
            // 标签没提人，但画面里有张够大的脸（占画面 3% 以上）——也是人像。
            // 不能只看「有脸」：风景照里一个路人的小脸会把整张判成人像。
            if (e.maxFaceArea ?? 0) > 0.03 { return .portrait }
            if s.contains("landscape") || s.contains("sky") || s.contains("mountain")
                || s.contains("land") || s.contains("sea") || s.contains("beach")
                || s.contains("tree") || s.contains("grass") || s.contains("rocks") { return .landscape }
        }
        let hour = Calendar.current.component(.hour, from: e.capturedAt)
        if hour >= 20 || hour < 6 { return .night }
        if e.flashOn == true { return .indoor }
        // 焦段兜底也统一按等效焦距判断
        if let eq = Helper.equivalentFocal(e) {
            if eq >= 50 { return .portrait }
            if eq <= 20 { return .landscape }
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
        if let sec = Helper.secondsOf(e.shutterSpeed), sec > Helper.slowShutterSeconds {
            out.append(AdviceItem(title: "慢快门糊片风险", text: String(format: "%.2f 秒快门对手持较慢", sec)))
        }
        if let ev = e.exposureComp, (ev > 1.3 || ev < -1.3) {
            out.append(AdviceItem(title: ev > 1.3 ? "过曝" : "欠曝",
                text: String(format: "曝光补偿 %.1f EV", ev)))
        }
        if out.isEmpty { out.append(AdviceItem(title: "曝光正常", text: "各项指标健康", positive: true)) }
        return out
    }

    /// 是不是手机 / 平板这类小底设备。
    /// 手机的实际焦距普遍只有 1.5–15mm，直接套全画幅的 24 / 50 阈值，
    /// 会把**每一张**手机照片都算成「超广角」——这正是之前「超广角 329 张」的来源。
    static func isSmallSensor(_ e: ExifEntry) -> Bool {
        let m = (e.phoneModel ?? "").lowercased()
        let markers = ["iphone", "ipad", "nova", "huawei", "honor", "oppo", "vivo",
                       "xiaomi", "redmi", "pixel", "samsung", "sm-", "oneplus",
                       "realme", "meizu", "op-", "nothing"]
        return markers.contains { m.contains($0) }
    }

    /// 机型 + 实际焦距 → 35mm 等效焦距。
    ///
    /// 为什么必须查表：手机既不写 `FocalLengthIn35mmFilm`，也不写 `FocalPlaneXResolution`
    /// （本机相册 120 张采样里两个字段都是 0 命中），crop factor 无从推算。
    /// 表里的值按各机型公开的镜头规格换算，覆盖本机相册出现过的设备；
    /// 新机型没命中时会退回按镜头角色给典型值，见 `equivalentFocal`。
    private static let eqTable: [String: [Double: Double]] = [
        // iPhone
        "iphone 15 pro": [2.22: 13, 2.69: 23, 6.76: 24, 6.77: 24, 9.0: 77],
        "iphone 14 pro": [2.22: 13, 2.69: 23, 6.86: 24, 9.0: 77],
        "iphone 14":     [5.7: 26],
        "iphone 11":     [1.54: 13, 2.71: 23, 4.25: 26],
        "iphone x":      [4.0: 28],
        "iphone 6s":     [4.15: 29],
        "iphone 16":     [2.69: 23],
        "iphone 17":     [2.71: 23],
        // 华为 / nova
        "nova 14 ultra": [1.76: 13, 3.51: 16, 4.9: 16, 5.75: 24, 5.8: 24, 14.58: 90, 14.6: 90],
        "nova 16 ultra": [1.95: 13, 3.51: 16, 6.7: 24, 6.73: 24, 14.58: 90],
        "nova 15 ultra": [5.75: 24, 14.58: 90],
        "nova 15 pro":   [5.72: 24],
        "huawei mate 80":     [1.95: 13, 5.75: 24, 14.46: 90],
        "huawei mate 70 pro+": [1.95: 13, 6.98: 24, 15.0: 90],
        "huawei mate 70 rs | ultimate design": [6.98: 24, 15.0: 90],
        "huawei pura 70 pro+": [15.0: 90],
        // 其他
        "op-041":  [7.08: 24],
        "nth-an00": [5.52: 24],
        "ac003":   [3.33: 16],
        "fc6310":  [8.8: 24],
    ]

    /// 35mm 等效焦距。拿到它，焦段判断和「焦距」分布才有统一口径。
    static func equivalentFocal(_ e: ExifEntry) -> Double? {
        // 1. EXIF 自己写了等效值，最可靠
        if let eq = e.focal35mm, eq > 0 { return Double(eq) }
        guard let f = e.focalLengthMm, f > 0 else { return nil }
        // 2. 机型 + 实际焦距查表
        let key = (e.phoneModel ?? "").lowercased()
        if let row = eqTable[key],
           let hit = row.first(where: { abs($0.key - f) < 0.15 })?.value {
            return hit
        }
        // 3. 手机但表里没有
        if isSmallSensor(e) {
            // 焦距 ≥16mm 不可能是手机实际焦距——这类机器自己写的就是等效值
            // （iPhone 15 Pro 的 24/35/50mm 变焦模式就是这样，镜头仍是 6.765mm）
            if f >= 16 { return f }
            if f < 2.6 { return 13 }   // 超广角
            if f < 4.2 { return 16 }   // 超广角 / 1x 裁切
            if f < 8.5 { return 24 }   // 主摄
            return 90                   // 长焦
        }
        // 4. 相机：实际焦距 × 机身 crop
        return f * sensorCrop(e)
    }

    /// 相机机身的 crop factor。手机不走这里（见 equivalentFocal）。
    static func sensorCrop(_ e: ExifEntry) -> Double {
        let m = (e.phoneModel ?? "").lowercased()
        if m.contains("gfx") || m.contains("x2d") || m.contains("907x") { return 0.79 }
        if m.contains("ilce-6") || m.contains("x-t") || m.contains("x-s") || m.contains("x-h")
            || m.contains("x100") || m.contains("eos r7") || m.contains("eos r10")
            || m.contains("eos m") || m.contains("z 50") || m.contains("z fc")
            || m.contains("d500") || m.contains("d7500") { return 1.5 }
        if m.contains("dc-g") || m.contains("om-") || m.contains("e-m") { return 2.0 }
        return 1.0   // 全画幅
    }

    /// 焦距展示：有等效值就报等效，同时保留实际值，避免「6.8mm 到底是广角还是长焦」的困惑。
    static func focalText(_ e: ExifEntry) -> String {
        let eq = equivalentFocal(e)
        let raw = e.focalLengthMm
        switch (eq, raw) {
        case let (eq?, raw?) where abs(eq - raw) > 0.6:
            return String(format: "等效 %.0fmm · 实际 %.1fmm", eq, raw)
        case let (eq?, _):
            return String(format: "等效 %.0fmm", eq)
        case (nil, let raw?):
            return String(format: "%.1fmm", raw)
        default:
            return "—"
        }
    }

    /// 焦段归类，统一用等效焦距判断。前置镜头单列。
    static func lensLabel(_ e: ExifEntry) -> String {
        let lens = (e.lens ?? "").lowercased()
        if lens.contains("front") || lens.contains("truedepth") { return "前置" }
        guard let eq = equivalentFocal(e) else { return "其他" }
        if eq < 24 { return "超广角" }
        if eq >= 50 { return "长焦" }
        return "主摄"
    }
}

// MARK: - Vision 视觉语义层（系统内置模型，零体积）
/// 一次前向推理拿到的全部画面事实。全部来自 macOS 内置的 Vision 模型，
/// 权重在系统里、app 不打包任何模型文件，所以二进制体积不变。
struct VisionFacts: Equatable {
    /// 前几个分类标签（英文 identifier，按置信度降序）
    let labels: [String]
    /// 主标签置信度
    let confidence: Double
    /// 美学分 0…1（已从系统原始的 -1…1 归一化），用不了时为 nil
    let aesthetics: Double?
    /// 人脸数量
    let faces: Int
    /// 最大人脸占画面的面积比例（归一化坐标，0…1）
    let maxFaceArea: Double
    /// 系统判定的「实用图」（文档、表格、收据一类）
    let isUtility: Bool
}

enum VisionAnalyzer {
    /// 喂进来的是**已经降采样过的**图（512px 长边即可）。
    /// 实测 6048×4032 全尺寸 54ms、512px 14.6ms，主标签一致率 28/29，
    /// 所以没必要为了分类去解码原图。
    static func analyze(_ cg: CGImage) -> VisionFacts? {
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])

        let classify = VNClassifyImageRequest()
        let faceReq = VNDetectFaceRectanglesRequest()
        var requests: [VNRequest] = [classify, faceReq]

        var aesReq: VNCalculateImageAestheticsScoresRequest?
        if #available(macOS 15.0, *) {
            let r = VNCalculateImageAestheticsScoresRequest()
            aesReq = r
            requests.append(r)
        }

        do {
            try handler.perform(requests)
        } catch {
            return nil
        }

        let results = classify.results ?? []
        guard let top = results.first, top.confidence > 0.02 else { return nil }

        let aes: Double?
        if #available(macOS 15.0, *), let r = aesReq?.results?.first {
            // ⚠️ overallScore 的原始范围是 **-1…1**，不是 0…1。
            // 直接当 0…1 用会让负数被压进最低档、均值被整体拉低（实测相册里有 -0.83 的）。
            // 这里统一归一化到 0…1，上层就只处理一种量纲。
            aes = (Double(r.overallScore) + 1) / 2
        } else {
            aes = nil
        }

        // 人脸面积用来区分「人像」和「风景里有个路人」：
        // 只看 faces > 0 的话，远景里任何一张小脸都会把照片判成人像。
        let faceObs = faceReq.results ?? []
        let maxFaceArea = faceObs
            .map { Double($0.boundingBox.width * $0.boundingBox.height) }
            .max() ?? 0

        return VisionFacts(
            labels: results.prefix(6).map { $0.identifier },
            confidence: Double(top.confidence),
            aesthetics: aes,
            faces: faceObs.count,
            maxFaceArea: maxFaceArea,
            isUtility: {
                if #available(macOS 15.0, *), let r = aesReq?.results?.first { return r.isUtility }
                return false
            }()
        )
    }

    /// 从 CGImageSource 直接取 512px 缩略图再分析——比解码全图快一个量级。
    static func analyze(source: CGImageSource) -> VisionFacts? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            return nil
        }
        return analyze(thumb)
    }

    /// 英文 identifier → 中文展示名。没收录的就把下划线换成空格。
    static func zh(_ label: String) -> String {
        switch label {
        case "people": return "人物"
        case "adult": return "成年人"
        case "child": return "孩子"
        case "baby": return "婴儿"
        case "portrait": return "肖像"
        case "face": return "面部"
        case "smile": return "笑容"
        case "outdoor": return "户外"
        case "indoor": return "室内"
        case "sky": return "天空"
        case "blue_sky": return "蓝天"
        case "cloud": return "云"
        case "sunset": return "日落"
        case "sunrise": return "日出"
        case "night": return "夜晚"
        case "nighttime": return "夜景"
        case "light": return "光线"
        case "water": return "水面"
        case "sea": return "海"
        case "lake": return "湖"
        case "river": return "河"
        case "beach": return "沙滩"
        case "mountain": return "山"
        case "land": return "陆地"
        case "grass": return "草地"
        case "forest": return "森林"
        case "tree": return "树"
        case "flower": return "花"
        case "plant": return "植物"
        case "garden": return "花园"
        case "house": return "房屋"
        case "structure": return "建筑"
        case "architecture": return "建筑"
        case "building": return "楼房"
        case "room": return "房间"
        case "furniture": return "家具"
        case "table": return "桌面"
        case "food": return "食物"
        case "meal": return "餐食"
        case "drink": return "饮品"
        case "animal": return "动物"
        case "dog": return "狗"
        case "cat": return "猫"
        case "bird": return "鸟"
        case "insect": return "昆虫"
        case "arthropods": return "节肢动物"
        case "vehicle": return "车辆"
        case "car": return "汽车"
        case "transport": return "交通"
        case "sport": return "运动"
        case "running": return "跑步"
        case "athletics": return "竞技"
        case "celebration": return "庆典"
        case "ceremony": return "仪式"
        case "wedding": return "婚礼"
        case "clothing": return "服饰"
        case "art": return "艺术"
        case "painting": return "绘画"
        case "text": return "文字"
        case "document": return "文档"
        case "screenshot": return "截图"
        case "recreation": return "娱乐"
        case "travel": return "旅行"
        case "urban": return "城市"
        case "city": return "城市"
        case "road": return "道路"
        case "rock": return "岩石"
        case "rocks": return "岩石"
        case "snow": return "雪"
        case "rain": return "雨"
        case "umbrella": return "雨伞"
        case "reflection": return "倒影"
        case "silhouette": return "剪影"
        case "darkness": return "暗部"
        default: return label.replacingOccurrences(of: "_", with: " ")
        }
    }
}

// MARK: - stats models
/// 统计页的时间范围过滤。
enum StatsRange: String, CaseIterable, Identifiable {
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
    let id = UUID()
    let date: Date, label: String, count: Int
}
/// 健康度的一个分项。
/// 用 struct 而不是元组——ForEach 的 id 键路径取不到元组元素。
struct HealthRow: Identifiable, Equatable {
    let id = UUID()
    let name: String, value: Int, hint: String
}
/// 拍摄习惯健康度：四个分项加权得总分，越高越好。
struct HealthScore: Equatable {
    let exposure: Int, stability: Int, coverage: Int, variety: Int
    var total: Int {
        Int(Double(exposure) * 0.30 + Double(stability) * 0.25
            + Double(coverage) * 0.20 + Double(variety) * 0.25)
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
        [HealthRow(name: "曝光控制", value: exposure, hint: "过曝 / 欠曝越少越好"),
         HealthRow(name: "手持稳定", value: stability, hint: "慢门糊片风险越低越好"),
         HealthRow(name: "数据完整", value: coverage, hint: "EXIF 原始参数占比"),
         HealthRow(name: "焦段多样", value: variety, hint: "用到的焦段越丰富越好")]
    }
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
    /// 跑过视觉模型的条目数
    let visionCount: Int
    /// 被判定为「非照片」（截图/文档/素材）的条目数
    let nonPhotoCount: Int
    /// 因判为文档/截图而被排除出所有分布统计的条目数（= 总数 − 参与统计数）
    let skippedCount: Int
    /// 平均美学分 0…1，没有视觉数据时为 0
    let meanAesthetics: Double
    /// 美学分分布
    let aestheticBuckets: [DistBucket]
}
private enum StatUtility {
    /// 把一组数值按给定区间切成直方图。
    private static func dist(_ values: [Double], _ bands: [(String, (Double) -> Bool)]) -> [DistBucket] {
        bands.map { label, test in DistBucket(label: label, count: values.filter(test).count) }
    }

    static func compute(_ es: [ExifEntry], range: StatsRange = .all) -> GlobalStats {
        let cal = Calendar.current
        // —— 时间范围过滤 ——
        let list: [ExifEntry] = {
            guard let d = range.days,
                  let from = cal.date(byAdding: .day, value: -d, to: Date()) else { return es }
            return es.filter { $0.capturedAt >= from }
        }()

        // 文档 / 截图没有拍摄意图，不参与「拍什么、用什么拍」的分布统计——
        // 混进来会把风景、室内弱光的占比整个拉偏（实测 500 张里有 104 张是文档截图）。
        // 它们仍会进到下面的 visionCount / nonPhotoCount，让用户知道跳过了多少。
        let usable: [ExifEntry] = list.filter { $0.isUtilityShot != true }
        let skippedCount = list.count - usable.count

        let total = usable.count
        let real = usable.filter { !$0.isAI }
        let aiCount = total - real.count
        // 失误率的分母用 EXIF 条目数，避免 AI 估算条目把比率稀释
        let realCount = max(real.count, 1)

        // —— 曝光与失误 ——
        let isoValues = real.compactMap { e in e.iso }.map { v in Double(v) }
        let secList = real.compactMap { e in Helper.secondsOf(e.shutterSpeed) }
        let slowCount = secList.filter { $0 > Helper.slowShutterSeconds }.count
        let blurCount = real.filter { ($0.iso ?? 0) > 1600 || (Helper.secondsOf($0.shutterSpeed) ?? 0) > Helper.slowShutterSeconds }.count
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
        for e in usable {
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
        for e in usable {
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
        for e in usable {
            let c = cal.dateComponents([.year, .month], from: e.capturedAt)
            guard let y = c.year, let m = c.month,
                  let first = cal.date(from: DateComponents(year: y, month: m, day: 1)) else { continue }
            let key = "\(y)-\(m)"
            if let cur = monthMap[key] { monthMap[key] = (cur.0, cur.1 + 1) }
            else { monthMap[key] = (first, 1) }
        }
        let monthly = monthMap.values.sorted { $0.0 < $1.0 }.suffix(12).map { d, n in
            // 带上年份，避免跨年时两个「12月」无法区分
            MonthPoint(date: d,
                       label: "\(cal.component(.year, from: d) % 100)年\(cal.component(.month, from: d))月",
                       count: n)
        }

        // —— 连续参数分布 ——
        let apValues = real.compactMap { e in e.aperture }
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
        // 焦距按「等效 35mm」分档，手机和相机因此在同一口径上可比。
        let focalValues = usable.compactMap { Helper.equivalentFocal($0) }
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
        for e in usable {
            scene[Helper.analyzeScene(e), default: 0] += 1
            light[Helper.analyzeLight(e), default: 0] += 1
            if let s = Helper.analyzeSupport(e) { support[s, default: 0] += 1 }
        }
        let lensCounts: [String: Int] = usable.reduce(into: [:]) { acc, e in
            acc[Helper.lensLabel(e), default: 0] += 1
        }
        let orderedLens = lensCounts.sorted { $0.value > $1.value }.map { LensUsage(label: $0.key, count: $0.value) }
        var camC: [String: Int] = [:]
        for e in usable {
            if let m = e.phoneModel?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
                camC[m, default: 0] += 1
            }
        }
        let cameraModels = camC.sorted { $0.value > $1.value }.map { NamedCount(name: $0.key, count: $0.value) }

        let topSceneLabel = scene.max(by: { $0.value < $1.value })?.key.rawValue
        let topFocalLabel = orderedLens.first?.label

        // —— 视觉模型给出的画面质量 ——
        // usable 已经在上面剔掉了文档/截图，这里只要再确认跑过 Vision。
        let photoish = usable.filter { $0.hasVision }
        let aesValues = photoish.compactMap { $0.aesthetics }
        let meanAesthetics = aesValues.isEmpty ? 0 : aesValues.reduce(0, +) / Double(aesValues.count)
        let aestheticBuckets = dist(aesValues, [
            ("<0.5", { $0 < 0.5 }),
            ("0.5-0.6", { $0 >= 0.5 && $0 < 0.6 }),
            ("0.6-0.7", { $0 >= 0.6 && $0 < 0.7 }),
            ("0.7-0.8", { $0 >= 0.7 && $0 < 0.8 }),
            ("0.8-0.9", { $0 >= 0.8 && $0 < 0.9 }),
            ("≥0.9", { $0 >= 0.9 }),
        ])
        let visionCount = list.filter { $0.hasVision }.count
        let nonPhotoCount = list.filter { $0.isNonPhoto }.count

        // —— 健康度评分 ——
        let exposureScore = Int(max(0, min(100, 100 - (blownRate + underRate) * 200)))
        let stabilityScore = Int(max(0, min(100, 100 - blurRate * 150)))
        let coverageScore = Int(min(100, Double(real.count) / Double(max(total, 1)) * 100))
        let usedFocal = focalBuckets.filter { $0.count > 0 }.count
        let varietyScore = Int(min(100, Double(usedFocal) / 5.0 * 100))
        let health = HealthScore(exposure: exposureScore, stability: stabilityScore,
                                 coverage: coverageScore, variety: varietyScore)

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
            health: health,
            visionCount: visionCount, nonPhotoCount: nonPhotoCount, skippedCount: skippedCount,
            meanAesthetics: meanAesthetics, aestheticBuckets: aestheticBuckets
        )
    }
}

// MARK: - growth persistence
struct GrowSummary: Codable, Hashable {
    /// 快照取在每天 00:00，记录的是「这一天」而非「这一周」——历史最多留 8 条。
    let snapshotDay: Date, total: Int, aiCount: Int, meanISO: Double
    let blurRate: Double, blownRate: Double, underRate: Double
}
/// Swift 6 严格并发要求静态可变状态有明确隔离：读写方（快照落盘、成长页）本就都在主线程。
@MainActor
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
        // 按天去重后仍会无限增长，滚动窗口只保留最近 60 条（成长页只展示 8 条）
        if all.count > 60 { all = Array(all.suffix(60)) }
        GrowthStore.all = all
    }
}

// MARK: - store
@MainActor final class ShotStore: ObservableObject {
    @Published var entries: [ExifEntry] = []
    @Published var grant: Grant = .notDetermined
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var statusMessage = ""

    /// 「优化 app，不要每次打开都要获取权限，获取一次就够了」：
    /// 启动时**同步**读取系统里真实的授权状态并写回 grant，
    /// 这样 RootView 第一次渲染就能落在正确分支——
    /// 已授权的用户直接进 StartView，不会再掉进 PermissionView 又被推开一次。
    /// 注意：这里只读不请求；真正首次未确定时仍由 ensurePermission() 弹系统框。
    init() {
        refreshGrant()
    }

    /// 只同步系统里真实的授权状态（不弹窗）：init 与回到前台时调用。
    func refreshGrant() {
        grant = Grant.fromPH(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    /// 相册授权：只在需要时请求，避免启动即弹窗。
    func ensurePermission() async {
        if grant == .notDetermined {
            grant = Grant.fromPH(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
        } else {
            refreshGrant()
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
        // 全列表按拍摄时间排序：并发解析的回传顺序不定，对比页的「最近 N 张」也依赖这个顺序
        entries.sort { $0.capturedAt < $1.capturedAt }
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
        entries = scanned.sorted { $0.capturedAt < $1.capturedAt }
        hasScanned = true
        isScanning = false
        await persistWeekSnapshot()
    }
    /// 清空当前结果回到选片引导页。
    func reset() {
        entries = []
        hasScanned = false
        refreshGrant()
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
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .frame(width: 72, height: 72)
                .background(Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
    @State private var image: NSImage? = nil
    var body: some View {
        ZStack {
            Rectangle().fill(Luma.muted.opacity(0.18))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").font(.title).foregroundStyle(Luma.muted)
            }
        }
        .task { image = await Helper.heroImageForAsset(id: assetIdentifier) }
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
                listVisionSection
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
            Text(isAI ? "本页分析基于 AI 推断，非原始拍摄数据"
                 : (entry.hasVision ? "参数来自相机 EXIF · 画面内容来自系统内置视觉模型"
                                    : "全部数据来自相机 EXIF / 原始拍摄"))
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
            paramRow("焦距", Helper.focalText(entry))
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

    /// 系统内置视觉模型读出来的画面内容。模型权重在 macOS 里，app 不打包任何文件。
    @ViewBuilder
    private var listVisionSection: some View {
        if entry.hasVision {
            Card(title: "画面识别", trailing: "Vision 内置模型") {
                VStack(alignment: .leading, spacing: 12) {
                    TagsList(tags: visionTags)
                    if let a = entry.aesthetics {
                        aestheticRow(a)
                    }
                    if entry.isNonPhoto {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(Luma.warn)
                            Text("系统判定这一张属于文档 / 截图类，不计入画面美学均值。")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private var visionTags: [Tag] {
        var out: [Tag] = []
        var seen = Set<String>()
        for id in (entry.visionLabels ?? []).prefix(5) {
            let name = VisionAnalyzer.zh(id)
            guard !seen.contains(name) else { continue }
            seen.insert(name)
            out.append(Tag(name, icon: "sparkles", tint: Luma.aiEstimate, source: .ai))
        }
        if let f = entry.faceCount, f > 0 {
            out.append(Tag("\(f) 张脸", icon: "face.smiling", tint: Luma.accent, source: .ai))
        }
        return out
    }

    private func aestheticRow(_ score: Double) -> some View {
        let tint: Color = score >= 0.7 ? Luma.ok : (score >= 0.5 ? Luma.accent : Luma.warn)
        let grade: String = {
            switch score {
            case 0.85...: return "很出彩"
            case 0.7..<0.85: return "不错"
            case 0.55..<0.7: return "一般"
            case 0.4..<0.55: return "偏弱"
            default: return "待提升"
            }
        }()
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("画面美学").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(grade).font(.caption).fontWeight(.medium).foregroundStyle(tint)
                Text(String(format: "%.2f", score))
                    .font(.caption).monospacedDigit().foregroundStyle(tint)
            }
            GeometryReader { geo in
                Capsule().fill(Luma.ink.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint)
                            .frame(width: max(3, CGFloat(score) * geo.size.width))
                    }
            }
            .frame(height: 5)
            Text("系统美学模型给出的构图与观感评分，与曝光参数无关")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
    private var listAdviceSection: some View {
        Card(title: "拍摄问题诊断") {
            VStack(spacing: 8) {
                ForEach(Helper.adviseFor(entry)) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.positive ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(item.positive ? Luma.ok : Luma.warn)
                            .padding(6)
                            .background((item.positive ? Luma.ok : Luma.warn).opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline).fontWeight(.semibold)
                            Text(item.text).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(insetFill(cs), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}

struct LibraryView: View {
    @ObservedObject var store: ShotStore
    @State private var compareSheet: Bool = false
    @State private var importSheet: Bool = false
    @State private var segment: Int = 0
    @State private var density: ListDensity = .comfortable
    @Environment(\.colorScheme) private var cs
    var body: some View {
        VStack(spacing: 0) {
            Picker("分区", selection: $segment) {
                Text("照片").tag(0)
                Text("统计").tag(1)
                Text("成长").tag(2)
                Text("提示").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
                Button { importSheet = true } label: { Label("添加照片", systemImage: "plus") }
                    .help("继续添加照片到分析中")
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
        .sheet(isPresented: $importSheet) { ImportView(store: store) }
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
                    .foregroundStyle(Color.primary.opacity(0.85))
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
                .foregroundStyle(Color.primary.opacity(0.85))
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
    @State private var image: NSImage? = nil
    var body: some View {
        ZStack {
            Rectangle().fill(Luma.muted.opacity(0.25))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: edge * 0.32))
                    .foregroundStyle(Luma.muted)
            }
        }
        .frame(width: edge, height: edge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        // 尺寸参与 task id：密度切换后按新尺寸重新取图（缓存键也带尺寸）
        .task(id: "\(assetIdentifier)-\(Int(edge))") {
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
    "焦距已统一为 35mm 等效：24mm 以下偏广角，50mm 以上是长焦。",
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
        aestheticSection(s)
        errorSection(s)
        insightSection(s)
    }

    // MARK: 画面美学（系统视觉模型）
    /// 这一块是纯新增维度：原来的健康分只看曝光/稳定，完全不知道照片好不好看。
    @ViewBuilder
    private func aestheticSection(_ s: GlobalStats) -> some View {
        if s.visionCount > 0 {
            let maxC = max(s.aestheticBuckets.map(\.count).max() ?? 1, 1)
            let photoTotal = s.aestheticBuckets.reduce(0) { $0 + $1.count }
            Card(title: "画面美学", trailing: "Vision 内置模型") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.2f", s.meanAesthetics))
                            .font(.title2).bold().monospacedDigit()
                            .foregroundStyle(s.meanAesthetics >= 0.7 ? Luma.ok : Luma.accent)
                        Text("平均美学分").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(photoTotal) 张计入")
                            .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(s.aestheticBuckets) { b in
                            shareRow(label: b.label, count: b.count, maxCount: maxC,
                                     tint: Luma.aiEstimate, total: photoTotal)
                        }
                    }
                    if s.nonPhotoCount > 0 {
                        Text("另有 \(s.nonPhotoCount) 张被系统识别为文档或截图，未计入美学均值")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: 头部与时间范围
    private func header(_ s: GlobalStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("拍摄统计画像").font(.title2).bold()
            Text("共 \(s.total) 张参与统计 · EXIF \(s.exifCount)"
                 + (s.aiCount > 0 ? " · AI 推算 \(s.aiCount)" : "")
                 + (s.skippedCount > 0 ? " · 另有 \(s.skippedCount) 张文档/截图未计入" : ""))
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private var rangePicker: some View {
        Picker("时间范围", selection: $range) {
            ForEach(StatsRange.allCases) { r in Text(r.rawValue).tag(r) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
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
        return Card(title: "拍摄习惯健康度", trailing: h.grade) {
            HStack(alignment: .center, spacing: 20) {
                ScoreRing(score: h.total, tint: h.tint)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(h.rows) { r in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(r.name).font(.caption).fontWeight(.medium)
                                Spacer()
                                Text("\(r.value)")
                                    .font(.caption).bold().monospacedDigit()
                                    .foregroundStyle(h.tint)
                            }
                            Capsule().fill(insetFill(cs)).frame(height: 4)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(h.tint)
                                        .frame(width: max(3, CGFloat(r.value) / 100 * 160))
                                }
                                .frame(width: 160)
                                .animation(.easeOut(duration: 0.45), value: r.value)
                            Text(r.hint).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 概览瓷砖
    private func overviewTiles(_ s: GlobalStats) -> some View {
        let tiles: [(String, String, String, String, Color)] = [
            ("photo.on.rectangle", "\(s.total)", "张", "解析照片", Luma.accent),
            ("gauge", String(format: "%.0f", s.meanISO), "", "平均 ISO", Color.primary),
            ("calendar", String(format: "%.1f", s.perDay), "张/天", "拍摄节奏", Luma.ok),
            ("sun.and.horizon", String(format: "%.0f%%", s.goldenRate * 100), "", "黄金时刻", Luma.warn)
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
            ForEach(0..<tiles.count, id: \.self) { i in
                let (icon, value, unit, label, tint) = tiles[i]
                Tile {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(value).font(.title2).bold().monospacedDigit().foregroundStyle(tint)
                            if !unit.isEmpty {
                                Text(unit).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 4) {
                            Image(systemName: icon).font(.caption2).foregroundStyle(tint)
                            Text(label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
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
    private func trendSection(_ s: GlobalStats) -> some View {
        let pts = s.monthly
        let maxC = max(pts.map { $0.count }.max() ?? 1, 1)
        return Card(title: "拍摄量趋势", trailing: pts.isEmpty ? nil : "近 \(pts.count) 个月") {
            if pts.isEmpty {
                Text("暂无数据").font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(pts) { p in
                        VStack(spacing: 4) {
                            Text("\(p.count)").font(.caption2).monospacedDigit()
                                .foregroundStyle(.secondary)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Luma.accent.opacity(0.85))
                                .frame(height: max(3, CGFloat(p.count) / CGFloat(maxC) * 80))
                            Text(p.label).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.easeOut(duration: 0.35), value: pts)
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
        return Card(title: "参数分布", trailing: kDistTabs[idx]) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("维度", selection: $distTab) {
                    ForEach(0..<kDistTabs.count, id: \.self) { i in Text(kDistTabs[i]).tag(i) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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
                .animation(.easeOut(duration: 0.35), value: distTab)
                Text(distNote(idx, s)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// ISO 那一档的说明改成按实际分布说话。
    /// 原来固定写「整体偏高说明常在弱光下拍摄」，可实测 57% 的照片 ISO 都在 400 以内，
    /// 文案和数字正好相反。
    private func distNote(_ idx: Int, _ s: GlobalStats) -> String {
        guard idx == 0 else { return kDistNotes[idx] }
        let total = max(s.isoBuckets.reduce(0) { $0 + $1.count }, 1)
        let low = s.isoBuckets.prefix(2).reduce(0) { $0 + $1.count }    // ≤400
        let high = s.isoBuckets.suffix(2).reduce(0) { $0 + $1.count }   // >1600
        let lowPct = low * 100 / total
        let highPct = high * 100 / total
        if highPct >= 25 {
            return "\(highPct)% 的照片 ISO 高于 1600，弱光场景偏多，留意噪点。"
        }
        if lowPct >= 50 {
            return "\(lowPct)% 的照片 ISO 在 400 以内，多数拍于光线充足时，画质底子干净。"
        }
        return "ISO 分布较均衡：\(lowPct)% 在 400 以内，\(highPct)% 超过 1600。"
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
            .animation(.easeOut(duration: 0.35), value: s.buckets)
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
                            shareRow(label: m.name, count: m.count, maxCount: camMax, tint: Luma.muted)
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
                        .background(insetFill(cs), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            Text(value).font(.subheadline).bold().monospacedDigit().foregroundStyle(Color.primary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(insetFill(cs), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        Tile(tint: rate > 0 ? tint : nil) {
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
                                    .animation(.easeOut(duration: 0.45), value: rate)
                            }
                        }
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
    /// 分布条。`total` 给了就在张数后面补占比——美学分布里最大的一档能占到近一半，
    /// 光看绝对张数不容易判断「这是我分布窄，还是这一档特别突出」。
    /// 条形宽度用 GeometryReader 自适应，原来写死 190 宽，卡片一拉宽右边就空一大片。
    private func shareRow(label: String, count: Int, maxCount: Int, tint: Color, total: Int? = nil) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.subheadline).lineLimit(1)
                .frame(minWidth: 56, maxWidth: 110, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.12))
                    Capsule().fill(count > 0 ? tint : tint.opacity(0.25))
                        .frame(width: max(6, CGFloat(count) / CGFloat(max(maxCount, 1)) * geo.size.width))
                }
            }
            .frame(height: 8)
            Text(total.map { "\(count) · \(pct(count, $0))" } ?? "\(count)")
                .font(.subheadline).monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: total == nil ? 32 : 96, alignment: .trailing)
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
        if let f = s.topFocalLabel {
            out.append("最常用的视角是\(f)，说明你偏爱这类构图。")
        }
        if let sc = s.topSceneLabel {
            out.append("拍得最多的是\(sc)题材。")
        }
        if s.perDay >= 8 {
            out.append("拍摄节奏很密，活跃日平均 \(String(format: "%.1f", s.perDay)) 张。")
        }
        if let d = s.busiestDay, s.busiestCount >= 3 {
            out.append("最高产的一天是 \(d.formatted(.dateTime.month().day()))，一口气拍了 \(s.busiestCount) 张。")
        }
        return Array(out.prefix(5))
    }
}

/// 健康度总分环形图：首次出现时从 0 扫到目标分，切换时间范围时平滑过渡。
struct ScoreRing: View {
    let score: Int, tint: Color
    @State private var progress: CGFloat = 0
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(score, 100))) / 100 * progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)").font(.title).bold().monospacedDigit().foregroundStyle(tint)
                Text("分").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
        .animation(.easeOut(duration: 0.6), value: score)
        .onAppear {
            guard progress == 0 else { return }
            withAnimation(.easeOut(duration: 0.8).delay(0.15)) { progress = 1 }
        }
    }
}

struct CompareView: View {
    @ObservedObject var store: ShotStore
    @Environment(\.colorScheme) private var cs
    var body: some View {
        let real = store.entries.filter { !$0.isAI }
        let selected = Array(real.suffix(4))
        if selected.count >= 2 {
            ComparisonGrid(entries: selected, scheme: cs)
        } else {
            EmptyStateView(title: "至少需要 2 张照片", text: "选择更多带 EXIF 的照片后可进行对比")
        }
    }
}

struct ComparisonGrid: View {
    let entries: [ExifEntry]
    let scheme: ColorScheme
    @State private var picked: ExifEntry?
    var body: some View {
        // 对比视图在 sheet 里呈现，同样不用 NavigationView（见 ImportView 的说明）
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("对比分析").font(.headline)
                    Text("最近的 \(entries.count) 张照片 · 点击查看完整解析")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(Luma.accent)
            }
            .padding(16)
            Divider()
            List {
                ForEach(entries) { e in
                    Button { picked = e } label: { entryRow(e) }
                        .buttonStyle(.plain)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 560, minHeight: 400)
        .background(schemeBg(scheme))
        .sheet(item: $picked) { e in SingleShotView(entry: e) }
    }
    private func entryRow(_ e: ExifEntry) -> some View {
        HStack(spacing: 12) {
            EntryThumbView(assetIdentifier: e.assetIdentifier)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.phoneModel ?? "无机型信息").font(.body).fontWeight(.medium)
                Text(Helper.paramSummary(e)).font(.caption).foregroundStyle(.secondary)
                Text("环境 \(Helper.analyzeLight(e).rawValue) / \(Helper.analyzeScene(e).rawValue)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
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

        let slow = real.compactMap { Helper.secondsOf($0.shutterSpeed) }.filter { $0 > Helper.slowShutterSeconds }
        if Double(slow.count) / rcount > 0.30 {
            out.append(TipItem(
                icon: "camera.viewfinder", title: "快门偏慢",
                message: "有 \(slow.count) 张快门慢于 1/30s。手持时建议架三脚架或切大光圈缩短曝光时间。",
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
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // 用户可能在系统设置里改完权限再切回来——每次激活都同步一次真实状态，
                // 否则被拒后即使重新授权，界面也会永远卡在「权限未开启」
                store.refreshGrant()
            }
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

/// 「先选照片再读信息」的落地页。启动后不必自动扫全库——等用户主动选片。
struct StartView: View {
    @ObservedObject var store: ShotStore
    @Environment(\.colorScheme) private var cs
    @State private var importPresenting = false
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
                Button { importPresenting = true } label: {
                    Label("选择照片解析", systemImage: "photo.badge.plus")
                        .frame(width: 240)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("或自动扫描最近的 500 张照片") { Task { await store.scanWholeLibrary() } }
                    .buttonStyle(.link)
                    .font(.subheadline)
            }
            Text("受限模式下只能看到已允许访问的照片，可随时在系统设置里调整")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(Luma.sp32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(schemeBg(cs))
        .sheet(isPresented: $importPresenting) { ImportView(store: store) }
    }
}

/// 相册网格多选：勾选 → 返回资产标识符 → 由 store并发解析 EXIF 并合并去重。
/// 注意：macOS 上 sheet 里不能嵌 NavigationView——内容切换时底层的
/// NSSplitViewController 会在约束更新中移除 split item 失败，直接抛异常崩溃，
/// 所以这里用自绘头部栏。
struct ImportView: View {
    @ObservedObject var store: ShotStore
    @Environment(\.dismiss) private var dismiss
    @State private var assetIDs: [String] = []
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
                    .background(selected.isEmpty ? Color.primary.opacity(0.06) : Luma.accent.opacity(0.12), in: Capsule())
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
                        ForEach(assetIDs, id: \.self) { id in
                            ImageCell(assetID: id, selected: selected.contains(id))
                                .onTapGesture {
                                    if selected.contains(id) { selected.remove(id) }
                                    else { selected.insert(id) }
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
        // 后台只做数据库查询并提取标识符；PHAsset 非 Sendable 不能跨并发域传递，
        // 网格端按 id 直接取缩略图即可
        let ids: [String] = await Task.detached(priority: .userInitiated) { () -> [String] in
            let opts = PHFetchOptions()
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            opts.fetchLimit = 500
            return Helper.identifiers(from: PHAsset.fetchAssets(with: opts))
        }.value
        assetIDs = ids
        loaded = true
    }
}

/// 带勾选标记的网格缩略图：按 id 异步取图，点击切换选中态。
struct ImageCell: View {
    let assetID: String
    let selected: Bool
    @State private var image: NSImage? = nil
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
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
        .task(id: assetID) { image = await Helper.thumbnailForAsset(id: assetID, size: 300) }
    }
}

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