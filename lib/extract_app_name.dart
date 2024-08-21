// import 'dart:io';
// import 'package:xml/xml.dart' as xml;

// Future<String> getAppNameFromManifest() async {
//   final manifestFile = File('android/app/src/main/AndroidManifest.xml');
//   final manifestContent = await manifestFile.readAsString();
  
//   final document = xml.parse(manifestContent);
//   final application = document.findAllElements('application').first;
//   final appName = application.getAttribute('android:name');
  
//   if (appName != null) {
//     return appName;
//   } else {
//     throw Exception('Failed to find android:name attribute in AndroidManifest.xml');
//   }
// }

// void main() async {
//   try {
//     final appName = await getAppNameFromManifest();
//     print('App Name: $appName');
//   } catch (e) {
//     print('Error: $e');
//   }
// }
