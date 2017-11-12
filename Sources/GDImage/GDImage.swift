#if os(Linux)
    import Glibc
    import gdlinux
#else
    import Darwin
    import gdmac
#endif

import Foundation

public struct GDPoint {
    var x: Int32
    var y: Int32

    init(x: Int32, y: Int32) {
        self.x = x
        self.y = y
    }
}

public struct GDSize {
    var width: Int32
    var height: Int32

    init(width: Int32, height: Int32) {
        self.width = width
        self.height = height
    }
}

public struct GDRect {
    var origin : GDPoint
    var size : GDSize

    init(origin:GDPoint, size:GDSize) {
        self.origin = origin
        self.size = size
    }

    var rect : gdRect {
        return gdRect(x: self.origin.x, y: self.origin.y, width: self.size.width, height: self.size.height)
    }

    var p1 : GDPoint {
        return self.origin
    }
    var p2 : GDPoint {
        return GDPoint(x: self.origin.x + self.size.width, y: self.origin.y + self.size.height)
    }
}

public class GDColor {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    init(color:Int32) {
        self.alpha   = 1 - (Double((color >> 24) & 0xFF) / 127)
        self.red     = Double((color >> 16) & 0xFF) / 255
        self.green   = Double((color >> 8) & 0xFF) / 255
        self.blue    = Double(color & 0xFF) / 255
    }

    func color(for image:GDImage) -> Int32 {
        return gdImageColorAllocateAlpha(
            image.imagePtr,
            Int32(self.red * 255.0),
            Int32(self.green * 255.0),
            Int32(self.blue * 255.0),
            127 - Int32(self.alpha * 127.0)
        )
    }


    static let red = GDColor(red: 1, green: 0, blue: 0, alpha: 1)
    static let green = GDColor(red: 0, green: 1, blue: 0, alpha: 1)
    static let blue = GDColor(red: 0, green: 0, blue: 1, alpha: 1)
    static let black = GDColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let white = GDColor(red: 1, green: 1, blue: 1, alpha: 1)
}

public enum GDGravity {
    case north
    case south
    case east
    case west
    case north_east
    case north_west
    case south_east
    case south_west
    case middle
}


public class GDImage {

    var imagePtr : gdImagePtr
    var size : GDSize {
        return GDSize(width: self.imagePtr.pointee.sx, height: self.imagePtr.pointee.sy)
    }

    deinit {
        gdImageDestroy(self.imagePtr)
    }

    init(ptr:gdImagePtr) {
        self.imagePtr = ptr
    }

    init?(size:GDSize) {
        guard let ptr = gdImageCreateTrueColor(size.width, size.height) else {
            return nil
        }
        self.imagePtr = ptr
    }

    init?(path:String) {
        guard let input = fopen(path, "rb") else {
            return nil
        }
        defer {
            fclose(input)
        }

        var ptr : gdImagePtr?
        let lastComp = (path as NSString).lastPathComponent
        var triedJpg = false
        var triedPng = false
        if lastComp.hasSuffix("jpg") || lastComp.hasSuffix("jpeg") {
            ptr = gdImageCreateFromJpeg(input)
            triedJpg = true
        } else if lastComp.hasSuffix("png") {
            ptr = gdImageCreateFromPng(input)
            triedPng = true
        }

        if nil == ptr {
            rewind(input)
            if !triedJpg {
                ptr = gdImageCreateFromJpeg(input)
            }
        }

        if nil == ptr {
            rewind(input)
            if !triedPng {
                ptr = gdImageCreateFromPng(input)
            }
        }

        guard let imgPtr = ptr else {
            return nil
        }
        self.imagePtr = imgPtr
    }

    @discardableResult
    func write(to path:String, quality:Int = 100, overwrite:Bool = false) -> Bool {
        let ext = (path as NSString).pathExtension
        guard ext == "png" || ext == "jpeg" || ext == "jpg" else {
            return false
        }

        if !overwrite {
            guard !FileManager().fileExists(atPath: path) else {
                return false
            }
        }

        guard let output = fopen(path, "wb+") else {
            return false
        }
        defer {
            fclose(output)
        }

        if ext == "png" {
            gdImageSaveAlpha(self.imagePtr, 1)
            gdImagePng(self.imagePtr, output)
        } else {
            gdImageJpeg(self.imagePtr, output, Int32(quality))
        }

        return true
    }

