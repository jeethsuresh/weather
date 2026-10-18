import 'dart:convert';
import 'dart:io';
import 'package:local_weather/models.dart';
import 'package:local_weather/storage.dart';
import 'package:local_weather/weather_api.dart';

Json fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

class MemoryStore implements LocalStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class StubTransport implements JsonTransport {
  StubTransport(this.respond);
  final Future<Json> Function(Uri) respond;
  final calls = <Uri>[];
  @override
  Future<Json> get(Uri uri) {
    calls.add(uri);
    return respond(uri);
  }

  @override
  void close() {}
}
