import 'package:material_ui/material_ui.dart';
import 'package:hw02_message_board/models/app_user.dart';
import 'package:hw02_message_board/models/message.dart';
import 'package:hw02_message_board/services/auth_service.dart';
import 'package:hw02_message_board/services/board_service.dart';

/// Live message board for a signed-in [profile].
class BoardScreen extends StatefulWidget {
  const BoardScreen({
    super.key,
    required this.profile,
    required this.auth,
    required this.board,
  });

  final AppUser profile;
  final AuthService auth;
  final BoardService board;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  /// Created once in [initState] so rebuilds do not open new Firestore reads.
  late final Stream<List<Message>> _messageStream;

  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// Snapshot order, used by the rules-check probes.
  List<Message> _latest = const [];

  int _renderedCount = 0;
  bool _busy = false;

  /// Reused across send retries until [BoardService.postMessage] succeeds.
  String? _pendingId;

  @override
  void initState() {
    super.initState();
    _messageStream = widget.board.messageBoard();
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = widget.profile;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vault Board'),
            Text(
              'Signed in as ${profile.displayName} · ${profile.role}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Rules check',
            onPressed: _openRulesCheck,
            icon: const Icon(Icons.shield_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _confirmSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: _messageStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _BoardStatus(
                    icon: Icons.error_outline,
                    iconColor: theme.colorScheme.error,
                    title: snapshot.error.toString(),
                    detail: 'Pull down or reopen to retry',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!;
                _latest = messages;
                final ordered = _oldestFirst(messages);
                _scrollIfGrew(ordered.length);

                if (ordered.isEmpty) {
                  return _BoardStatus(
                    key: const Key('empty-board'),
                    icon: Icons.forum_outlined,
                    iconColor: theme.colorScheme.primary,
                    title: 'The board is empty',
                    detail: 'Be the first to post a message.',
                  );
                }

                return ListView.separated(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: ordered.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final message = ordered[index];
                    return _MessageCard(
                      message: message,
                      isMine: message.authorUid == profile.uid,
                      onEdit: () => _editMessage(message),
                      onDelete: () => _deleteMessage(message),
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          _composerBar(theme),
        ],
      ),
    );
  }

  Widget _composerBar(ThemeData theme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('composer-field'),
                controller: _composer,
                enabled: !_busy,
                maxLength: 500,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: _busy ? null : (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Write a message…',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: IconButton.filled(
                key: const Key('send-button'),
                tooltip: 'Send',
                onPressed: _busy ? null : _send,
                icon: _busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.send),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollIfGrew(int count) {
    final grew = count > _renderedCount;
    _renderedCount = count;
    if (!grew) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    if (_busy) return;
    final text = _composer.text.trim();
    if (text.isEmpty) {
      _snack('Message cannot be empty');
      return;
    }
    if (text.length > 500) {
      _snack('Message text must be 1–500 characters.');
      return;
    }

    setState(() => _busy = true);
    _pendingId ??= widget.board.newMessageId();
    final messageId = _pendingId!;
    try {
      final created = await widget.board.postMessage(
        messageId: messageId,
        authorUid: widget.profile.uid,
        authorName: widget.profile.displayName,
        text: text,
      );
      if (!mounted) return;
      _pendingId = null;
      _composer.clear();
      if (!created) {
        _snack('Already posted (duplicate ignored)');
      }
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editMessage(Message message) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _EditMessageDialog(
        initialText: message.text,
        onSave: (text) =>
            widget.board.editMessage(messageId: message.id, newText: text),
      ),
    );
    if (saved == true && mounted) {
      _snack('Message updated');
    }
  }

  Future<void> _deleteMessage(Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message'),
        content: const Text('Delete this message? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.board.deleteMessage(messageId: message.id);
      if (!mounted) return;
      _snack('Message deleted');
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString());
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Sign out of Vault Board?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.auth.signOut();
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString());
    }
  }

  void _openRulesCheck() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _RulesSheet(
        onEditOther: () => _probeOther(widget.board.probeCrossUserUpdate),
        onDeleteOther: () => _probeOther(widget.board.probeCrossUserDelete),
        onForge: () => widget.board.probeForgedCreate('someone-else-uid'),
      ),
    );
  }

  /// Runs [probe] against the first snapshot message from another author.
  Future<String> _probeOther(Future<String> Function(String id) probe) {
    for (final message in _latest) {
      if (message.authorUid != widget.profile.uid) {
        return probe(message.id);
      }
    }
    return Future.value('Need a message from another user first');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.message,
    required this.isMine,
    required this.onEdit,
    required this.onDelete,
  });

  final Message message;
  final bool isMine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        message.authorName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isMine)
                        const Chip(
                          label: Text('(you)'),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
                if (isMine)
                  PopupMenuButton<String>(
                    tooltip: 'Message actions',
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(message.text),
            const SizedBox(height: 8),
            Text(
              _stamp(message),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardStatus extends StatelessWidget {
  const _BoardStatus({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: iconColor),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edit dialog. Pops `true` after [onSave] succeeds.
class _EditMessageDialog extends StatefulWidget {
  const _EditMessageDialog({required this.initialText, required this.onSave});

  final String initialText;
  final Future<void> Function(String text) onSave;

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final TextEditingController _controller;
  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Message cannot be empty');
      return;
    }
    if (text.length > 500) {
      setState(() => _error = 'Message text must be 1–500 characters.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(text);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit message'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_saving,
        maxLength: 500,
        minLines: 1,
        maxLines: 6,
        decoration: InputDecoration(
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// Firestore denial probes. The returned string is the evidence line.
class _RulesSheet extends StatefulWidget {
  const _RulesSheet({
    required this.onEditOther,
    required this.onDeleteOther,
    required this.onForge,
  });

  final Future<String> Function() onEditOther;
  final Future<String> Function() onDeleteOther;
  final Future<String> Function() onForge;

  @override
  State<_RulesSheet> createState() => _RulesSheetState();
}

class _RulesSheetState extends State<_RulesSheet> {
  var _running = false;
  String _result = '';

  Future<void> _run(String label, Future<String> Function() probe) async {
    setState(() => _running = true);
    try {
      final value = await probe();
      if (!mounted) return;
      setState(() {
        _running = false;
        _result = '$label\n$value';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _result = '$label\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resultColor = _resultColor(theme, _result);

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Rules check (Firestore is the gate)',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'These calls skip the client checks. A denial means the security rules held.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _running
                  ? null
                  : () =>
                        _run('Edit other user\'s message:', widget.onEditOther),
              child: const Text("Try editing someone else's message"),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _running
                  ? null
                  : () => _run(
                      'Delete other user\'s message:',
                      widget.onDeleteOther,
                    ),
              child: const Text("Try deleting someone else's message"),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _running
                  ? null
                  : () => _run('Post with forged authorUid:', widget.onForge),
              child: const Text('Try posting as another user'),
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _running
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : SelectableText(
                        _result,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          color: resultColor,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pending server timestamps sort after dated messages so "sending…" stays at the bottom.
List<Message> _oldestFirst(List<Message> messages) {
  final ranked = <({int index, Message message})>[
    for (var i = 0; i < messages.length; i++) (index: i, message: messages[i]),
  ];
  ranked.sort((a, b) {
    final byTime = _compareCreated(a.message.createdAt, b.message.createdAt);
    if (byTime != 0) return byTime;
    return a.index.compareTo(b.index);
  });
  return [for (final row in ranked) row.message];
}

int _compareCreated(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

String _stamp(Message message) {
  final when = message.createdAt == null
      ? 'sending…'
      : _formatTimestamp(message.createdAt!);
  if (message.isEdited) return '$when · edited';
  return when;
}

String _formatTimestamp(DateTime time) {
  final local = time.toLocal();
  final hour24 = local.hour;
  final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = hour24 >= 12 ? 'PM' : 'AM';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[local.month - 1]} ${local.day}, $hour:$minute $period';
}

Color? _resultColor(ThemeData theme, String result) {
  if (result.isEmpty) return theme.colorScheme.onSurfaceVariant;
  final dark = theme.brightness == Brightness.dark;
  if (result.contains('DENIED by Firestore')) {
    return dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828);
  }
  return dark ? const Color(0xFFA5D6A7) : const Color(0xFF2E7D32);
}
