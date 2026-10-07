// MacShot Simple, GPL-3.0. Manual vertical capture; conservative overlap matching.
import CoreGraphics
import Foundation

struct ScrollStitcher {
    enum Result: Equatable { case unchanged, appended(Int), unmatched, limit, invalid }
    private(set) var image: CGImage
    private(set) var previous: CGImage
    let maxHeight: Int
    let maxPixels: Int

    init(_ first: CGImage, maxHeight: Int = 20_000, maxPixels: Int = 40_000_000) {
        image = first; previous = first; self.maxHeight = maxHeight; self.maxPixels = maxPixels
    }

    static func fitsLimits(width:Int,height:Int,maxHeight:Int = 20_000,maxPixels:Int = 40_000_000) -> Bool {
        width > 0 && height > 0 && height <= maxHeight && height <= maxPixels/width
    }

    /// Normalize layouts rather than guessing the WindowServer's channel order.
    static func frame(_ image: CGImage) -> ScrollFrameAnalyzer.Frame? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let _ = image.colorSpace else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let result = context.makeImage() else { return nil }
        return ScrollFrameAnalyzer.frame(for: result)
    }

    static func difference(_ a: ScrollFrameAnalyzer.Frame, _ b: ScrollFrameAnalyzer.Frame,
                           x: Int, ay: Int, by: Int) -> Double {
        guard let ap = a.offset(x: x, y: ay), let bp = b.offset(x: x, y: by) else { return 255 }
        return Double(abs(Int(a.bytes[ap+a.redOffset])-Int(b.bytes[bp+b.redOffset]))
            + abs(Int(a.bytes[ap+a.greenOffset])-Int(b.bytes[bp+b.greenOffset]))
            + abs(Int(a.bytes[ap+a.blueOffset])-Int(b.bytes[bp+b.blueOffset]))) / 3
    }

    static func stable(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height, let af = frame(a), let bf = frame(b) else { return false }
        return stable(af,bf)
    }
    private static func stable(_ a:ScrollFrameAnalyzer.Frame,_ b:ScrollFrameAnalyzer.Frame) -> Bool {
        var sad = 0.0, count = 0.0
        for y in stride(from:0,to:a.height,by:max(1,a.height/60)) {
            for x in stride(from:a.width/10,to:a.width*9/10,by:max(1,a.width/40)) {
                sad += difference(a,b,x:x,ay:y,by:y); count += 1
            }
        }
        return count > 0 && sad/count < 0.8
    }

    mutating func append(_ current: CGImage) -> Result {
        guard current.width == previous.width, current.height == previous.height,
              current.width >= 32, current.height >= 64,
              let a = Self.frame(previous), let b = Self.frame(current) else { return .invalid }
        if Self.stable(a,b) { return .unchanged }
        let h = current.height, w = current.width
        // Ignore pinned rows in alignment; retain their appearance once in output.
        let header = min(h/4, ScrollFrameAnalyzer.frozenTopRows(current: b, previous: a, rightMarginPx: w/10) ?? 0)
        var footer = 0
        for y in stride(from: h-1, through: h-h/4, by: -1) {
            var sad = 0.0, count = 0.0
            for x in stride(from: w/10, to: w*9/10, by: max(1,w/32)) {
                sad += Self.difference(a,b,x:x,ay:y,by:y); count += 1
            }
            if count == 0 || sad/count > 3 { break }
            footer += 1
        }
        let bottom = h-footer, minOverlap = max(32,h/4)
        let maxShift = bottom-header-minOverlap
        guard maxShift >= 1 else { return .unmatched }
        // Weight visible content instead of allowing white margins to dominate
        // the score. A sparse regular grid can miss entire lines of small text.
        var points:[(Int,Int)] = []
        for y in stride(from:header,to:bottom,by:max(2,h/180)) {
            for x in stride(from:w/10,to:w*9/10,by:max(2,w/180)) {
                guard let p = b.offset(x:x,y:y),
                      let px = b.offset(x:min(w-1,x+2),y:y),
                      let py = b.offset(x:x,y:min(h-1,y+2)) else { continue }
                if [b.redOffset,b.greenOffset,b.blueOffset].contains(where:{
                    abs(Int(b.bytes[p+$0])-Int(b.bytes[px+$0])) > 12 ||
                    abs(Int(b.bytes[p+$0])-Int(b.bytes[py+$0])) > 12
                }) { points.append((x,y)) }
            }
        }
        if points.count > 1600 {
            let step = (points.count+1599)/1600
            points = stride(from:0,to:points.count,by:step).map { points[$0] }
        }
        func score(_ shift:Int) -> Double {
            var total=0.0, count=0
            var bins = [Int](repeating:0,count:256)
            var sums = [Double](repeating:0,count:256)
            for (x,y) in points where y < bottom-shift {
                let difference = Self.difference(a,b,x:x,ay:y+shift,by:y)
                let bin = Int(difference)
                bins[bin] += 1; sums[bin] += difference
                total += difference;count += 1
            }
            guard count >= 16 else { return 255 }
            // Small changing controls/caret/animation should not outweigh the
            // matching page. Trim only the worst 10%; uniqueness stays required.
            var remaining = count/10
            let retained = count-remaining
            for bin in stride(from:255,through:0,by:-1) where remaining > 0 && bins[bin] > 0 {
                let removed = min(remaining,bins[bin])
                total -= sums[bin]*Double(removed)/Double(bins[bin]);remaining -= removed
            }
            return max(0,total)/Double(retained)
        }
        let scores = (1...maxShift).map { ($0,score($0)) }
        guard let best = scores.min(by:{$0.1 < $1.1}), best.1 < 3 else { return .unmatched }
        let alternative = scores.filter {abs($0.0-best.0)>max(4,h/100)}.map(\.1).min() ?? 255
        guard alternative > best.1+1.5 else { return .unmatched }
        let shift = best.0
        let height = image.height + shift
        guard Self.fitsLimits(width:w,height:height,maxHeight:maxHeight,maxPixels:maxPixels) else { return .limit }
        guard let old = image.cropping(to: CGRect(x:0,y:0,width:w,height:image.height-footer)),
              let strip = current.cropping(to: CGRect(x:0,y:bottom-shift,width:w,height:shift+footer)),
              let context = CGContext(data:nil,width:w,height:height,bitsPerComponent:8,bytesPerRow:w*4,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return .invalid }
        context.draw(old,in:CGRect(x:0,y:shift+footer,width:w,height:old.height))
        context.draw(strip,in:CGRect(x:0,y:0,width:w,height:strip.height))
        guard let result = context.makeImage() else { return .invalid }
        image = result; previous = current
        return .appended(shift)
    }
}
