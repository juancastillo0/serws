import 'dart:convert';
import 'dart:typed_data';

import 'package:serws/src/byte_parser.dart';

sealed class WsMessage {
  const WsMessage();

  Map<String, Object?> toJson();
  Uint8List toBytes();

  factory WsMessage.fromMessage(Object? message) {
    if (message is Uint8List) {
      final kind =
          WsMessageKind.values[ByteData.sublistView(message).getUint32(0)];

      final bytes = Uint8List.sublistView(message, 4);
      return switch (kind) {
        WsMessageKind.config => WsConfigMessage.fromBytes(bytes),
        WsMessageKind.http => WsHttpMessage.fromBytes(bytes),
        WsMessageKind.subscription => WsSubscriptionMessage.fromBytes(bytes),
      };
    } else {
      final messageJson = jsonDecode(message as String) as Map<String, Object?>;
      final kind = WsMessageKind.values[messageJson['kind'] as int];
      return switch (kind) {
        WsMessageKind.config => WsConfigMessage.fromJson(messageJson),
        WsMessageKind.http => WsHttpMessage.fromJson(messageJson),
        WsMessageKind.subscription =>
          WsSubscriptionMessage.fromJson(messageJson),
      };
    }
  }
}

enum WsMessageKind {
  config,
  http,
  subscription,
}

class WsConfigMessage extends WsMessage {
  final bool remove;

  WsConfigMessage({required this.remove});

  factory WsConfigMessage.fromJson(Map messageJson) {
    return WsConfigMessage(
      remove: messageJson['remove'] as bool? ?? false,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        if (remove) 'remove': remove,
      };

  static const lastVersion = 0;

  factory WsConfigMessage.fromBytes(Uint8List messageBytes) {
    final parser = ByteParser(ByteData.sublistView(messageBytes));
    final messageVersion = parser.readUint32();

    return switch (messageVersion) {
      lastVersion || _ => switch (parser.readUint32()) {
          0 => WsConfigMessage(remove: false),
          _ => WsConfigMessage(remove: true),
        },
    };
  }

  @override
  Uint8List toBytes() => remove
      ? Uint32List.fromList([lastVersion, 1]).buffer.asUint8List()
      : Uint8List(8 * 2);
}

class WsHttpMessage extends WsMessage {
  final int id;
  final int statusCode;
  final Map<String, List<String>>? headers;
  final Object? body;

  WsHttpMessage({
    required this.id,
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  factory WsHttpMessage.fromJson(Map messageJson) => WsHttpMessage(
        id: messageJson['id'] as int,
        statusCode: messageJson['statusCode'] as int,
        headers: (messageJson['headers'] as Map?)?.cast(),
        body: messageJson['body'] as String?,
      );

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'statusCode': statusCode,
        if (headers != null) 'headers': headers,
        if (body != null) 'body': body,
      };

  static const lastVersion = 0;

  factory WsHttpMessage.fromBytes(Uint8List messageBytes) {
    final parser = ByteParser(ByteData.sublistView(messageBytes));
    final messageVersion = parser.readUint32();

    return switch (messageVersion) {
      lastVersion || _ => WsHttpMessage(
          id: parser.readUint32(),
          statusCode: parser.readUint32(),
          headers: parser.readMap(
            parser.readUtf8String,
            () => parser.readList(parser.readUtf8String),
          ),
          body: parser.parsePayload(messageBytes),
        ),
    };
  }

  @override
  Uint8List toBytes() {
    final builder = ByteBuilder();
    builder.writeUint32List([lastVersion, id, statusCode]);
    builder.writeHeaders(headers);
    builder.writePayload(body);
    return builder.takeBytes();
  }
}

class WsSubscriptionMessage extends WsMessage {
  final int wsId;
  final int? closeCode;
  final String? closeReason;
  final Object? message;

  WsSubscriptionMessage({
    required this.wsId,
    required this.closeCode,
    required this.closeReason,
    required this.message,
  });

  factory WsSubscriptionMessage.fromJson(Map messageJson) {
    return WsSubscriptionMessage(
      wsId: messageJson['wsId'] as int,
      closeCode: messageJson['closeCode'] as int?,
      closeReason: messageJson['closeReason'] as String?,
      message: messageJson['message'] as String?,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        'wsId': wsId,
        if (closeCode != null) 'closeCode': closeCode,
        if (closeReason != null) 'closeReason': closeReason,
        if (message != null) 'message': message,
      };

  static const lastVersion = 0;

  factory WsSubscriptionMessage.fromBytes(Uint8List messageBytes) {
    final parser = ByteParser(ByteData.sublistView(messageBytes));
    final messageVersion = parser.readUint32();

    return switch (messageVersion) {
      lastVersion || _ => WsSubscriptionMessage(
          wsId: parser.readUint32(),
          closeCode: parser.readUint32(),
          closeReason: parser.readUtf8String(),
          message: parser.parsePayload(messageBytes),
        ),
    };
  }

  @override
  Uint8List toBytes() {
    final builder = ByteBuilder();
    builder.writeUint32List([lastVersion, wsId, closeCode ?? 0]);
    builder.writeUtf8(closeReason ?? '');
    builder.writePayload(message);
    return builder.takeBytes();
  }
}
