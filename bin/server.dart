import 'dart:io';

import 'package:serws/serws.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

Response _rootHandler(Request req) {
  return Response.ok('Hello, World!\n');
}

Response _echoHandler(Request request) {
  final message = request.params['message'];
  return Response.ok('$message\n');
}

void main(List<String> args) async {
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;
  final servers = ServerResponders(password: 'password');
  final responseHandlers = ResponderHandlers(servers: servers);
  final wsHandler = webSocketHandler(responseHandlers.createServerHandler);

// Configure routes.
  final router = Router()
    ..get('/', _rootHandler)
    ..get('/echo/<message>', _echoHandler)
    ..all('/wscall', responseHandlers.wsCallHandler)
    ..all('/call', responseHandlers.callHandler)
    ..all('/subscribe', wsHandler);

  // Configure a pipeline that logs requests.
  final handler =
      Pipeline().addMiddleware(logRequests()).addHandler(router.call);

  // shelf_io.serve(handler, 'localhost', 8080).then((server) {
  //   print('Serving at ws://${server.address.host}:${server.port}');
  // });

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(handler, ip, port);
  print('Server listening on port ${server.port}');
}
