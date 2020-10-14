import 'dart:convert';
import 'dart:io';

import 'package:crawling_at_home/vars.dart';
import 'package:http/http.dart' as http;


void main(List<String> arguments) async {
  // bool nonInteractively

  final res = await http.get('$mirror/enwiki/20201001/dumpstatus.json');

  final data = json.decode(res.body);

  final articleFiles = data['jobs']['articlesdump']['files'];

  List<Map> tasks = [];

  for (final String file in articleFiles.keys) {
    final fileData = articleFiles[file];
    
    final pagePart = file.split('-').last.split('.').first;

    final pageParts = pagePart.split('p');

    tasks.add({
      'id': fileData['sha1'],
      'type': 'wikipedia',
      'file': file,
      'path': fileData['url'],
      'size': fileData['size'],
      'sha1': fileData['sha1'],
      'firstPageID': int.parse(pageParts[1]),
      'lastPageID': int.parse(pageParts[2]),
    });
  }

  tasks.sort((a, b) => -a['firstPageID'].compareTo(b['firstPageID']));


  File('data/server/tasks.json').writeAsStringSync(json.encode(tasks));


}
