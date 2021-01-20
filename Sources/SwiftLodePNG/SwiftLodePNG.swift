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
import Foundation

var lodePNGVersion: String { return String(cString: LODEPNG_VERSION_STRING) }

public struct LodePNGImage<Color: LodePNGPixel> {
	/// An error from LodePNG
	public struct Error: LocalizedError {
		public var code: UInt32

		public var errorDescription: String {
			return String(cString: lodepng_error_text(code))
		}
	}

	static private func throwIfError(_ code: UInt32) throws {
		if code != 0 {
			throw Error(code: code)
		}
	}

	public struct UnsafeMutableBuffer {
		@usableFromInline var raw: UnsafeMutableRawPointer?
		@usableFromInline let width: UInt32
		@usableFromInline let height: UInt32

		@inlinable func checkSize() {
			// Overflow check now so we don't have to later
			precondition((Int(width) * Int(height) * Color.bpp + 7) / 8 == size)
		}

		@inlinable func bindBuffer() {
			raw?.bindMemory(to: Color.BufferType.self, capacity: size / MemoryLayout<Color.BufferType>.size)
		}

		/// Bytes in image
		@inlinable var size: Int {
			let bpp = Color.bpp
			if bpp % 8 == 0 {
				return Int(width) &* Int(height) &* (bpp / 8)
			} else {
				return (Int(width) &* Int(height) &* bpp &+ 7) / 8
			}
		}

		/// Raw storage
		@inlinable var buffer: UnsafeMutableRawBufferPointer { return .init(start: raw, count: size) }

		/// Gives mutable access to raw storage
		@inlinable func withUnsafeMutableBytes<Return>(_ execute: (UnsafeMutableRawBufferPointer) throws -> Return) rethrows -> Return {
			defer { bindBuffer() }
			return try execute(.init(buffer))
		}

		/// Gives access to raw storage
		@inlinable func withUnsafeBytes<Return>(_ execute: (UnsafeRawBufferPointer) throws -> Return) rethrows -> Return {
			return try withUnsafeMutableBytes { try execute(.init($0)) }
		}

		@inlinable subscript(unchecked i: Int) -> Color {
			get {
				Color(from: .init(raw!.assumingMemoryBound(to: Color.BufferType.self)), index: i)
			}
			nonmutating set {
				newValue.store(to: raw!.assumingMemoryBound(to: Color.BufferType.self), index: i)
			}
		}

		@inlinable public subscript(x x: Int, y y: Int) -> Color {
			get {
				precondition((0..<Int(width)).contains(x) && (0..<Int(height)).contains(y))
				return self[unchecked: x + y * Int(width)]
			}
			nonmutating set {
				precondition((0..<Int(width)).contains(x) && (0..<Int(height)).contains(y))
				self[unchecked: x + y * Int(width)] = newValue
			}
		}

		@inlinable init(width: UInt32, height: UInt32, raw: UnsafeMutableRawPointer?) {
			(self.width, self.height, self.raw) = (width, height, raw)
		}
	}

	@usableFromInline final class COWHelper {
		@usableFromInline var buffer: UnsafeMutableBuffer

		@inlinable init(width: UInt32, height: UInt32, rawAllocator: (Int) -> UnsafeMutableRawPointer) {
			buffer = .init(width: width, height: height, raw: nil)
			buffer.raw = rawAllocator(buffer.size)
			buffer.bindBuffer()
			buffer.checkSize()
		}

		@usableFromInline convenience init(copying other: UnsafeMutableBuffer) {
			self.init(width: other.width, height: other.height) {
				let ptr = malloc($0)!
				ptr.copyMemory(from: other.raw!, byteCount: $0)
				return ptr
			}
		}

		deinit {
			if let raw = buffer.raw {
				free(raw)
			}
		}
	}

	@usableFromInline var actual: COWHelper

	@inlinable func withBuffer<Return>(_ execute: (UnsafeMutableBuffer) throws -> Return) rethrows -> Return {
		return try withExtendedLifetime(actual) { try execute($0.buffer) }
	}

	/// Gives access to the internal buffer
	/// Note: Not safe to keep the buffer outside of the function
	@inlinable public mutating func withMutableBuffer<Return>(_ execute: (UnsafeMutableBuffer) throws -> Return) rethrows -> Return {
		makeMutable()
		return try withBuffer(execute)
	}

	/// The image width
	@inlinable public var width: Int { return Int(actual.buffer.width) }
	/// The image height
	@inlinable public var height: Int { return Int(actual.buffer.height) }
	/// Bytes per image color value
	@inlinable public var bitDepth: Int { return Int(Color.bitDepth) }
	@inlinable mutating func makeMutable() {
		if !isKnownUniquelyReferenced(&actual) {
			actual = withBuffer { COWHelper(copying: $0) }
		}
	}
	/// Gives mutable access to raw storage
	@inlinable mutating func withUnsafeMutableBytes<Return>(_ execute: (UnsafeMutableRawBufferPointer) throws -> Return) rethrows -> Return {
		return try withMutableBuffer { try $0.withUnsafeMutableBytes(execute) }
	}
	/// Gives access to raw storage
	@inlinable func withUnsafeBytes<Return>(_ execute: (UnsafeRawBufferPointer) throws -> Return) rethrows -> Return {
		return try withBuffer { try $0.withUnsafeBytes(execute) }
	}

	@inlinable public subscript(x x: Int, y y: Int) -> Color {
		get {
			return withBuffer { $0[x: x, y: y] }
		}
		set {
			withMutableBuffer { $0[x: x, y: y] = newValue }
		}
	}

