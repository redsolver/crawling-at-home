import 'dart:convert';
import 'dart:io';

import "package:console/console.dart";
import 'package:crawling_at_home/runner/wikipedia.dart';
import 'package:crawling_at_home/util/skynet_upload.dart';

import 'package:filesize/filesize.dart' as filesize;

import 'package:http/http.dart' as http;

Map config;

final String endpoint = 'https://cah.solver.cloud';

final configFile = File('config.json');

Map get currentTask => config['task'];
String get configToken => config['token'];

void main(List<String> arguments) async {
  final loop = arguments.contains('--loop');

  final automatic = arguments.contains('--automatic');

  if (loop) {
    print('INFO: Running in loop mode.');
    while (true) {
      await start(automatic);
    }
  } else {
    await start(automatic);
  }
}

Future<void> start(bool automatic) async {
  if (!configFile.existsSync()) {
    configFile.writeAsStringSync('{}');
  }

  config = json.decode(configFile.readAsStringSync());

  Console.init();

  while (!config.containsKey('token')) {
    print('Welcome to Crawling@Home!');
    print(
        '\n\nWARNING: Please make sure you have the command line tools "wget", "sha1sum" and "bunzip2" installed!');

    print('');
    final token = await readInput('Please enter your token: ');

    if (token.length != 36) {
      print('Invalid token.');
    } else {
      config['token'] = token;
      saveConfig();
      printColor('\nToken set and saved in config.json\n', Color.GREEN);
    }
  }

  if (currentTask != null) {
  } else {
    print('Fetching available tasks...');

    final res = await http.get('$endpoint/tasks');

    List<Map> tasks = json.decode(res.body).cast<Map>();

    if (tasks.length > 5) {
      tasks = tasks.sublist(0, 5);
    }

    final list = tasks.map<String>((e) {
      return '${e['type']}: ${e['file']} (${filesize.filesize(e['size'], 0)})';
    }).toList();

    print('');

    var chooser = Chooser<String>(
      list,
      message: "Select a Task: ",
    );

    String str;

    if (automatic) {
      str = list.first;
    } else {
      print('Hint: Run with --automatic flag to skip this selection\n');

      str = chooser.chooseSync();
    }

    printColor("\n$str", Color.CYAN);

    printColor("\nClaiming task...", Color.CYAN);

    final i = list.indexOf(str);

    final task = tasks[i];

    print(task);

    final res2 = await http.post('$endpoint/claimTask',
        body: json.encode({
          'token': configToken,
          'id': task['id'],
        }));

    if (res2.statusCode != 200) {
      throw Exception('HTTP ${res2.statusCode} ${res2.body}');
    }
    final res2status = json.decode(res2.body);

    if (res2status['status'] != 'ok') {
      throw Exception('Status ${res2status}');
    }

    config['task'] = task;

    saveConfig();

    printColor("\nSuccessfully claimed task!", Color.GREEN);
  }

  print(
      'Executing ${currentTask['type']} task runner for ${currentTask['file']}');

  if (currentTask['type'] == 'wikipedia') {
    final runner = WikipediaTaskRunner(currentTask);

    final file = await runner.run();

    print('Uploading to Skynet...');

    final skynetFile = await uploadFile(file);

    print('Submitting task...');

    final res2 = await http.post('$endpoint/submitTask',
        body: json.encode({
          'token': configToken,
          'id': currentTask['id'],
          'skylink': skynetFile.skylink,
          'sha256': skynetFile.sha256,
        }));

    if (res2.statusCode != 200) {
      throw Exception('HTTP ${res2.statusCode} ${res2.body}');
    }
    final res2status = json.decode(res2.body);

    if (res2status['status'] != 'ok') {
      throw Exception('Status ${res2status}');
    }

    config.remove('task');

    saveConfig();

    printColor('\nTASK SUCCESS\n', Color.GREEN);
  }
}

void printColor(String text, Color color) {
  var pen = TextPen();

  pen.setColor(color);
  pen.text(text);

  pen.print();
}

void saveConfig() {
  configFile.writeAsStringSync(json.encode(config));
}
