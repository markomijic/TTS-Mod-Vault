import 'dart:convert' show JsonEncoder, json;
import 'dart:io' show File;
import 'dart:ui' show ImageFilter;

import 'package:bson/bson.dart' show BsonBinary, BsonCodec;
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useTextEditingController, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, modsProvider;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

class DownloadModByIdDialog extends HookConsumerWidget {
  const DownloadModByIdDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetDirectory =
        useState(p.normalize(ref.read(directoriesProvider).workshopDir));
    final downloading = useState(false);
    final textController = useTextEditingController();

    Future<void> downloadAndResizeImage(dynamic imageUrl, String modId) async {
      if (imageUrl is! String) {
        return;
      }

      try {
        // Download the image
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode != 200) {
          debugPrint('Failed to download image');
          return;
        }

        // Decode the image
        final originalImage = img.decodeImage(response.bodyBytes);
        if (originalImage == null) {
          debugPrint('Failed to decode image');
          return;
        }

        // First save the original at maximum quality
        final tempPath = '${targetDirectory.value}/${modId}_temp.png';
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(img.encodePng(
          originalImage,
          level: 0,
        ));

        // Read back the uncompressed image
        final uncompressedBytes = await tempFile.readAsBytes();
        final uncompressedImage = img.decodeImage(uncompressedBytes);
        if (uncompressedImage == null) {
          debugPrint('Failed to decode uncompressed image');
          return;
        }

        // Now resize from the uncompressed version
        final resizedImage = img.copyResizeCropSquare(
          uncompressedImage,
          size: 256,
          interpolation: img.Interpolation.cubic,
        );

        // Save the final resized image with minimal compression
        final finalPath = '${targetDirectory.value}/$modId.png';
        final finalFile = File(finalPath);

        await finalFile.writeAsBytes(img.encodePng(
          resizedImage,
          level: 0, // Keep using no compression for best quality
        ));

        // Clean up temp file
        await tempFile.delete();

        debugPrint('Image saved to: $finalPath');
      } catch (e) {
        debugPrint('Error processing image: $e');
      }
    }

    Future<String> downloadAndConvertBson(dynamic fileUrl, String modId) async {
      if (fileUrl is! String) {
        return "Invalid url: $fileUrl";
      }

      try {
        final response = await http.get(Uri.parse(fileUrl));
        if (response.statusCode != 200) {
          return "Failed to download BSON file from $fileUrl";
        }

        final bsonBinary = BsonBinary.from(response.bodyBytes);
        final decodedData = BsonCodec.deserialize(bsonBinary);
        decodedData.removeWhere((key, value) => value is BsonBinary);

        final jsonEncoder = JsonEncoder.withIndent('  ', (object) {
          if (object is Int64) return object.toString();
          return object;
        });

        final jsonString = jsonEncoder.convert(decodedData);

        final filePath = '${targetDirectory.value}/$modId.json';
        final file = File(filePath);

        await file.writeAsString(jsonString);
        return 'Mod saved to: $filePath';
      } catch (e) {
        return 'Error for mod json file: $e';
      }
    }

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        content: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            Text(
              'Download Workshop Mod by ID',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            TextField(
              controller: textController,
              cursorColor: Colors.black,
              keyboardType: TextInputType.number,
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                fillColor: Colors.white,
                border: OutlineInputBorder(),
                hintText: 'Enter ID',
              ),
            ),
            Text('Save to: ${targetDirectory.value}'),
            Row(
              spacing: 8,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: downloading.value
                      ? null
                      : () async {
                          String? dir;
                          final initialDirectory = p.normalize(
                              ref.read(directoriesProvider).workshopDir);

                          try {
                            dir = await FilePicker.platform.getDirectoryPath(
                              lockParentWindow: true,
                              initialDirectory: initialDirectory,
                            );
                          } catch (e) {
                            debugPrint("File picker error $e");
                            if (context.mounted) {
                              showSnackBar(
                                  context, "Failed to open file picker");
                              Navigator.pop(context);
                            }
                            return;
                          }

                          if (dir == null) return;

                          targetDirectory.value = p.normalize(dir);
                        },
                  child: Text('Select folder'),
                ),
                Spacer(),
                ElevatedButton(
                  onPressed: downloading.value
                      ? null
                      : () {
                          Navigator.of(context).pop();
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: downloading.value
                      ? null
                      : () async {
                          try {
                            final modId = textController.text;
                            if (textController.text.isEmpty) {
                              return;
                            }

                            downloading.value = true;

                            final url = Uri.parse(
                              'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/',
                            );

                            final response = await http.post(
                              url,
                              body: {
                                'itemcount': '1',
                                'publishedfileids[0]': modId.toString(),
                              },
                            );

                            final responseData = json.decode(response.body);
                            final fileDetails = responseData['response']
                                ['publishedfiledetails'][0];

                            final consumerAppId =
                                fileDetails['consumer_app_id'];
                            if (consumerAppId == 286160) {
                              final fileUrl = fileDetails['file_url'];
                              final previewUrl = fileDetails['preview_url'];

                              final resultMessage =
                                  await downloadAndConvertBson(fileUrl, modId);
                              await downloadAndResizeImage(previewUrl, modId);

                              // Add the newly downloaded mod to state
                              final jsonFilePath =
                                  '${targetDirectory.value}/$modId.json';
                              await ref
                                  .read(modsProvider.notifier)
                                  .addSingleMod(
                                    jsonFilePath,
                                    ModTypeEnum.mod,
                                  );

                              if (context.mounted) {
                                if (resultMessage.isNotEmpty) {
                                  showSnackBar(context, resultMessage);
                                }
                                Navigator.of(context).pop();
                              }
                            } else {
                              debugPrint('Consumer app ID: $consumerAppId');
                              if (context.mounted) {
                                showSnackBar(context,
                                    'Consumer app ID does not match. Expected: 286160, Got: $consumerAppId');
                                Navigator.of(context).pop();
                              }
                            }
                          } catch (e) {
                            debugPrint('Error: $e');
                            if (context.mounted) {
                              showSnackBar(context, 'Error: $e');
                              Navigator.of(context).pop();
                            }
                          } finally {
                            downloading.value = false;
                          }
                        },
                  icon: Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
