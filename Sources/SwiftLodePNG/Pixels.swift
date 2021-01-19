/*
SwiftLodePNG version 20201017

Copyright (c) 2020 TellowKrinkle

This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
claim that you wrote the original software. If you use this software
in a product, an acknowledgment in the product documentation would be
appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be
misrepresented as being the original software.

3. This notice may not be removed or altered from any source
distribution.
*/

import CLodePNG

public protocol LodePNGPixel {
	static var bitDepth: UInt32 { get }
	static var enumValue: LodePNGColorType { get }
	static var bpp: Int { get }
	init(from buffer: UnsafeRawBufferPointer, index: Int)
	func store(to buffer: UnsafeMutableRawBufferPointer, index: Int)
}

public protocol LodePNGNormalSupportedColor {
	var bigEndian: Self { get }
	init(bigEndian: Self)
}

extension UInt8: LodePNGNormalSupportedColor {}
extension UInt16: LodePNGNormalSupportedColor {}

/// A pixel storing three colors and an alpha channel
public struct LodePNGRGBA<Value: LodePNGNormalSupportedColor>: LodePNGPixel {
	@inlinable public static var bitDepth: UInt32 { return UInt32(MemoryLayout<Value>.size * 8) }
	@inlinable public static var enumValue: LodePNGColorType { return .LCT_RGBA }
	@inlinable public static var bpp: Int { return Int(bitDepth) * 4 }

	@usableFromInline var values: (Value, Value, Value, Value)

	@inlinable public var r: Value { get { return .init(bigEndian: values.0) } set { values.0 = newValue.bigEndian } }
	@inlinable public var g: Value { get { return .init(bigEndian: values.1) } set { values.1 = newValue.bigEndian } }
	@inlinable public var b: Value { get { return .init(bigEndian: values.2) } set { values.2 = newValue.bigEndian } }
	@inlinable public var a: Value { get { return .init(bigEndian: values.3) } set { values.3 = newValue.bigEndian } }

	@inlinable public init(r: Value, g: Value, b: Value, a: Value) {
		values = (r.bigEndian, g.bigEndian, b.bigEndian, a.bigEndian)
	}

	@inlinable public init(from buffer: UnsafeRawBufferPointer, index: Int) {
		values = buffer.bindMemory(to: (Value, Value, Value, Value).self)[index]
	}
	@inlinable public func store(to buffer: UnsafeMutableRawBufferPointer, index: Int) {
		buffer.bindMemory(to: (Value, Value, Value, Value).self)[index] = values
	}
}

/// A pixel storing three colors
public struct LodePNGRGB<Value: LodePNGNormalSupportedColor>: LodePNGPixel {
	@inlinable public static var bitDepth: UInt32 { return UInt32(MemoryLayout<Value>.size * 8) }
	@inlinable public static var enumValue: LodePNGColorType { return .LCT_RGB }
	@inlinable public static var bpp: Int { return Int(bitDepth) * 3 }

	@usableFromInline var values: (Value, Value, Value)

	@inlinable public var r: Value { get { return .init(bigEndian: values.0) } set { values.0 = newValue.bigEndian } }
	@inlinable public var g: Value { get { return .init(bigEndian: values.1) } set { values.1 = newValue.bigEndian } }
	@inlinable public var b: Value { get { return .init(bigEndian: values.2) } set { values.2 = newValue.bigEndian } }

	@inlinable public init(r: Value, g: Value, b: Value) {
		values = (r.bigEndian, g.bigEndian, b.bigEndian)
	}

	@inlinable public init(from buffer: UnsafeRawBufferPointer, index: Int) {
		let tmp = buffer.bindMemory(to: (Value, Value, Value).self)[index]
		values = (.init(bigEndian: tmp.0), .init(bigEndian: tmp.1), .init(bigEndian: tmp.2))
	}
	@inlinable public func store(to buffer: UnsafeMutableRawBufferPointer, index: Int) {
		buffer.bindMemory(to: (Value, Value, Value).self)[index] = (values.0.bigEndian, values.1.bigEndian, values.2.bigEndian)
	}
}



