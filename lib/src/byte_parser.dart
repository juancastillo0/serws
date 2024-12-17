import 'dart:convert';
import 'dart:typed_data';

class ByteParser {
  final ByteData byteData;
  int byteOffset;

  ByteParser(this.byteData, {this.byteOffset = 0});

  bool readBool() => readUint32() != 0;
  int readUint32() => byteData.getUint32(byteOffset += 4);

  String readUtf8String() {
    final length = readUint32();
    if (length == 0) return '';
    return utf8.decode(Uint8List.sublistView(
      byteData,
      byteOffset += length,
      byteOffset,
    ));
  }

  Map<K, V> readMap<K, V>(K Function() parseKey, V Function() parseValue) {
    final length = readUint32();
    return Map.fromEntries(
      Iterable.generate(
        length,
        (_) => MapEntry(parseKey(), parseValue()),
      ),
    );
  }

  List<V> readList<V>(V Function() parseValue) {
    final length = readUint32();
    return List.generate(length, (_) => parseValue());
  }

  Object? parsePayload(Uint8List messageBytes) {
    return switch (readUint32()) {
      1 => Uint8List.sublistView(messageBytes, byteOffset),
      2 => readUtf8String(),
      _ => null,
    };
  }
}

class ByteBuilder {
  final BytesBuilder builder;

  ByteBuilder({BytesBuilder? builder})
      : builder = builder ?? BytesBuilder(copy: false);

  Uint8List takeBytes() => builder.takeBytes();

  void writeUint32List(List<int> list) {
    builder.add(Uint32List.fromList(list).buffer.asUint8List());
  }

  void writeUint32(int value) {
    builder.add((Uint32List(1)..[0] = value).buffer.asUint8List());
  }

  void writeBool(bool value) {
    writeUint32(value ? 1 : 0);
  }

  void writeUtf8(String? str) {
    if (str == null) {
      builder.add(Uint8List(4));
      return;
    }
    final bytes = utf8.encode(str);
    writeUint32(bytes.length);
    builder.add(bytes);
  }

  void writeHeaders(Map<String, List<String>>? headers) {
    writeUint32(headers?.length ?? 0);
    headers?.forEach((k, v) {
      writeUtf8(k);

      writeUint32(v.length);
      v.forEach(writeUtf8);
    });
  }

  void writePayload(Object? payload) {
    switch (payload) {
      case TypedData payload:
        writeUint32(1);
        builder.add(Uint8List.sublistView(payload));
      case String payload:
        writeUint32(2);
        writeUtf8(payload);
      case null:
        builder.add(Uint8List(4));
      default:
        throw Error();
    }
  }

  // switch (message) {
  //   case TypedData d:
  //     builder.add((Uint32List(1)..[0] = 1).buffer.asUint8List());
  //     builder.add(d.buffer.asUint8List(d.offsetInBytes));
  //   case String str:
  //     builder.add(
  //       (Uint32List(2)
  //             ..[0] = 2
  //             ..[1] = str.length)
  //           .buffer
  //           .asUint8List(),
  //     );
  //     builder.add(utf8.encode(str));
  //   default:
  //     builder.add(Uint8List(4));
  // }

  void add2(Uint8List bytes) {
    builder.add(bytes);
  }
}
