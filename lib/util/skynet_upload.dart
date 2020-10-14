import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';

final String skynetPortalUploadUrl = 'https://siasky.net/skynet/skyfile';

Future<SkynetFile> uploadFile(File file) async {
  print('hashing...');
  final hash = await file.openRead().transform(sha256).join();

  var stream = new http.ByteStream(file.openRead());
  var length = await file.length();

  var uri = Uri.parse(skynetPortalUploadUrl);

  print('uploading...');

  var request = new http.MultipartRequest("POST", uri);
  var multipartFile = new http.MultipartFile('file', stream, length,
      filename: basename(file.path));

  request.files.add(multipartFile);
  var response = await request.send();

  if (response.statusCode != 200) {
    throw Exception('HTTP ${response.statusCode}');
  }

  final res = await response.stream.transform(utf8.decoder).join();

  final resData = json.decode(res);

  if (resData['skylink'] == null) throw Exception('Skynet Upload Fail');

  return SkynetFile(sha256: hash, skylink: resData['skylink']);
}

class SkynetFile {
  String skylink;
  String sha256;
  SkynetFile({this.skylink, this.sha256});
}