/// A pixel storing one color and one alpha
public struct LodePNGGrayAlpha<Value: LodePNGNormalSupportedColor>: LodePNGPixel {
	@inlinable public static var bitDepth: UInt32 { return UInt32(MemoryLayout<Value>.size * 8) }
	@inlinable public static var enumValue: LodePNGColorType { return .LCT_GREY_ALPHA }
	@inlinable public static var bpp: Int { return Int(bitDepth) * 2 }

	@usableFromInline var values: (Value, Value)

	@inlinable public var g: Value { get { return .init(bigEndian: values.0) } set { values.0 = newValue.bigEndian } }
	@inlinable public var a: Value { get { return .init(bigEndian: values.1) } set { values.1 = newValue.bigEndian } }

	@inlinable public init(g: Value, a: Value) {
		values = (g.bigEndian, a.bigEndian)
	}

	@inlinable public init(from buffer: UnsafeRawBufferPointer, index: Int) {
		let tmp = buffer.bindMemory(to: (Value, Value).self)[index]
		values = (.init(bigEndian: tmp.0), .init(bigEndian: tmp.1))
	}
	@inlinable public func store(to buffer: UnsafeMutableRawBufferPointer, index: Int) {
		buffer.bindMemory(to: (Value, Value).self)[index] = (values.0.bigEndian, values.1.bigEndian)
	}
}

/// A pixel storing one color value
public struct LodePNGGrayscale<Value: LodePNGNormalSupportedColor>: LodePNGPixel {
	@inlinable public static var bitDepth: UInt32 { return UInt32(MemoryLayout<Value>.size * 8) }
	@inlinable public static var enumValue: LodePNGColorType { return .LCT_GREY }
	@inlinable public static var bpp: Int { return Int(bitDepth) }

	@usableFromInline var value: Value

	@inlinable public var g: Value { get { return .init(bigEndian: value) } set { value = newValue.bigEndian } }

	@inlinable public init(g: Value) {
		value = g.bigEndian
	}

	@inlinable public init(from buffer: UnsafeRawBufferPointer, index: Int) {
		value = buffer.bindMemory(to: Value.self)[index]
	}
	@inlinable public func store(to buffer: UnsafeMutableRawBufferPointer, index: Int) {
		buffer.bindMemory(to: Value.self)[index] = value
	}
}

public protocol LodePNGSmallColor {
	static var log2bits: Int { get }
}
extension LodePNGSmallColor {
	@inlinable public static var bits: UInt32 { return 1 << log2bits }
}

public enum LodePNGOneBitColor: LodePNGSmallColor {
	@inlinable public static var log2bits: Int { 0 }
}
public enum LodePNGTwoBitColor: LodePNGSmallColor {
	@inlinable public static var log2bits: Int { 1 }
}
public enum LodePNGFourBitColor: LodePNGSmallColor {
	@inlinable public static var log2bits: Int { 2 }
}

/// Grayscale pixel with size less than one byte
public struct LodePNGSmallGrayscale<Value: LodePNGSmallColor>: LodePNGPixel {
	@inlinable public static var bitDepth: UInt32 { return Value.bits }
	@inlinable public static var enumValue: LodePNGColorType { return .LCT_GREY }
	@inlinable public static var bpp: Int { return Int(bitDepth) }

	public var g: UInt8

	@inlinable static func actualIndex(_ index: Int) -> Int { index >> (3 - Value.log2bits) }
	@inlinable static func shiftAmount(_ index: Int) -> Int { index & (7 >> Value.log2bits) }
	@inlinable static var mask: UInt8 { 0xFF >> (8 - UInt8(Value.bits)) }

	@inlinable public init(g: UInt8) {
		self.g = g & Self.mask
	}

	@inlinable public init(from buffer: UnsafeRawBufferPointer, index: Int) {
		g = (buffer[Self.actualIndex(index)] >> Self.shiftAmount(index)) & Self.mask
	}

	@inlinable public func store(to buffer: UnsafeMutableRawBufferPointer, index: Int) {
		let smask = Self.mask << Self.shiftAmount(index)
		let toWrite = g << Self.shiftAmount(index)
		buffer[Self.actualIndex(index)] &= ~smask
		buffer[Self.actualIndex(index)] |= toWrite
	}
}

