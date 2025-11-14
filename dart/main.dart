import 'dart:async';
import 'dart:convert';
import 'dart:io';

class JsonRpcRequest {
  final dynamic id;
  final String method;
  final dynamic params;

  JsonRpcRequest({required this.id, required this.method, this.params});

  static JsonRpcRequest? tryParse(Map<String, dynamic> m) {
    if (m['jsonrpc'] != '2.0') return null;
    final method = m['method'];
    if (method is! String) return null;
    final id = m.containsKey('id') ? m['id'] : null;
    return JsonRpcRequest(id: id, method: method, params: m['params']);
  }
}

Map<String, dynamic> jsonRpcResult(dynamic id, dynamic result) => {
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    };

Map<String, dynamic> jsonRpcError(dynamic id, int code, String message,
        [dynamic data]) =>
    {
      'jsonrpc': '2.0',
      'id': id,
      'error': {
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      }
    };

typedef ToolHandler = Future<dynamic> Function(Map<String, dynamic> params);

class Tool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final ToolHandler handler;

  Tool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
  });

  Map<String, dynamic> toDescriptor() => {
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
      };
}

class ToolRegistry {
  final Map<String, Tool> _tools = {};

  void register(Tool tool) {
    _tools[tool.name] = tool;
  }

  Tool? get(String name) => _tools[name];

  List<Map<String, dynamic>> listDescriptors() =>
      _tools.values.map((t) => t.toDescriptor()).toList(growable: false);
}

class SchemaValidationException implements Exception {
  final String message;
  SchemaValidationException(this.message);
  @override
  String toString() => 'SchemaValidationException: $message';
}

void validateAgainstSchema(
    Map<String, dynamic>? value, Map<String, dynamic> schema) {
  if (schema['type'] != 'object') {
    return;
  }
  if (value == null) {
    throw SchemaValidationException('Expected params object, got null.');
  }
  final props = (schema['properties'] ?? {}) as Map<String, dynamic>;
  final requiredList = (schema['required'] ?? []) as List;

  for (final key in requiredList) {
    if (!value.containsKey(key)) {
      throw SchemaValidationException('Missing required property: $key');
    }
  }

  bool _matchesType(dynamic v, String t) {
    switch (t) {
      case 'string':
        return v is String;
      case 'number':
        return v is num;
      case 'integer':
        return v is int;
      case 'boolean':
        return v is bool;
      case 'object':
        return v is Map;
      case 'array':
        return v is List;
      default:
        return true;
    }
  }

  for (final entry in value.entries) {
    if (!props.containsKey(entry.key)) continue;
    final def = props[entry.key] as Map<String, dynamic>;
    final type = def['type'];
    if (type is String && !_matchesType(entry.value, type)) {
      throw SchemaValidationException(
          'Property "${entry.key}" expected type $type.');
    }
  }
}

Tool greetTool = Tool(
  name: 'greet',
  description: 'Greets a user by name.',
  inputSchema: {
    'type': 'object',
    'properties': {
      'name': {'type': 'string', 'description': 'Name to greet'}
    },
    'required': ['name']
  },
  handler: (params) async {
    final name = params['name'] as String;
    return {'message': 'Hello, $name! 👋'};
  },
);

Tool addTool = Tool(
  name: 'add',
  description: 'Adds two numbers (a + b).',
  inputSchema: {
    'type': 'object',
    'properties': {
      'a': {'type': 'number'},
      'b': {'type': 'number'}
    },
    'required': ['a', 'b']
  },
  handler: (params) async {
    final a = (params['a'] as num).toDouble();
    final b = (params['b'] as num).toDouble();
    return {'sum': a + b};
  },
);

Tool timeTool = Tool(
  name: 'time',
  description: 'Returns the current server time (ISO 8601).',
  inputSchema: {
    'type': 'object',
    'properties': {}
  },
  handler: (params) async {
    return {'iso': DateTime.now().toUtc().toIso8601String()};
  },
);

class McpLikeServer {
  final ToolRegistry registry;

