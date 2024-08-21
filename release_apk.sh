#!/bin/bash

# Build the APK
flutter build apk

# Run Dart script to upload APK to Google Drive and send Slack message
dart run lib/upload_apk_to_google_drive.dart
