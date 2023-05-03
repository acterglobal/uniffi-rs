// Struct comes from dart:ffi
class RustBuffer extends Struct {
    @Int32()
    external int capacity;

    @Int32()
    external int len;

    external Pointer data;

    static RustBuffer fromBytes(Api api, Pointer<ForeignBytes> bytes) {
        final _fromBytesPtr = api._lookup<
        NativeFunction<
            Void Function(Pointer<ForeignBytes>, Pointer<RustCallStatus>)>>("{{ ci.ffi_rustbuffer_from_bytes().name() }}");
        final fromBytes =
        _fromBytesPtr.asFunction<void Function(Pointer<ForeignBytes>, Pointer<RustCallStatus>)>();
        return rustCall(api, (res) => fromBytes(bytes, res));
    }

    void deallocate(Api api) {
        final _freePtr = api._lookup<
        NativeFunction<
            Void Function(RustBuffer, Pointer<RustCallStatus>)>>("{{ ci.ffi_rustbuffer_free().name() }}");
        final free = _freePtr.asFunction<void Function(RustBuffer, Pointer<RustCallStatus>)>();
        rustCall(api, (res) => free(this, res));
    }

    Uint8List asByteBuffer() {
        List<int> buf = [];
        for (int i = 0; i < len; i++) {
            int char = data.cast<Uint8>().elementAt(i).value;
            buf.add(char);
        }
        return Uint8List.fromList(buf);
    }

    @override
    String toString() {
        String res = "RustBuffer { capacity: $capacity, len: $len, data: $data }";
        for (int i = 0; i < len; i++) {
            int char = data.cast<Uint8>().elementAt(i).value;
            res += String.fromCharCode(char);
        }
        return res;
    }
}

class ForeignBytes extends Struct {
    @Int32()
    external int len;

    external Pointer data;

    static Pointer<ForeignBytes> allocate({int count = 1}) =>
        calloc<ForeignBytes>(count * sizeOf<ForeignBytes>());
}

