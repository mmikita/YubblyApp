import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yubbly_app/web_embedded.dart';

void main() {
  test('extractConfig reads a nested ytcfg object', () {
    final html =
        '<script>ytcfg.set({"INNERTUBE_CONTEXT":{"client":'
        '{"visitorData":"abc","clientName":"WEB_EMBEDDED_PLAYER"}},'
        '"STS":20746});</script>';
    final cfg = WebEmbeddedClient.extractConfig(html);
    expect(cfg, isNotNull);
    expect(cfg!['STS'], 20746);
    expect(cfg['INNERTUBE_CONTEXT']['client']['visitorData'], 'abc');
  });

  test('extractConfig ignores malformed blocks', () {
    expect(WebEmbeddedClient.extractConfig('ytcfg.set({broken});'), isNull);
  });

  test('parsePlayerResponse keeps every language and normalizes track ids', () {
    final json = {
      'playabilityStatus': {'status': 'OK'},
      'streamingData': {
        'adaptiveFormats': [
          {
            'itag': 140,
            'url': 'https://media.example/a?n=abc',
            'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
            'bitrate': 128000,
            'contentLength': '1234',
            'audioTrack': {
              'id': 'pl.10',
              'displayName': 'Polish',
              'audioIsDefault': false,
            },
          },
          {
            'itag': 251,
            'url': 'https://media.example/b?n=def',
            'mimeType': 'audio/webm; codecs="opus"',
            'bitrate': 140000,
            'contentLength': 4321,
            'audioTrack': {
              'id': 'en-US.4',
              'displayName': 'English (US) original',
              'audioIsDefault': true,
            },
          },
          {
            'itag': 137,
            'url': 'https://media.example/v',
            'mimeType': 'video/mp4',
            'bitrate': 1000000,
            'contentLength': '9999',
            'height': 1080,
          },
        ],
      },
    };
    final manifest = WebEmbeddedClient.parsePlayerResponse(
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
    );
    expect(manifest.audio, hasLength(2));
    expect(manifest.video, hasLength(1));
    expect(manifest.audio.first.trackId, 'pl');
    expect(manifest.audio.first.container, 'mp4');
    expect(manifest.audio.first.bytes, 1234);
    expect(manifest.audio.last.trackId, 'en-US');
    expect(manifest.audio.last.container, 'webm');
    expect(manifest.audio.last.isDefault, isTrue);
    expect(manifest.selectAudio('pl', mp4Only: true).tag, 140);
    expect(manifest.selectAudio('en-US', mp4Only: false).tag, 251);
    expect(manifest.selectVideo(maxHeight: 1080)?.height, 1080);
  });

  test('parsePlayerResponse reports unplayable videos', () {
    expect(
      () => WebEmbeddedClient.parsePlayerResponse({
        'playabilityStatus': {
          'status': 'ERROR',
          'reason': 'This video is unavailable',
        },
      }),
      throwsA(
        isA<WebEmbeddedException>().having(
          (e) => e.message,
          'message',
          contains('This video is unavailable'),
        ),
      ),
    );
  });

  test('selectAudio rejects missing MP4 when the platform requires it', () {
    final manifest = WebManifest(
      audio: [
        WebAudioStream(
          tag: 251,
          url: Uri.parse('https://media.example/opus'),
          container: 'webm',
          mimeType: 'audio/webm',
          bitrate: 128000,
          bytes: 10,
          trackId: 'pl',
          trackName: 'Polish',
          isDefault: false,
        ),
      ],
      video: const [],
    );
    expect(
      () => manifest.selectAudio('pl', mp4Only: true),
      throwsA(isA<StateError>()),
    );
  });
}