  McpLikeServer(this.registry);

  Future<Map<String, dynamic>> _handle(String method, dynamic params) async {
    switch (method) {
      case 'mcp/handshake':
        return {
          'protocol': 'mcp-like',
          'version': '0.1.0',
          'server': {
            'name': 'dart-mcp-like',
            'version': '0.1.0',
          }
        };

      case 'mcp/list_tools':
        return {
          'tools': registry.listDescriptors(),
        };

      case 'mcp/call_tool':
        {
          if (params is! Map<String, dynamic>) {
            throw SchemaValidationException('params must be an object.');
          }
          final name = params['name'];
          final args = (params['arguments'] ?? {}) as Map<String, dynamic>;
          if (name is! String) {
            throw SchemaValidationException('name must be a string.');
          }
          final tool = registry.get(name);
          if (tool == null) {
            throw SchemaValidationException('Unknown tool: $name');
          }
          validateAgainstSchema(args, tool.inputSchema);
          final out = await tool.handler(args);
          return {'output': out};
        }

      default:
        throw SchemaValidationException('Unknown method: $method');
    }
  }

  Future<void> handleRaw(Map<String, dynamic> message,
      void Function(Map<String, dynamic>) send) async {
    final req = JsonRpcRequest.tryParse(message);
    if (req == null) {
      final id = message['id'];
      if (id != null) {
        send(jsonRpcError(id, -32600, 'Invalid Request'));
      }
      return;
    }

    if (req.id == null) return;

    try {
      final result = await _handle(req.method, req.params);
      send(jsonRpcResult(req.id, result));
    } on SchemaValidationException catch (e) {
      send(jsonRpcError(req.id, -32602, 'Invalid params', {'detail': e.toString()}));
    } catch (e, st) {
      send(jsonRpcError(req.id, -32603, 'Internal error', {
        'message': e.toString(),
        'stack': st.toString(),
      }));
    }
  }
}

Future<void> runOnStdio(McpLikeServer server) async {
  final out = stdout;
  void send(Map<String, dynamic> msg) {
    out.writeln(jsonEncode(msg));
    out.flush();
  }

  await stdin.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) async {
      if (line.trim().isEmpty) return;
      Map<String, dynamic> msg;
      try {
        msg = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      await server.handleRaw(msg, send);
    },
    cancelOnError: false,
  ).asFuture();
}

Future<void> runOnWebSocket(McpLikeServer server, InternetAddress host, int port) async {
  final httpServer = await HttpServer.bind(host, port);
  print('WebSocket listening on ws://${host.address}:$port');
  await for (final req in httpServer) {
    if (WebSocketTransformer.isUpgradeRequest(req)) {
      final socket = await WebSocketTransformer.upgrade(req);
      socket.listen((data) async {
        Map<String, dynamic> msg;
        try {
          if (data is String) {
            msg = jsonDecode(data) as Map<String, dynamic>;
          } else if (data is List<int>) {
            msg = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
          } else {
            return;
          }
        } catch (_) {
          return;
        }
        void send(Map<String, dynamic> reply) {
          socket.add(jsonEncode(reply));
        }

        await server.handleRaw(msg, send);
      });
    } else {
      req.response.statusCode = 400;
      req.response.write('Expected WebSocket upgrade');
      await req.response.close();
    }
  }
}

void main(List<String> args) async {
  final registry = ToolRegistry()
    ..register(greetTool)
    ..register(addTool)
    ..register(timeTool);

  final server = McpLikeServer(registry);

  if (args.contains('--stdio')) {
    await runOnStdio(server);
    return;
  }

  final hostArg = _argValue(args, '--host') ?? '127.0.0.1';
  final portArg = int.tryParse(_argValue(args, '--port') ?? '8765') ?? 8765;

  final host = InternetAddress.tryParse(hostArg) ?? InternetAddress.loopbackIPv4;
  await runOnWebSocket(server, host, portArg);
}

String? _argValue(List<String> args, String key) {
  final i = args.indexOf(key);
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  return null;
}