{# comment

class RustType {
    late final Api _api;
    late final RustBuffer _inner;

    RustType._(this._api, this._inner);
    
    late final _freePtr = _api._lookup<
        NativeFunction<
            Void Function(RustBuffer, Pointer<RustCallStatus>)>>("{{ ci.ffi_rustbuffer_free().name() }}"); 
    late final _free = _freePtr.asFunction<void Function(RustBuffer, Pointer<RustCallStatus>)>();

    late final _allocPtr = _api._lookup<
        NativeFunction<
            Void Function(Int32, Pointer<RustCallStatus>)>>("{{ ci.ffi_rustbuffer_alloc().name() }}"); 
    late final _alloc = _allocPtr.asFunction<void Function(Int32, Pointer<RustCallStatus>)>();

    late final _fromBytesPtr = _api._lookup<
        NativeFunction<
            Void Function(Int32, Pointer<RustCallStatus>)>>("{{ ci.ffi_rustbuffer_from_bytes().name() }}"); 
    late final _fromBytes = _allocPtr.asFunction<void Function(Int32, Pointer<RustCallStatus>)>();

    // Frees the buffer in place.
    // The buffer must not be used after this is called.
    void drop() {
        _free(_inner);
    }

    static Pointer<RustBuffer> allocate(Api api) {
        buf = _alloc();
    }

    static RustType from(Api api, int ptr) {
        RustType._(api, Pointer<RustBuffer>.fromAddress(ptr).ref);
    }
}

fileprivate extension RustBuffer {
    // Allocate a new buffer, copying the contents of a `UInt8` array.
    init(bytes: [UInt8]) {
        let rbuf = bytes.withUnsafeBufferPointer { ptr in
            RustBuffer.from(ptr)
        }
        self.init(capacity: rbuf.capacity, len: rbuf.len, data: rbuf.data)
    }


    // Frees the buffer in place.
    // The buffer must not be used after this is called.
    func deallocate() {
        try! rustCall { {{ ci.ffi_rustbuffer_free().name() }}(self, $0) }
    }
}

fileprivate extension ForeignBytes {
    init(bufferPointer: UnsafeBufferPointer<UInt8>) {
        self.init(len: Int32(bufferPointer.count), data: bufferPointer.baseAddress)
    }
}

// For every type used in the interface, we provide helper methods for conveniently
// lifting and lowering that type from C-compatible data, and for reading and writing
// values of that type in a buffer.

// Helper classes/extensions that don't change.
// Someday, this will be in a library of its own.

fileprivate extension Data {
    init(rustBuffer: RustBuffer) {
        // TODO: This copies the buffer. Can we read directly from a
        // Rust buffer?
        self.init(bytes: rustBuffer.data!, count: Int(rustBuffer.len))
    }
}

// Define reader functionality.  Normally this would be defined in a class or
// struct, but we use standalone functions instead in order to make external
// types work.
//
// With external types, one dart source file needs to be able to call the read
// method on another source file's FfiConverter, but then what visibility
// should Reader have?
// - If Reader is fileprivate, then this means the read() must also
//   be fileprivate, which doesn't work with external types.
// - If Reader is internal/public, we'll get compile errors since both source
//   files will try define the same type.
//
// Instead, the read() method and these helper functions input a tuple of data

fileprivate func createReader(data: Data) -> (data: Data, offset: Data.Index) {
    (data: data, offset: 0)
}

// Reads an integer at the current offset, in big-endian order, and advances
// the offset on success. Throws if reading the integer would move the
// offset past the end of the buffer.
fileprivate func readInt<T: FixedWidthInteger>(_ reader: inout (data: Data, offset: Data.Index)) throws -> T {
    let range = reader.offset..<reader.offset + MemoryLayout<T>.size
    guard reader.data.count >= range.upperBound else {
        throw UniffiInternalError.bufferOverflow
    }
    if T.self == UInt8.self {
        let value = reader.data[reader.offset]
        reader.offset += 1
        return value as! T
    }
    var value: T = 0
    let _ = withUnsafeMutableBytes(of: &value, { reader.data.copyBytes(to: $0, from: range)})
    reader.offset = range.upperBound
    return value.bigEndian
}

// Reads an arbitrary number of bytes, to be used to read
// raw bytes, this is useful when lifting strings
fileprivate func readBytes(_ reader: inout (data: Data, offset: Data.Index), count: Int) throws -> Array<UInt8> {
    let range = reader.offset..<(reader.offset+count)
    guard reader.data.count >= range.upperBound else {
        throw UniffiInternalError.bufferOverflow
    }
    var value = [UInt8](repeating: 0, count: count)
    value.withUnsafeMutableBufferPointer({ buffer in
        reader.data.copyBytes(to: buffer, from: range)
    })
    reader.offset = range.upperBound
    return value
}

// Reads a float at the current offset.
fileprivate func readFloat(_ reader: inout (data: Data, offset: Data.Index)) throws -> Float {
    return Float(bitPattern: try readInt(&reader))
}

// Reads a float at the current offset.
fileprivate func readDouble(_ reader: inout (data: Data, offset: Data.Index)) throws -> Double {
    return Double(bitPattern: try readInt(&reader))
}

// Indicates if the offset has reached the end of the buffer.
fileprivate func hasRemaining(_ reader: (data: Data, offset: Data.Index)) -> Bool {
    return reader.offset < reader.data.count
}

// Define writer functionality.  Normally this would be defined in a class or
// struct, but we use standalone functions instead in order to make external
// types work.  See the above discussion on Readers for details.

fileprivate func createWriter() -> [UInt8] {
    return []
}

fileprivate func writeBytes<S>(_ writer: inout [UInt8], _ byteArr: S) where S: Sequence, S.Element == UInt8 {
    writer.append(contentsOf: byteArr)
}

// Writes an integer in big-endian order.
//
// Warning: make sure what you are trying to write
// is in the correct type!
fileprivate func writeInt<T: FixedWidthInteger>(_ writer: inout [UInt8], _ value: T) {
    var value = value.bigEndian
    withUnsafeBytes(of: &value) { writer.append(contentsOf: $0) }
}

fileprivate func writeFloat(_ writer: inout [UInt8], _ value: Float) {
    writeInt(&writer, value.bitPattern)
}

fileprivate func writeDouble(_ writer: inout [UInt8], _ value: Double) {
    writeInt(&writer, value.bitPattern)
}

// Protocol for types that transfer other types across the FFI. This is
// analogous go the Rust trait of the same name.
fileprivate protocol FfiConverter {
    associatedtype FfiType
    associatedtype DartType

    static func lift(_ value: FfiType) throws -> DartType
    static func lower(_ value: DartType) -> FfiType
    static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> DartType
    static func write(_ value: DartType, into buf: inout [UInt8])
}

// Types conforming to `Primitive` pass themselves directly over the FFI.
fileprivate protocol FfiConverterPrimitive: FfiConverter where FfiType == DartType { }

extension FfiConverterPrimitive {
    public static func lift(_ value: FfiType) throws -> DartType {
        return value
    }

    public static func lower(_ value: DartType) -> FfiType {
        return value
    }
}

// Types conforming to `FfiConverterRustBuffer` lift and lower into a `RustBuffer`.
// Used for complex types where it's hard to write a custom lift/lower.
class FfiConverterRustBuffer {
    static DartType lift<DartType>(RustBuffer buf) {
        val byteBuf = buf.asByteBuffer();
        let value = try read<DartType>(byteBuf);
        if hasRemaining(reader) {
            throw UniffiInternalError.incompleteData;
        }
        buf.deallocate();
        return value;
    }

    static RustBuffer lower<DartType>(DartType value) {
        var writer = createWriter();
        write<DartType>(value, into: &writer);
        return RustBuffer(bytes: writer);
    }
}

#}