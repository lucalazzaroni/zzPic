import Foundation

/// Math on EXIF orientation values (1…8), used for lossless rotation.
public enum ExifOrientation {
    /// Each orientation as the 2×2 matrix that maps stored pixels to displayed pixels
    /// (x to the right, y downwards).
    private static let matrices: [UInt32: [Int]] = [
        1: [1, 0, 0, 1],    // up
        2: [-1, 0, 0, 1],   // mirrored horizontally
        3: [-1, 0, 0, -1],  // rotated 180°
        4: [1, 0, 0, -1],   // mirrored vertically
        5: [0, 1, 1, 0],    // transpose
        6: [0, -1, 1, 0],   // rotate 90° clockwise to display
        7: [0, -1, -1, 0],  // transverse
        8: [0, 1, -1, 0],   // rotate 90° counter-clockwise to display
    ]

    /// The orientation to store so that the displayed image is rotated by a further 90°.
    public static func rotated(_ orientation: UInt32, clockwise: Bool) -> UInt32 {
        let m = matrices[orientation] ?? matrices[1]!
        let r = clockwise ? [0, -1, 1, 0] : [0, 1, -1, 0]
        let product = [
            r[0] * m[0] + r[1] * m[2], r[0] * m[1] + r[1] * m[3],
            r[2] * m[0] + r[3] * m[2], r[2] * m[1] + r[3] * m[3],
        ]
        return matrices.first { $0.value == product }?.key ?? 1
    }

    /// `true` when the orientation swaps width and height.
    public static func swapsDimensions(_ orientation: UInt32) -> Bool {
        (5...8).contains(orientation)
    }
}
