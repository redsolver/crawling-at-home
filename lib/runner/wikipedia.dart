import 'dart:convert';
import 'dart:io';

import 'package:crawling_at_home/vars.dart';
import 'package:html_character_entities/html_character_entities.dart';

class WikipediaTaskRunner {
  final Map task;

  WikipediaTaskRunner(this.task);

  Future<File> run() async {
    final String id = task['id'];

    final Directory directory = Directory('data/$id');
    if (!directory.existsSync()) directory.createSync(recursive: true);

    final String cFileName = task['file'];

    final File compressedFile = File('${directory.path}/$cFileName');
    final File file =
        File('${directory.path}/${cFileName.split(".bz2").first}');

    final File checkpointFile = File('${directory.path}/checkpoint');

    final File jsonFile = File('${directory.path}/out.json');

    bool allowDL = true;

    if (checkpointFile.existsSync()) {
      if (int.parse(checkpointFile.readAsStringSync()) == 999999999999) {
        allowDL = false;
      }
    }

    if (!file.existsSync() && allowDL) {
      print('Starting download and decompression step...');

      if (!compressedFile.existsSync()) {
        print('Downloading compressed file...');

        final downloadProcess = await Process.start(
          'wget',
          ['$mirror/${task['path']}'],
          workingDirectory: directory.path,
          mode: ProcessStartMode.normal,
        );

        bindToStdout(downloadProcess.stdout);
        bindToStdout(downloadProcess.stderr);

        var buildCode = await downloadProcess.exitCode;

        if (buildCode != 0) throw Exception('Failed to download file.');
      }

      print('Checking file integrity...');

      final result = await Process.run('sha1sum', [compressedFile.path]);

      final String hash = result.stdout.split(' ').first;

      if (hash != task['sha1']) {
        throw Exception('INVALID HASH!!');
      }

      print('Success.');

      print('Decompressing file...');

      final downloadProcess = await Process.start(
        'bunzip2',
        [cFileName],
        workingDirectory: directory.path,
        mode: ProcessStartMode.normal,
      );

      bindToStdout(downloadProcess.stdout);
      bindToStdout(downloadProcess.stderr);

      var buildCode = await downloadProcess.exitCode;

      if (buildCode != 0) throw Exception('Failed to decompress file.');

      print('Success.');
    }
    print('Processing file...');

    int checkpoint = 0;

    if (checkpointFile.existsSync()) {
      checkpoint = int.tryParse(checkpointFile.readAsStringSync()) ?? 0;
      print('Skipping until checkpoint is reached...');
    } else {
      jsonFile.writeAsStringSync('[');
    }

    if (checkpoint < 999999999999) {
      int firstPageID = task['firstPageID'];
      int lastPageID = task['lastPageID'];

      int diff = lastPageID - firstPageID;

      int i = 0;

      String s = '';

      bool start = true;

      List<int> old = [];

      await for (final part in file.openRead()) {
        try {
          if (old.isNotEmpty) {
            s += utf8.decode([...old, ...part]);
            old = [];
          } else {
            s += utf8.decode(part);
          }
        } catch (e) {
          old.addAll(part);
        }

        if (start) {
          if (s.contains('</siteinfo>')) {
            s = s.substring(s.indexOf('</siteinfo>') + 11);
            start = false;
          }
        }

        while (s.contains('<page>') && s.contains('</page>')) {
          final page = s.split('</page>')[0];
          i++;

          if (i % 1000 == 0) {
            final id = int.parse(page.split('</id>')[0].split('<id>')[1]);

            int norm = id - firstPageID;

            double percent = norm / diff * 100;

            print(percent.toStringAsFixed(2) + ' % done');

            if (i <= checkpoint) {
              s = s.substring(page.length + 7);
              continue;
            }

            if (i % 10000 == 0) {
              print('Checkpoint saving...');
              String str = json.encode(documents).replaceAll('\\u', 'u');

              str = str.substring(1, str.length - 1);
              if (checkpoint != 0) {
                str = ',$str';
              }
              jsonFile.writeAsStringSync(str, mode: FileMode.writeOnlyAppend);
              checkpointFile.writeAsStringSync(i.toString());
              checkpoint = i;
              documents = [];
              print('Checkpoint done');
            }
          } else {
            if (i <= checkpoint) {
              s = s.substring(page.length + 7);
              continue;
            }
          }

          await processPage(page);

          s = s.substring(page.length + 7);
        }
      }

      String str = json.encode(documents).replaceAll('\\u', 'u');

      str = str.substring(1);
      if (checkpoint != 0 && documents.isNotEmpty) {
        str = ',$str';
      }
      jsonFile.writeAsStringSync(str, mode: FileMode.writeOnlyAppend);

      checkpointFile.writeAsStringSync('999999999999');

      print('Done.');
    } else {
      print('Skip processing.');
    }
    if (file.existsSync()) {
      print('Deleting XML file...');
      await file.delete();
    }

    return jsonFile;
  }

