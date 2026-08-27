#!/usr/bin/env swift

// Draws the Rondo mark and writes the app icon at every size Xcode asks for.
//
// The mark is code rather than an SVG because rendering an SVG faithfully
// needs a library that is not in the dev shell, while Core Graphics is on
// every machine that can build this app at all. The output is committed;
// this script exists so the icon can be changed rather than redrawn.
//
// Usage: scripts/make-app-icon.swift <output-directory>

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - The mark

/// A colour written the way the Sonatelle brand files write them.
func srgb(_ hex: UInt32) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: 1
  )
}

/// The palette.
///
/// Deliberately not the organization's amber and rose. Rondo needs to be
/// picked out of a Dock at a glance, and a warm neutral is the easiest
/// thing in the world to lose among other warm neutrals; the family
/// resemblance is carried by the shape language instead.
enum Palette {
  static let groundTop = srgb(0xF7F4FF)
  static let groundBottom = srgb(0xE9E3FA)
  /// The three stops the ring travels through, light to deep.
  static let sweepStops: [(r: Double, g: Double, b: Double)] = [
    (0x8B / 255, 0x7B / 255, 0xF0 / 255),
    (0x6C / 255, 0x4F / 255, 0xE0 / 255),
    (0x46 / 255, 0x28 / 255, 0xAE / 255),
  ]

  static let card = srgb(0x361E82)
  static let cardDetail = srgb(0xB9A8FF)

  /// The colour of the sweep a fraction of the way along it.
  static func sweep(at position: Double) -> CGColor {
    let scaled = position * Double(sweepStops.count - 1)
    let index = min(Int(scaled), sweepStops.count - 2)
    let blend = scaled - Double(index)
    let from = sweepStops[index]
    let to = sweepStops[index + 1]
    return CGColor(
      srgbRed: from.r + (to.r - from.r) * blend,
      green: from.g + (to.g - from.g) * blend,
      blue: from.b + (to.b - from.b) * blend,
      alpha: 1
    )
  }
}

/// How the ring is drawn, in degrees.
///
/// A rondo is a theme that keeps returning, so the mark is one sweep that
/// deepens as it travels and arrives back where it began - an arrowhead at
/// the end says it is going somewhere rather than sitting still. Dividing
/// the ring into the five sections of an ABACA would be more literal, but
/// at sixteen pixels five sections are five loose strokes rather than a
/// ring, and two of them would have to be pale enough to read as missing.
///
/// All angles are measured counterclockwise from three o'clock, and the
/// sweep runs clockwise, so the numbers below decrease as it travels.
enum Ring {
  static let radius = 285.0
  static let stroke = 126.0

  static let start = 55.0
  /// Where the arrowhead's base sits, and so where the stroke stops. The
  /// two meet flush: both are radial lines at this angle, and the head is
  /// the wider of the two.
  static let base = 128.0
  static var sweep: Double { start - base + 360 }

  /// The arrowhead, along the direction of travel and across it. About as
  /// long as it is broad, and broader than the stroke, or it does not read
  /// as a head.
  static let arrowLength = 175.0
  static let arrowReach = 84.0

  /// Core Graphics offers linear and radial gradients but not one that
  /// travels around a circle, so the sweep is laid down in small steps and
  /// the colour interpolated across them.
  static let steps = 720

  /// How far each step reaches past the next one's start. Butted exactly
  /// end to end, the antialiased edges leave a hairline between every pair
  /// and the ring moires; overlapping hides the seam.
  static let stepOverlap = 0.6
}

/// Draws the card that sits in the ring's hole.
///
/// A subscription is a charge that comes back, so what the ring returns to
/// is the thing being charged. It is a card and not a currency symbol on
/// purpose: Rondo holds several currencies at once and never converts
/// between them, so putting one currency's glyph at the centre of the mark
/// would claim something the app does not do.
func drawCard(in context: CGContext, centre: CGPoint, unit: CGFloat) {
  let width = 244 * unit
  let height = 168 * unit
  let body = CGRect(
    x: centre.x - width / 2,
    y: centre.y - height / 2,
    width: width,
    height: height
  )
  let card = CGPath(
    roundedRect: body,
    cornerWidth: 34 * unit,
    cornerHeight: 34 * unit,
    transform: nil
  )

  context.saveGState()
  context.addPath(card)
  context.setFillColor(Palette.card)
  context.fillPath()

  // Solid rather than outlined. An outline would match the menu bar's
  // `creditcard` symbol stroke for stroke, but a mark this small carries
  // one shape better than three thin ones, and the outline closed up into
  // a smudge below about forty pixels.
  context.addPath(card)
  context.clip()
  context.setFillColor(Palette.cardDetail)

  // The band a card carries across its width.
  context.fill(
    CGRect(
      x: body.minX,
      y: centre.y + 34 * unit,
      width: width,
      height: 26 * unit
    )
  )

  // The chip, low and to the left. This is what makes the shape a bank
  // card rather than any other rounded rectangle.
  context.addPath(
    CGPath(
      roundedRect: CGRect(
        x: centre.x - 84 * unit,
        y: centre.y - 50 * unit,
        width: 44 * unit,
        height: 36 * unit
      ),
      cornerWidth: 9 * unit,
      cornerHeight: 9 * unit,
      transform: nil
    )
  )
  context.fillPath()
  context.restoreGState()
}

