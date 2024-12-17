import 'dart:convert';
import 'dart:typed_data';

import 'package:serws/src/byte_parser.dart';

sealed class WsServerMessage {
  const WsServerMessage();

  Map<String, Object?> toJson();
  Uint8List toBytes();

  factory WsServerMessage.fromMessage(Object? message) {
    if (message is Uint8List) {
      // TODO: pass kind
      final kind = WsServerMessageKind
          .values[ByteData.sublistView(message).getUint32(0)];

      final bytes = Uint8List.sublistView(message, 4);
      return switch (kind) {
        WsServerMessageKind.config => WsServerConfigMessage.fromBytes(bytes),
        WsServerMessageKind.http => WsServerHttpMessage.fromBytes(bytes),
        WsServerMessageKind.subscription =>
          WsServerSubscriptionMessage.fromBytes(bytes),
      };
    } else {
      final messageJson = jsonDecode(message as String) as Map<String, Object?>;
      // TODO: pass kind
      final kind = WsServerMessageKind.values[messageJson['kind'] as int];
      return switch (kind) {
        WsServerMessageKind.config =>
          WsServerConfigMessage.fromJson(messageJson),
        WsServerMessageKind.http => WsServerHttpMessage.fromJson(messageJson),
        WsServerMessageKind.subscription =>
          WsServerSubscriptionMessage.fromJson(messageJson),
      };
    }
  }
}

enum WsServerMessageKind {
  config,
  http,
  subscription,
}

class WsServerConfigMessage extends WsServerMessage {
  final String? subprotocol;

  WsServerConfigMessage({required this.subprotocol});

  factory WsServerConfigMessage.fromJson(Map messageJson) {
    return WsServerConfigMessage(
      subprotocol: messageJson['subprotocol'] as String?,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        if (subprotocol != null) 'subprotocol': subprotocol,
      };

  static const lastVersion = 0;

  factory WsServerConfigMessage.fromBytes(Uint8List messageBytes) {
    final parser = ByteParser(ByteData.sublistView(messageBytes));
    final messageVersion = parser.readUint32();

    return switch (messageVersion) {
      lastVersion || _ => WsServerConfigMessage(
          subprotocol: parser.readUtf8String(),
        )
    };
  }

  @override
  Uint8List toBytes() {
    final builder = ByteBuilder();
    builder.writeUint32(lastVersion);
    builder.writeUtf8(subprotocol);
    return builder.takeBytes();
  }
}

enum HttpMethod {
  OPTIONS,
  GET,
  HEAD,
  POST,
  PUT,
  DELETE,
  TRACE,
  CONNECT,
  PATCH,
}

class WsServerHttpMessage extends WsServerMessage {
  final int id;
  final HttpMethod method;
  final String url;
  final String protocolVersion;
  final Map<String, List<String>> headers;
  final bool finished;
  final Object body;

  WsServerHttpMessage({
    required this.id,
    required this.url,
    required this.method,
    required this.protocolVersion,
    required this.finished,
    required this.body,
    required this.headers,
  });

  factory WsServerHttpMessage.fromJson(Map messageJson) => WsServerHttpMessage(
        id: messageJson['id'] as int,
        method: HttpMethod.values.byName(messageJson['method'] as String),
        url: messageJson['url'] as String,
        protocolVersion: messageJson['protocolVersion'] as String,
        headers: (messageJson['headers'] as Map).cast(),
        finished: messageJson['finished'] as bool,
        body: messageJson['body'] as String,
      );

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'method': method,
        'url': url,
        'protocolVersion': protocolVersion,
        'headers': headers,
        'finished': finished,
        'body': body,
      };

  static const lastVersion = 0;

  factory WsServerHttpMessage.fromBytes(Uint8List messageBytes) {
    final parser = ByteParser(ByteData.sublistView(messageBytes));
    final messageVersion = parser.readUint32();

    return switch (messageVersion) {
      lastVersion || _ => WsServerHttpMessage(
          id: parser.readUint32(),
          method: HttpMethod.values[parser.readUint32()],
          url: parser.readUtf8String(),
          protocolVersion: parser.readUtf8String(),
          headers: parser.readMap(
            parser.readUtf8String,
            () => parser.readList(parser.readUtf8String),
          ),
          finished: parser.readBool(),
          body: parser.parsePayload(messageBytes)!,
        ),
    };
  }

  @override
  Uint8List toBytes() {
    final builder = ByteBuilder();
    builder.writeUint32List([lastVersion, id, method.index]);
    builder.writeUtf8(url);
    builder.writeUtf8(protocolVersion);
    builder.writeHeaders(headers);
    builder.writeBool(finished);
    builder.writePayload(body);
    return builder.takeBytes();
  }
}

class WsServerSubscriptionMessage extends WsServerMessage {
  final int wsId;
  final int? closeCode;
  final String? closeReason;
  final Object? message;

  WsServerSubscriptionMessage({
    required this.wsId,
    required this.closeCode,
    required this.closeReason,
    required this.message,
  });

  factory WsServerSubscriptionMessage.fromJson(Map messageJson) {
    return WsServerSubscriptionMessage(
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

  factory WsServerSubscriptionMessage.fromBytes(Uint8List messageBytes) {
    final parser = ByteParser(ByteData.sublistView(messageBytes));
    final messageVersion = parser.readUint32();

    return switch (messageVersion) {
      lastVersion || _ => WsServerSubscriptionMessage(
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