  List<Map> documents = [];

  Future<void> processPage(String page) async {
    if (!page.contains('<redirect title="')) {
      String title = page.split('</title>')[0].split('<title>')[1];

      bool isCategory = false;

      if (title.contains(':')) {
        if (title.startsWith('File:') ||
            title.startsWith('Wikipedia:') ||
            title.startsWith('Template:') ||
            title.startsWith('Draft:') ||
            title.startsWith('Portal:') ||
            title.startsWith('Module:') ||
            title.startsWith('Help:') ||
            title.startsWith('MediaWiki:')) {
          return;
        }

        if (title.startsWith('Category:')) {
          isCategory = true;
          title = title.substring(9);
        }
      }

/*       if (title.contains(':') && !title.startsWith('Category:')) {
        print(title);
      }
 */

      final id = page.split('</id>')[0].split('<id>')[1];

      String text = page.split('<text')[1].trimLeft();

      final int start = text.indexOf('>');

      text = text.substring(start + 1);

      if (text.length > 50000) {
        text = text.substring(0, 50000);
      }

      text = HtmlCharacterEntities.decode(text);

      int blockLevel = 0;

      for (String line in text.split('\n')) {
        line = line.trim();

        if (blockLevel > 0) {
          blockLevel -= (line.split('}}').length - 1);

          blockLevel += (line.split('{{').length - 1);

          continue;
        }

        if (line.startsWith('[[')) continue;

        if (line.startsWith('{{')) {
          blockLevel -= (line.split('}}').length - 1);

          blockLevel += (line.split('{{').length - 1);
          continue;
        }
        if (line.startsWith('<!--')) continue;

        if (line.startsWith('<sha1>')) continue;
        if (line.startsWith('</')) continue;

        if (line.isEmpty) continue;

        text = line;
        break;
      }

      text = text.replaceAll("'''", '');
      text = text.replaceAll("''", '');

      text = text.replaceAll(RegExp(r'<ref(.*?)<\/ref>'), '');

      text = text.replaceAll(RegExp(r'<ref(.*?)\/>'), '');

      text = text.replaceAll(RegExp(r'<!--([^>]+)-->'), '');

      text = text.replaceAllMapped(RegExp(r'\[\[([^\]]+)\]\]'),
          (match) => match.group(1).split('|').last);

      text = text.replaceAll(RegExp(r'\{\{([^\}]+)\}\};? *'), '');

      text = text.replaceAll('}}', '');
      text = text.replaceAll('(,', '(');
      text = text.replaceAll(RegExp(r' \( *'), ' (');
      text = text.replaceAll(RegExp(r' \(\)'), '');

      if (text.length > 400) {
        text = text.substring(0, 400).trimRight() + '...';
      }

      text = text.replaceAll('  ', ' ');

      final tags = isCategory ? ['wikipedia-category'] : ['wikipedia'];

      addPageToIndex(
        id: id.trim(),
        title: HtmlCharacterEntities.decode(title),
        description: isCategory ? '' : text,
        type: 'text/html',
        link: isCategory
            ? 'https://en.wikipedia.org/wiki/Category:${title.replaceAll(' ', '_')}'
            : 'https://en.wikipedia.org/wiki/${title.replaceAll(' ', '_')}',
        tags: tags,
      );
    }
  }

  void addPageToIndex(
      {String id,
      String title,
      String description,
      String type,
      String link,
      List<String> tags}) {
    final doc = {
      "id": 'wp-$id',
      "title": title,
      "description": description,
      "tags": tags,
      "link": link,
      'type': type,
      "indexed_at": DateTime.now().millisecondsSinceEpoch,
    };

    documents.add(doc);
  }
}

void bindToStdout(var x) {
  x.transform(utf8.decoder).transform(const LineSplitter()).listen((event) {
    if (event.isNotEmpty) {
      print(event);
    }
  });
}
