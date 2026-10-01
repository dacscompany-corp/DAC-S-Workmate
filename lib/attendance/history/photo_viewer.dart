import 'package:flutter/material.dart';

import '../../ui/theme.dart';

/// One attendance photo, full screen: the proof, with whose day and which leg.
class PhotoViewer extends StatelessWidget {
  const PhotoViewer({super.key, required this.image, required this.heading, required this.caption});
  final ImageProvider image;
  final String heading;
  final String caption;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: WmColors.viewerBackdrop,
        body: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('PROOF', style: monoLabel.copyWith(color: Colors.white70)),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(heading, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                Text(caption, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ]),
            ),
            Expanded(
              child: InteractiveViewer(
                child: Center(
                  child: Image(
                    image: image,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Text('No photo yet', style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
}