    func copy(from:GDImage) {
        gdImageCopy(self.imagePtr, from.imagePtr, 0, 0, 0, 0, from.size.width, from.size.height)
    }

    func get(pixel:GDPoint) -> GDColor {
        return GDColor(color: gdImageGetTrueColorPixel(self.imagePtr, pixel.x, pixel.y))
    }

    func fill(with color:GDColor) {
        self.fill(rectangle: GDRect(origin:GDPoint(x: 0, y: 0), size:self.size), color: color)
    }

    func fill(rectangle:GDRect, color:GDColor) {
        let p1 = rectangle.p1
        let p2 = rectangle.p2
        gdImageFilledRectangle(self.imagePtr, p1.x, p1.y, p2.x, p2.y, color.color(for: self))
    }

    func resizedTo(width: Int32, height: Int32, applySmoothing: Bool = true) -> GDImage? {
        let currentSize = self.size
        guard currentSize.width != width || currentSize.height != height else { return self }

        if applySmoothing {
            gdImageSetInterpolationMethod(self.imagePtr, GD_BILINEAR_FIXED)
        } else {
            gdImageSetInterpolationMethod(self.imagePtr, GD_NEAREST_NEIGHBOUR)
        }

        guard let output = gdImageScale(self.imagePtr, UInt32(width), UInt32(height)) else { return nil }
        return GDImage(ptr: output)
    }

    func resizedTo(width: Int32, applySmoothing: Bool = true) -> GDImage? {
        let currentSize = self.size
        guard currentSize.width != width else { return self }

        if applySmoothing {
            gdImageSetInterpolationMethod(self.imagePtr, GD_BILINEAR_FIXED)
        } else {
            gdImageSetInterpolationMethod(self.imagePtr, GD_NEAREST_NEIGHBOUR)
        }

        let heightAdjustment = Double(width) / Double(currentSize.width)
        let newHeight = Double(currentSize.height) * Double(heightAdjustment)

        guard let output = gdImageScale(self.imagePtr, UInt32(width), UInt32(newHeight)) else { return nil }
        return GDImage(ptr: output)
    }

    func resizedTo(maxWidth:Int32, applySmoothing: Bool = true) -> GDImage? {
        if self.size.width > maxWidth {
            return self.resizedTo(width: maxWidth, applySmoothing:applySmoothing)
        }
        return self
    }

    func resizedTo(height: Int32, applySmoothing: Bool = true) -> GDImage? {
        let currentSize = self.size
        guard currentSize.height != height else { return self }

        if applySmoothing {
            gdImageSetInterpolationMethod(self.imagePtr, GD_BILINEAR_FIXED)
        } else {
            gdImageSetInterpolationMethod(self.imagePtr, GD_NEAREST_NEIGHBOUR)
        }

        let widthAdjustment = Double(height) / Double(currentSize.height)
        let newWidth = Double(currentSize.width) * Double(widthAdjustment)

        guard let output = gdImageScale(self.imagePtr, UInt32(newWidth), UInt32(height)) else { return nil }
        return GDImage(ptr: output)
    }


    func crop(to:GDRect) -> GDImage? {
        var box = to.rect
        guard let output = gdImageCrop(self.imagePtr, &box) else {
            return nil
        }
        return GDImage(ptr: output)
    }

    func crop(x:Int32, y:Int32, width:Int32, height:Int32) -> GDImage? {
        var box = gdRect(x: x, y: y, width: width, height: height)
        guard let output = gdImageCrop(self.imagePtr, &box) else {
            return nil
        }
        return GDImage(ptr: output)
    }

    func squared(_ gravity:GDGravity = .middle) -> GDImage? {
        let size = self.size
        guard size.width != size.height else { return self }    // nothing to do, already squared
        let side = min(size.width, size.height)
        guard side > 0 else { return nil }

        let x:Int32
        let y:Int32

        switch gravity {
        case .north:
            x = (size.width - side)/2
            y = 0

        case .north_east:
            x = size.width - side
            y = 0

        case .north_west:
            x = 0
            y = 0

        case .west:
            x = 0
            y = (size.height - side)/2

        case .middle:
            x = (size.width - side)/2
            y = (size.height - side)/2

        case .east:
            x = size.width - side
            y = (size.height - side)/2

        case .south:
            x = (size.width - side)/2
            y = size.height - side

        case .south_east:
            x = size.width - side
            y = size.height - side

        case .south_west:
            x = 0
            y = size.height - side
        }

        return self.crop(x: x, y: y, width: side, height: side)
    }

}