/// Draws the mark filling a square canvas of `side` points.
func drawMark(in context: CGContext, side: CGFloat) {
  let unit = side / 1024

  // macOS gives an app icon its own rounded shape inside the canvas rather
  // than letting artwork run to the edge; the margin is what the system
  // expects to see and what keeps the mark from touching its neighbours in
  // the Dock.
  let inset = 100 * unit
  let plate = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
  let corner = plate.width * 0.2237
  let shape = CGPath(
    roundedRect: plate,
    cornerWidth: corner,
    cornerHeight: corner,
    transform: nil
  )

  context.saveGState()
  context.addPath(shape)
  context.clip()
  let ground = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [Palette.groundTop, Palette.groundBottom] as CFArray,
    locations: [0, 1]
  )!
  context.drawLinearGradient(
    ground,
    start: CGPoint(x: plate.minX, y: plate.maxY),
    end: CGPoint(x: plate.maxX, y: plate.minY),
    options: []
  )
  context.restoreGState()

  let centre = CGPoint(x: side / 2, y: side / 2)
  let radius = Ring.radius * unit
  let stroke = Ring.stroke * unit

  /// A point on the ring, given an angle in degrees and a distance from
  /// the centre.
  func point(at degrees: Double, from distance: CGFloat) -> CGPoint {
    let radians = degrees * .pi / 180
    return CGPoint(
      x: centre.x + cos(radians) * distance,
      y: centre.y + sin(radians) * distance
    )
  }

  // Butt caps, so the stroke stops exactly where the arrowhead begins. A
  // round cap would reach a stroke's width past that and swallow the head.
  context.setLineWidth(stroke)
  context.setLineCap(.butt)

  for step in 0 ..< Ring.steps {
    let from = Double(step) / Double(Ring.steps)
    let to = Double(step + 1) / Double(Ring.steps)
    context.setStrokeColor(Palette.sweep(at: from))
    context.addArc(
      center: centre,
      radius: radius,
      startAngle: (Ring.start - Ring.sweep * from) * .pi / 180,
      endAngle: (Ring.start - Ring.sweep * to - Ring.stepOverlap) * .pi / 180,
      clockwise: true
    )
    context.strokePath()
  }

  // The arrowhead, carrying the colour the sweep ended on.
  //
  // The base is a radius, matching the square end the stroke leaves, and
  // the tip runs forward from it along the tangent there. That puts the
  // tip a little outside the ring's centre line, which is what a head on a
  // curve looks like. Laying the whole triangle on the circle instead -
  // tip and base both on it - flattens the head against the arc until it
  // reads as a flag rather than as a point.
  let heading = Ring.base * .pi / 180
  let anchor = point(at: Ring.base, from: radius)
  let apex = CGPoint(
    x: anchor.x + sin(heading) * Ring.arrowLength * unit,
    y: anchor.y - cos(heading) * Ring.arrowLength * unit
  )

  context.setFillColor(Palette.sweep(at: 1))
  context.move(to: apex)
  context.addLine(to: point(at: Ring.base, from: radius + Ring.arrowReach * unit))
  context.addLine(to: point(at: Ring.base, from: radius - Ring.arrowReach * unit))
  context.closePath()
  context.fillPath()

  drawCard(in: context, centre: centre, unit: unit)
}

// MARK: - Writing the files

/// Renders the mark at one pixel size.
func render(side: Int) -> CGImage {
  let context = CGContext(
    data: nil,
    width: side,
    height: side,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.setAllowsAntialiasing(true)
  context.interpolationQuality = .high
  drawMark(in: context, side: CGFloat(side))
  return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) throws {
  guard
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL,
      UTType.png.identifier as CFString,
      1,
      nil
    )
  else {
    throw CocoaError(.fileWriteUnknown)
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw CocoaError(.fileWriteUnknown)
  }
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
  FileHandle.standardError.write(
    Data("usage: make-app-icon.swift <output-directory>\n".utf8)
  )
  exit(2)
}
let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)

// Every pixel size a macOS app icon is asked for. The catalogue names them
// as ten entries, but several are the same pixels under two names.
let sizes = [16, 32, 64, 128, 256, 512, 1024]
for side in sizes {
  let url = outputDirectory.appendingPathComponent("icon-\(side).png")
  try write(render(side: side), to: url)
  print("wrote \(url.lastPathComponent)")
}
