import 'dart:convert' show JsonEncoder, json;
import 'dart:io' show File;

import 'package:bson/bson.dart' show BsonBinary, BsonCodec;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useTextEditingController, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:tts_mod_vault/src/state/provider.dart' show directoriesProvider;

class DownloadModByIdDialog extends HookConsumerWidget {
  const DownloadModByIdDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workshopDir = ref.watch(directoriesProvider).workshopDir;

    Future<void> downloadAndResizeImage(String imageUrl, String modId) async {
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

        // First save the original at maximum quality with NO compression
        final tempPath = '$workshopDir/test/${modId}_temp.png';
        final tempFile = File(tempPath);
        await tempFile.parent.create(recursive: true);

        // Save with level 0 (no compression) to preserve maximum quality
        await tempFile.writeAsBytes(img.encodePng(
          originalImage,
          level: 0, // No compression
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
        final finalPath = '$workshopDir/test/$modId.png';
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

    Future<void> downloadAndConvertBson(String fileUrl, String modId) async {
      try {
        final response = await http.get(Uri.parse(fileUrl));
        if (response.statusCode != 200) {
          debugPrint('Failed to download BSON file');
          return;
        }

        // Create BsonBinary from the response bytes
        final bsonBinary = BsonBinary.from(response.bodyBytes);

        // Deserialize the BSON data
        final decodedData = BsonCodec.deserialize(bsonBinary);

        // Convert to pretty-printed JSON
        final jsonString =
            const JsonEncoder.withIndent('  ').convert(decodedData);

        // Save JSON to disk
        final filePath = '$workshopDir/test/$modId.json'; // TODO remove /test/
        final file = File(filePath);

        // Create directory if it doesn't exist
        await file.parent.create(recursive: true); // TODO remove

        await file.writeAsString(jsonString);

        debugPrint('JSON saved to: $filePath');
      } catch (e) {
        debugPrint('Error processing BSON file: $e');
      }
    }

    final textController = useTextEditingController();
    final downloading = useState(false);

    // TODO add blur
    return AlertDialog(
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
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Enter ID',
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
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

                          final consumerAppId = fileDetails['consumer_app_id'];
                          if (consumerAppId == 286160) {
                            final fileUrl = fileDetails['file_url'];
                            final previewUrl = fileDetails['preview_url'];

                            await downloadAndConvertBson(fileUrl, modId);
                            await downloadAndResizeImage(previewUrl, modId);
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          } else {
                            debugPrint(
                                'Consumer app ID does not match. Expected: 286160, Got: $consumerAppId');
                          }
                        } catch (e) {
                          debugPrint('Error: $e');

                          // TODO add show snackbar for errors
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
    );
  }
}
