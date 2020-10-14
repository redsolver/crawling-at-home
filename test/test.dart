import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:crawling_at_home/runner/wikipedia.dart';

void main() {
  group('Wikipedia Runner', () {
    test('calculate', () {
      for (final File file in Directory('test/files/wikipedia').listSync()) {
        final content = file.readAsStringSync();

        final int lineEnd = content.indexOf('\n');
        final expectedJson = content.substring(0, lineEnd);

        final xml = content.substring(lineEnd);

        final wr = WikipediaTaskRunner({});

        wr.processPage(xml);

        wr.documents.forEach((element) {
          element['indexed_at'] = -1;
        });

        print(json.encode(wr.documents));
        expect(json.encode(wr.documents), expectedJson);
      }
    });
  });
}
