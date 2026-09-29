import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PhotoGalleryViewerScreen extends StatefulWidget {
  final List<String> photoPaths;
  final int initialIndex;

  const PhotoGalleryViewerScreen({super.key, required this.photoPaths, this.initialIndex = 0});

  @override
  State<PhotoGalleryViewerScreen> createState() => _PhotoGalleryViewerScreenState();
}

class _PhotoGalleryViewerScreenState extends State<PhotoGalleryViewerScreen> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.photoPaths.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_index + delta).clamp(0, widget.photoPaths.length - 1);
    if (next == _index) return;
    _controller.animateToPage(next, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final multiple = widget.photoPaths.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: multiple ? Text('${_index + 1} / ${widget.photoPaths.length}') : null,
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.photoPaths.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.file(
                  File(widget.photoPaths[i]),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) =>
                      Icon(Icons.broken_image_outlined, color: AppColors.textmedium.withValues(alpha: 0.38), size: 64),
                ),
              ),
            ),
          ),
          if (multiple) ...[
            Positioned(
              left: 8,
              child: _NavArrow(icon: Icons.chevron_left, onTap: _index > 0 ? () => _go(-1) : null),
            ),
            Positioned(
              right: 8,
              child: _NavArrow(icon: Icons.chevron_right, onTap: _index < widget.photoPaths.length - 1 ? () => _go(1) : null),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _NavArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.25 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
          child: Icon(icon, color: AppColors.textmedium, size: 32),
        ),
      ),
    );
  }
}