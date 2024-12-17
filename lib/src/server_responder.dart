import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:serws/src/ws_message.dart';
import 'package:serws/src/ws_server_message.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class Responder {
  final WebSocketChannel _webSocket;
  final Map<int, Completer<WsHttpMessage>> httpRequests = {};
  final Map<int, WebSocketChannel> wsSubscriptionsRequests = {};

  Responder(this._webSocket);

  Future<void> handleWsMessage(message) async {
    final parsed = WsMessage.fromMessage(message);
    switch (parsed) {
      case WsConfigMessage parsed:
        if (parsed.remove) {
          return _webSocket.sink.close();
        }
      case WsHttpMessage parsed:
        final id = parsed.id;
        httpRequests[id]!.complete(parsed);
      case WsSubscriptionMessage parsed:
        final id = parsed.wsId;
        final ws = wsSubscriptionsRequests[id]!;
        if (parsed.message != null) {
          ws.sink.add(parsed.message);
        }
        if (parsed.closeCode != null) {
          wsSubscriptionsRequests.remove(id);
          return ws.sink.close(parsed.closeCode, parsed.closeReason);
        }
    }
  }

  Future<void> sendWsMessage(WsServerMessage message) async {
    _webSocket.sink.add(message.toBytes());
  }

  Future<void> dispose() {
    httpRequests.values.forEach((c) => c.completeError('Server disconnected'));
    return Future.wait(
      wsSubscriptionsRequests.values.map((c) => c.sink.close()),
    );
  }
}

class ServerResponders {
  final String password;
  final List<Responder> servers = [];
  final Random random;

  ServerResponders({required this.password, Random? random})
      : random = random ?? Random.secure();

  void create(WebSocketChannel webSocket, String? subprotocol) {
    final responder = Responder(webSocket);
    bool initial = true;
    webSocket.stream.listen(
      (message) {
        if (initial) {
          // TODO: receive config such as last version and ws support
          if (message != password) {
            webSocket.sink.close();
            return;
          }
          initial = false;
          servers.add(responder);
          responder.sendWsMessage(WsServerConfigMessage(
            subprotocol: subprotocol,
          ));
        } else {
          responder.handleWsMessage(message);
        }
      },
      onDone: () {
        responder.dispose();
        servers.remove(responder);
      },
    );
  }

  // TODO: by ip
  Responder? selectForHttp(Request request) {
    return servers.isEmpty ? null : servers.first;
  }

  Responder? selectForWs(Request request) {
    return servers.isEmpty ? null : servers.first;
  }
}

class ResponderHandlers {
  final ServerResponders servers;
  final Duration httpBodyDuration;
  int lastHttpCallId = 0;
  int lastWsCallId = 0;

  ResponderHandlers({
    required this.servers,
    this.httpBodyDuration = const Duration(seconds: 2),
  });

  void createServerHandler(WebSocketChannel webSocket, String? subprotocol) {
    servers.create(webSocket, subprotocol);
  }

  Future<Response> callHandler(Request req) async {
    final responder = servers.selectForHttp(req);
    if (responder == null) return Response.internalServerError();

    BytesBuilder buffer = BytesBuilder();
    final id = ++lastHttpCallId;
    void send({bool finished = false}) {
      if (buffer.isNotEmpty) {
        responder.sendWsMessage(WsServerHttpMessage(
          id: id,
          url: req.url.toString(),
          method: HttpMethod.values.byName(req.method),
          protocolVersion: req.protocolVersion,
          headers: req.headersAll,
          body: buffer.takeBytes(),
          finished: finished,
        ));
        buffer = BytesBuilder();
      }
      if (!finished) {
        Timer(httpBodyDuration, send);
      }
    }

    Timer(httpBodyDuration, send);
    await for (final b in req.read()) {
      buffer.add(b);
    }
    send(finished: true);

    final comp = Completer<WsHttpMessage>();
    responder.httpRequests[lastHttpCallId] = comp;
    final value = await comp.future;
    return Response(
      value.statusCode,
      body: value.body,
      headers: value.headers,
    );
  }

  FutureOr<Response> wsCallHandler(Request req) {
    final responder = servers.selectForWs(req);
    if (responder == null) return Response.internalServerError();

    final inner =
        webSocketHandler((WebSocketChannel webSocket, String? subprotocol) {
      final wsId = ++lastWsCallId;
      responder.wsSubscriptionsRequests[wsId] = webSocket;
      webSocket.stream.listen(
        (message) {
          responder.sendWsMessage(
            WsServerSubscriptionMessage(
              wsId: wsId,
              message: message,
              closeCode: null,
              closeReason: null,
            ),
          );
        },
        onDone: () {
          final removed = responder.wsSubscriptionsRequests.remove(wsId);
          if (removed != null) {
            responder.sendWsMessage(
              WsServerSubscriptionMessage(
                wsId: wsId,
                message: null,
                closeCode: webSocket.closeCode,
                closeReason: webSocket.closeReason,
              ),
            );
          }
        },
      );
    });
    return inner(req);
  }
}
