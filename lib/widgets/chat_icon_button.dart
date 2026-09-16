import 'package:flutter/material.dart';
import '../data/app_session.dart';
import '../data/chat_store.dart';
import '../theme/app_theme.dart';

class ChatIconButton extends StatefulWidget {
  final String requestId;
  final VoidCallback onTap;
  const ChatIconButton({super.key, required this.requestId, required this.onTap});

  @override
  State<ChatIconButton> createState() => _ChatIconButtonState();
}

class _ChatIconButtonState extends State<ChatIconButton> {
  final _store = ChatStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChange);
  }

  @override
  void dispose() {
    _store.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final role = AppSession.instance.currentRole;
    final unread = _store.unreadCountFor(widget.requestId, role);

    return Tooltip(
      message: unread > 0 ? 'Messages, $unread unread' : 'Messages',
      child: InkResponse(
        onTap: widget.onTap,
        radius: 22,
        // A 44-point target around the 36-point circle, the same as the call
        // button beside it.
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(Icons.chat_bubble_outline, color: AppColors.info, size: 18),
                ),
                if (unread > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 9, color: AppColors.textlight, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}