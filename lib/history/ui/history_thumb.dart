import 'dart:io';

import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../data/history_api.dart';

/// A gallery photo, from this phone when saved, else downloaded once and
/// kept. A placeholder while loading, and when it cannot be shown.
class HistoryThumb extends StatefulWidget {
  const HistoryThumb({super.key, required this.history, required this.path, this.size = 56, this.height});

  final HistoryApi history;
  final String? path;
  final double size;

  /// Taller than wide (the item page's photo strip); defaults to [size].
  final double? height;

  @override
  State<HistoryThumb> createState() => _HistoryThumbState();
}

class _HistoryThumbState extends State<HistoryThumb> {
  late Future<File?> _file = _load();

  Future<File?> _load() async {
    final p = widget.path;
    if (p == null) return null;
    try {
      return await widget.history.photo(p);
    } catch (_) {
      return null;
    }
  }

  @override
  void didUpdateWidget(HistoryThumb old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _file = _load();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height ?? widget.size;
    final gap = Container(
      width: widget.size,
      height: h,
      decoration: BoxDecoration(color: WmColors.inert, borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.image_outlined, color: WmColors.textMuted),
    );
    return FutureBuilder<File?>(
      future: _file,
      builder: (context, snap) {
        final f = snap.data;
        if (f == null) return gap;
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(f, width: widget.size, height: h, cacheWidth: (widget.size * MediaQuery.devicePixelRatioOf(context)).round(), fit: BoxFit.cover, errorBuilder: (_, _, _) => gap),
        );
      },
    );
  }
}
