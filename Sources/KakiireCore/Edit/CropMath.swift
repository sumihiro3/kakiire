import CoreGraphics

/// 切り抜きの範囲を数値で決めるときの計算。
public enum CropMath {
    /// `rect` を整数の px に丸め、画像の中に収める。
    ///
    /// はみ出した分は大きさを保ったまま中へずらし、画像より大きければ画像の大きさで止める。幅・高さは最小 1px。
    public static func fit(_ rect: CGRect, in image: CGSize) -> CGRect {
        let r = rect.standardized
        let w = min(max(1, r.width.rounded()), image.width)
        let h = min(max(1, r.height.rounded()), image.height)
        let x = min(max(0, r.minX.rounded()), image.width - w)
        let y = min(max(0, r.minY.rounded()), image.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// 縦横比 `aspect` を保ったときの高さ(整数の px)。
    public static func height(forWidth w: CGFloat, keeping aspect: CGSize) -> CGFloat {
        guard aspect.width > 0 else { return w }
        return (w * aspect.height / aspect.width).rounded()
    }

    /// 縦横比 `aspect` を保ったときの幅(整数の px)。
    public static func width(forHeight h: CGFloat, keeping aspect: CGSize) -> CGFloat {
        guard aspect.height > 0 else { return h }
        return (h * aspect.width / aspect.height).rounded()
    }
}
