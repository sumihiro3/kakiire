import CoreGraphics
import CryptoKit
import Foundation

/// 取り込んだ元画像。中身は不変で、Document をコピーしても参照を共有する。
///
/// `@unchecked Sendable`:プロパティはすべて `let` で、生成後に変更されない。
public final class ImageAsset: @unchecked Sendable, Hashable {
    public let cgImage: CGImage
    /// エンコード済みの元データ(PNG)。保存時はこれをそのまま書く。
    public let data: Data
    /// `data` の SHA-256(16進小文字)。同一性の判定とキャッシュのキーに使う。
    public let sha256: String

    public init(cgImage: CGImage, data: Data) {
        self.cgImage = cgImage
        self.data = data
        self.sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public var pixelSize: CGSize { CGSize(width: cgImage.width, height: cgImage.height) }

    public static func == (a: ImageAsset, b: ImageAsset) -> Bool { a.sha256 == b.sha256 }
    public func hash(into h: inout Hasher) { h.combine(sha256) }
}

/// 元画像に対する無劣化の向き変更。
public enum Rotation: Int, Sendable, Codable, CaseIterable {
    case r0 = 0, r90 = 90, r180 = 180, r270 = 270
}

public struct BaseImage: Sendable, Equatable {
    public var asset: ImageAsset
    public var rotation: Rotation
    public var flipH: Bool
    public var flipV: Bool

    public init(asset: ImageAsset, rotation: Rotation = .r0, flipH: Bool = false, flipV: Bool = false) {
        self.asset = asset; self.rotation = rotation; self.flipH = flipH; self.flipV = flipV
    }

    /// 回転を適用した後のピクセルサイズ。注釈の座標はこの空間。
    public var pixelSize: CGSize {
        let s = asset.pixelSize
        return rotation == .r90 || rotation == .r270 ? CGSize(width: s.height, height: s.width) : s
    }

    public var isIdentity: Bool { rotation == .r0 && !flipH && !flipV }
}

/// 書き出し範囲と倍率。元画像は書き換えず、ここで非破壊に持つ。
public struct Canvas: Sendable, Equatable {
    /// 切り抜き範囲。nil は画像全体。
    public var crop: CGRect?
    public var outputScale: Double

    public init(crop: CGRect? = nil, outputScale: Double = 1) {
        self.crop = crop; self.outputScale = outputScale
    }
}

/// 編集中の文書全体。値型なので Undo 用に丸ごとコピーしても安い。
public struct Document: Sendable, Equatable {
    public var canvas: Canvas
    public var base: BaseImage
    public var annotations: [Annotation]

    public init(base: BaseImage, canvas: Canvas = Canvas(), annotations: [Annotation] = []) {
        self.base = base; self.canvas = canvas; self.annotations = annotations
    }

    /// 回転後の画像サイズ。
    public var pixelSize: CGSize { base.pixelSize }

    /// 書き出し前の切り抜き範囲(画像内に収めたもの)。
    public var effectiveCrop: CGRect {
        let full = CGRect(origin: .zero, size: pixelSize)
        guard let crop = canvas.crop else { return full }
        let r = crop.standardized.intersection(full)
        return r.isNull || r.isEmpty ? full : r
    }

    public func annotation(_ id: UUID) -> Annotation? { annotations.first { $0.id == id } }

    /// 種類ごとに「矢印 3」のような次の既定名を返す。`label` は App が表示言語で渡す種類の名前。
    public func nextName(for content: AnnotationContent, label: String) -> String {
        let n = annotations.filter { $0.content.kindKey == content.kindKey }.count + 1
        return "\(label) \(n)"
    }
}

// MARK: - document.json

/// document.json の内容。画像本体は持たず、`base.asset` のファイル名で参照する。
public struct DocumentDescriptor: Sendable, Equatable, Codable {
    public struct Base: Sendable, Equatable, Codable {
        public var asset: String
        public var rotation: Rotation
        public var flipH: Bool
        public var flipV: Bool

        public init(asset: String, rotation: Rotation = .r0, flipH: Bool = false, flipV: Bool = false) {
            self.asset = asset; self.rotation = rotation; self.flipH = flipH; self.flipV = flipV
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            asset = try c.decode(String.self, forKey: .asset)
            rotation = try c.decodeIfPresent(Rotation.self, forKey: .rotation) ?? .r0
            flipH = try c.decodeIfPresent(Bool.self, forKey: .flipH) ?? false
            flipV = try c.decodeIfPresent(Bool.self, forKey: .flipV) ?? false
        }
    }

    public var canvas: Canvas
    public var base: Base
    public var annotations: [Annotation]

    public init(canvas: Canvas, base: Base, annotations: [Annotation]) {
        self.canvas = canvas; self.base = base; self.annotations = annotations
    }
}

extension Canvas: Codable {
    enum Keys: String, CodingKey { case crop, outputScale }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if c.contains(.crop), try !c.decodeNil(forKey: .crop) {
            crop = try c.decodeRect(.crop)
        } else {
            crop = nil
        }
        outputScale = try c.decodeIfPresent(Double.self, forKey: .outputScale) ?? 1
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        if let crop { try c.encodeRect(crop, .crop) }
        try c.encode(outputScale, forKey: .outputScale)
    }
}

public extension Document {
    /// 保存用の記述子。元画像は `baseAssetName` のファイル名で参照する。
    func descriptor(baseAssetName: String = "base.png") -> DocumentDescriptor {
        DocumentDescriptor(
            canvas: canvas,
            base: .init(asset: baseAssetName, rotation: base.rotation, flipH: base.flipH, flipV: base.flipV),
            annotations: annotations)
    }

    /// 記述子と、そこから参照される元画像から文書を組み立てる。
    init(descriptor d: DocumentDescriptor, baseAsset: ImageAsset) {
        self.init(
            base: BaseImage(asset: baseAsset, rotation: d.base.rotation, flipH: d.base.flipH, flipV: d.base.flipV),
            canvas: d.canvas,
            annotations: d.annotations)
    }
}