	/// Create a new image with the given dimensions
	public init(width: Int, height: Int, data: [UInt8]) {
		actual = .init(width: UInt32(width), height: UInt32(height)) { size in
			precondition(data.count >= size)
			let tmp = malloc(size)!
			tmp.copyMemory(from: data, byteCount: size)
			return tmp
		}
	}

	/// Create a new image with the given dimensions
	public init(width: Int, height: Int) {
		actual = .init(width: UInt32(width), height: UInt32(height)) { malloc($0) }
	}

	/// Decode the given buffer into a new image
	public init(decoding buffer: UnsafeRawBufferPointer) throws {
		let bound = buffer.bindMemory(to: UInt8.self)
		var tmpRaw: UnsafeMutablePointer<UInt8>? = nil
		var tmpWidth: UInt32 = 0
		var tmpHeight: UInt32 = 0
		try LodePNGImage.throwIfError(lodepng_decode_memory(&tmpRaw, &tmpWidth, &tmpHeight, bound.baseAddress, bound.count, Color.enumValue, Color.bitDepth))
		self.actual = .init(width: tmpWidth, height: tmpHeight) { _ in .init(tmpRaw!) }
	}

	/// Decode the given buffer into a new image
	@inlinable public init(decoding data: Data) throws {
		self = try data.withUnsafeBytes(Self.init(decoding:))
	}

	/// Decode the given buffer into a new image
	@inlinable public init(decoding data: [UInt8]) throws {
		self = try data.withUnsafeBytes(Self.init(decoding:))
	}

	/// Encode the image to an `UnsafeRawBufferPointer` which must be freed using `free()`
	public func encodeToUnsafePointer() throws -> UnsafeMutableRawBufferPointer {
		let width = actual.buffer.width
		let height = actual.buffer.height
		return try withUnsafeBytes { buffer in
			var out: UnsafeMutablePointer<UInt8>? = nil
			var outsize = 0
			let ptr = buffer.baseAddress!.bindMemory(to: UInt8.self, capacity: buffer.count)
			try LodePNGImage.throwIfError(lodepng_encode_memory(&out, &outsize, ptr, width, height, Color.enumValue, Color.bitDepth))
			return UnsafeMutableRawBufferPointer(start: out.map(UnsafeMutableRawPointer.init), count: outsize)
		}
	}

	/// Encode the image to a Foundation `Data`
	public func encode() throws -> Data {
		let ptr = try encodeToUnsafePointer()
		return Data(bytesNoCopy: ptr.baseAddress!, count: ptr.count, deallocator: .free)
	}

	@inlinable init(_ actual: COWHelper) {
		self.actual = actual
	}

	/// Temporarily create an image with the given storage (the image is only valid for the duration of `execute`)
	@inlinable public static func withImage<Result>(
		data: UnsafeRawBufferPointer, width: Int, height: Int,
		_ execute: (LodePNGImage) throws -> Result
	) rethrows -> Result {
		let ptr = UnsafeMutableRawPointer(mutating: data.baseAddress!) // COW will prevent modifications
		let image = COWHelper(width: UInt32(width), height: UInt32(height)) { size in
			precondition(data.count >= size)
			return ptr
		}
		defer { image.buffer.raw = nil }
		return try execute(.init(image))
	}

	/// Temporarily create an image with bytes from the given array (the image is only valid for the duration of `execute`)
	@inlinable public static func withImage<Result>(
		data: [UInt8], width: Int, height: Int,
		_ execute: (LodePNGImage) throws -> Result
	) rethrows -> Result {
		return try data.withUnsafeBytes { try withImage(data: $0, width: width, height: height, execute) }
	}

	/// Take ownership of the image's buffer, destroying it
	@inlinable public mutating func takeOwnershipOfBuffer() -> UnsafeMutableRawBufferPointer {
		makeMutable()
		let out = actual.buffer.buffer
		actual.buffer.raw = nil
		return out
	}
}

extension LodePNGImage.UnsafeMutableBuffer: Equatable {
	@inlinable public static func == (lhs: LodePNGImage.UnsafeMutableBuffer, rhs: LodePNGImage.UnsafeMutableBuffer) -> Bool {
		guard lhs.width == rhs.width && lhs.height == rhs.height else { return false }
		return lhs.withUnsafeBytes { lhsptr in
			return rhs.withUnsafeBytes { rhsptr in
				return memcmp(lhsptr.baseAddress!, rhsptr.baseAddress!, lhsptr.count) == 0
			}
		}
	}
}

extension LodePNGImage: Equatable {
	@inlinable public static func == (lhs: LodePNGImage, rhs: LodePNGImage) -> Bool {
		return lhs.withBuffer { lb in rhs.withBuffer { rb in lb == rb } }
	}
}

extension LodePNGImage.UnsafeMutableBuffer: RandomAccessCollection, MutableCollection {
	public typealias Element = Color

	@inlinable public var startIndex: Int { 0 }

	@inlinable public var endIndex: Int { Int(width) &* Int(height) }

	@inlinable public subscript(position: Int) -> Color {
		get {
			precondition(indices.contains(position))
			return self[unchecked: position]
		}
		nonmutating set {
			precondition(indices.contains(position))
			self[unchecked: position] = newValue
		}
	}
}

extension LodePNGImage: RandomAccessCollection, MutableCollection {
	public typealias Element = Color

	@inlinable public var startIndex: Int { 0 }

	@inlinable public var endIndex: Int { width &* height }

	@inlinable public subscript(position: Int) -> Color {
		get {
			return withBuffer { $0[position] }
		}
		set {
			withMutableBuffer { $0[position] = newValue }
		}
	}
}
