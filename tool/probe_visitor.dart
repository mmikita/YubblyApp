// Checks whether passing visitorData (and the matching header) to the player
// lifts the 1 MiB range cap on dubbed audio tracks.
//
// Usage: dart run tool/probe_visitor.dart [videoId]
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<String> visitorData() async {
  final request = await _client.postUrl(
    Uri.parse(
      'https://www.youtube.com/youtubei/v1/visitor_id?prettyPrint=false',
    ),
  );
  request.headers.contentType = ContentType.json;
  request.add(
    utf8.encode(
      jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': '2.20250101.00.00',
            'hl': 'en',
          },
        },
      }),
    ),
  );
  final json =
      jsonDecode(await utf8.decodeStream(await request.close()))
          as Map<String, dynamic>;
  final context = json['responseContext'] as Map<String, dynamic>? ?? {};
  final data = context['visitorData'] as String?;
  if (data == null) throw StateError('no visitorData: $json');
  return data;
}

Future<Map<String, dynamic>> player(String id, {String? visitor}) async {
  final c = YoutubeApiClient.androidSdkless;
  final request = await _client.postUrl(Uri.parse(c.apiUrl));
  request.headers.contentType = ContentType.json;
  if (visitor != null) {
    request.headers.set('X-Goog-Visitor-Id', visitor);
    request.headers.set(
      HttpHeaders.cookieHeader,
      'VISITOR_INFO1_LIVE=$visitor',
    );
  }
  final context =
      jsonDecode(jsonEncode(c.payload['context'])) as Map<String, dynamic>;
  if (visitor != null) {
    (context['client'] as Map<String, dynamic>)['visitorData'] = visitor;
  }
  request.add(
    utf8.encode(
      jsonEncode({
        'context': context,
        'videoId': id,
        'contentCheckOk': true,
        'racyCheckOk': true,
      }),
    ),
  );
  return jsonDecode(await utf8.decodeStream(await request.close()))
      as Map<String, dynamic>;
}

Future<String> probe(Uri url, int start, int length) async {
  final request = await _client.getUrl(url);
  request.headers.set(
    HttpHeaders.rangeHeader,
    'bytes=$start-${start + length - 1}',
  );
  final response = await request.close();
  var read = 0;
  try {
    await for (final chunk in response) {
      read += chunk.length;
      if (read >= length) break;
    }
  } catch (_) {}
  return '${response.statusCode}/$read';
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  try {
    final visitor = await visitorData();
    stdout.writeln(
      'visitor=${visitor.substring(0, 24)}... (${visitor.length})',
    );
    final json = await player(id, visitor: visitor);
    final status = json['playabilityStatus'] as Map<String, dynamic>?;
    final data = json['streamingData'] as Map<String, dynamic>? ?? {};
    final formats =
        (data['adaptiveFormats'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    stdout.writeln('status=${status?['status']} formats=${formats.length}');
    final format = formats.firstWhere(
      (f) =>
          '${f['mimeType']}'.startsWith('audio/') &&
          (Uri.parse(f['url'] as String).queryParameters['xtags'] ?? '')
              .contains('dubbed'),
      orElse: () =>
          formats.firstWhere((f) => '${f['mimeType']}'.startsWith('audio/')),
    );
    final url = Uri.parse(format['url'] as String);
    stdout.writeln(
      'xtags=${url.queryParameters['xtags']} len=${format['contentLength']}',
    );
    for (final offset in [0, 1 << 20, 2 << 20, 5 << 20]) {
      stdout.writeln(
        '  @${offset ~/ 1024}K -> ${await probe(url, offset, 65536)}',
      );
    }
  } catch (error) {
    stdout.writeln('failed: $error');
  } finally {
    _client.close(force: true);
  }
}
