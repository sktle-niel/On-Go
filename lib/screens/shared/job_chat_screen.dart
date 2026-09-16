import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/app_session.dart';
import '../../data/chat_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/photo_gallery_viewer_screen.dart';

class JobChatScreen extends StatefulWidget {
  final String requestId;
  final String otherPartyName;

  const JobChatScreen({super.key, required this.requestId, required this.otherPartyName});

  @override
  State<JobChatScreen> createState() => _JobChatScreenState();
}

class _JobChatScreenState extends State<JobChatScreen> {
  final _store = ChatStore.instance;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  ChatMessage? _replyingTo;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChange);
    // Deferred to after this frame — calling markSeen synchronously here
    // fires notifyListeners() WHILE the navigation transition is still
    // building the widget tree (initState runs during build). Any other
    // ChatIconButton still mounted elsewhere (e.g. on the card you just
    // navigated from) would then try to setState() mid-build and crash
    // with "setState() called during build". Post-frame scheduling lets
    // the current build finish first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _store.markSeen(widget.requestId, AppSession.instance.currentRole);
    });
  }

  @override
  void dispose() {
    _store.removeListener(_onChange);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    // Same reasoning as initState above: a message arriving while this
    // screen is open should clear the badge, but marking it seen must
    // happen after the current build/notify cycle finishes, not inside it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _store.markSeen(widget.requestId, AppSession.instance.currentRole);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    try {
      _store.sendMessage(widget.requestId, text: text, replyToId: _replyingTo?.id);
      _controller.clear();
      setState(() => _replyingTo = null);
      _scrollToBottom();
    } on StateError catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), duration: AppDurations.snackBar));
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      _store.sendMessage(widget.requestId, imagePath: file.path, replyToId: _replyingTo?.id);
      setState(() => _replyingTo = null);
      _scrollToBottom();
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), duration: AppDurations.snackBar));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not attach photo: $e'), duration: AppDurations.snackBar));
    }
  }

  void _showMessageOptions(ChatMessage msg) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (msg.text != null)
              ListTile(
                leading: Icon(Icons.copy, color: AppColors.primary),
                title: const Text('Copy'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: msg.text!));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied'), duration: Duration(milliseconds: 700)),
                  );
                },
              ),
            ListTile(
              leading: Icon(Icons.reply, color: AppColors.primary),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _replyingTo = msg);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _senderLabel(ChatMessage msg) => msg.sender == ChatSender.client ? 'Client' : widget.otherPartyName;

  @override
  Widget build(BuildContext context) {
    final messages = _store.messagesFor(widget.requestId);
    final myRole = AppSession.instance.currentRole;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textmedium,
        title: Text(widget.otherPartyName),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text('Send a message to get started', style: TextStyle(color: AppColors.textdark.withValues(alpha: 0.55), fontSize: 12)),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = (myRole == AppRole.client && msg.sender == ChatSender.client) ||
                          (myRole == AppRole.mechanic && msg.sender == ChatSender.mechanic);
                      final repliedTo = msg.replyToId == null ? null : _store.messageById(widget.requestId, msg.replyToId!);

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: GestureDetector(
                          onLongPress: () => _showMessageOptions(msg),
                          child: Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe ? AppColors.surface.withValues(alpha: 0.55) : AppColors.surface.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (repliedTo != null)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
                                    ),
                                    child: Text(
                                      repliedTo.text ?? (repliedTo.imagePath != null ? 'Photo' : ''),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55)),
                                    ),
                                  ),
                                msg.imagePath != null
                                    ? GestureDetector(
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => PhotoGalleryViewerScreen(photoPaths: [msg.imagePath!]),
                                          ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.file(File(msg.imagePath!), width: 180, fit: BoxFit.cover),
                                        ),
                                      )
                                    : Text(msg.text ?? '', style: TextStyle(fontSize: 13, color: AppColors.textdark)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.background,
              child: Row(
                children: [
                  Container(width: 3, height: 32, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Replying to ${_senderLabel(_replyingTo!)}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        Text(
                          _replyingTo!.text ?? (_replyingTo!.imagePath != null ? 'Photo' : ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Cancel reply',
                    onPressed: () => setState(() => _replyingTo = null),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                // Bottom-aligned, so the buttons stay beside the last line as
                // a long message grows the field upward.
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(Icons.camera_alt_outlined, color: AppColors.textdark.withValues(alpha: 0.55)),
                    tooltip: 'Take a photo',
                    onPressed: () => _pickImage(ImageSource.camera),
                  ),
                  IconButton(
                    icon: Icon(Icons.image_outlined, color: AppColors.textdark.withValues(alpha: 0.55)),
                    tooltip: 'Send a photo',
                    onPressed: () => _pickImage(ImageSource.gallery),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(24)),
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(hintText: 'Message', border: InputBorder.none, isDense: true),
                      ),
                    ),
                  ),
                  // Live only once there is something to send.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) {
                      final empty = value.text.trim().isEmpty;
                      return IconButton(
                        icon: Icon(Icons.send, color: empty ? AppColors.primary.withValues(alpha: 0.4) : AppColors.primary),
                        tooltip: 'Send',
                        onPressed: empty ? null : _send,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}