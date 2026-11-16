import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'android_tags.dart';
import 'tags.dart';

void main() {
  runApp(ITagApp(gateway: AndroidTagGateway()));
}

class ITagApp extends StatelessWidget {
  const ITagApp({super.key, required this.gateway});

  final TagGateway gateway;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) {
      final colors = ColorScheme.fromSeed(
        seedColor: const Color(0xFF005E55),
        brightness: brightness,
      );
      return ThemeData(
        colorScheme: colors,
        scaffoldBackgroundColor: colors.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: colors.surface,
          scrolledUnderElevation: 0,
        ),
        visualDensity: VisualDensity.standard,
      );
    }

    return MaterialApp(
      title: 'iTAG',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: _Home(gateway: gateway),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({required this.gateway});

  final TagGateway gateway;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  late final _controller = TagController(widget.gateway);
  late final AppLifecycleListener _lifecycle;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (!_adding) unawaited(_controller.resume());
      },
    );
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    _adding = true;
    final tag = await Navigator.of(context).push<Tag>(
      MaterialPageRoute(
        builder: (context) => _ScanPage(controller: _controller),
      ),
    );
    _adding = false;
    await _controller.stopScan();
    if (mounted && tag != null) await _rename(tag, isNew: true);
  }

  Future<void> _rename(Tag tag, {bool isNew = false}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(tag: tag, isNew: isNew),
    );
    if (mounted && name != null) await _controller.rename(tag, name);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        final colors = Theme.of(context).colorScheme;
        final style = Theme.of(context).textTheme;
        final tags = _controller.tags;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              'iTAG',
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            actions: [
              IconButton(
                tooltip: '添加标签',
                onPressed: _controller.busy ? null : _add,
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  children: [
                    Text(
                      '我的物品',
                      style: style.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_controller.error case final error?) ...[
                      _Message(error),
                      const SizedBox(height: 16),
                    ],
                    if (_controller.loading)
                      const Center(child: CircularProgressIndicator())
                    else if (tags.isEmpty)
                      _EmptyState(onAdd: _controller.busy ? null : _add)
                    else
                      for (final tag in tags) ...[
                        _TagCard(
                          key: ValueKey(tag.id),
                          tag: tag,
                          controller: _controller,
                          onRename: () => _rename(tag),
                        ),
                        const SizedBox(height: 12),
                      ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 112,
            height: 112,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primaryContainer.withValues(alpha: 0.48),
            ),
            child: CircleAvatar(
              radius: 39,
              backgroundColor: colors.primaryContainer,
              foregroundColor: colors.onPrimaryContainer,
              child: const Icon(Icons.sell_outlined, size: 36),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '添加第一个标签',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '将 iTAG 挂在耳机盒或钥匙上，需要时让它响铃。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加标签'),
          ),
        ],
      ),
    );
  }
}

class _TagCard extends StatelessWidget {
  const _TagCard({
    super.key,
    required this.tag,
    required this.controller,
    required this.onRename,
  });

  final Tag tag;
  final TagController controller;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final connected = controller.connectedId == tag.id;
    final connecting = controller.connectingId == tag.id;
    final disconnecting = connected && controller.disconnecting;
    final battery = connected ? controller.link?.battery : null;
    final canRing = connected && controller.link?.canRing == true;
    final controlsEnabled = !controller.busy;
    final status = connecting
        ? '连接中…'
        : disconnecting
        ? '断开中…'
        : connected
        ? '已连接'
        : '未连接';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
      decoration: BoxDecoration(
        color: connected ? colors.surfaceContainerLow : colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: connected ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: connected
                    ? colors.primaryContainer
                    : colors.surfaceContainerHighest,
                foregroundColor: connected
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
                child: const Icon(Icons.sell_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tag.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      status,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: connected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '管理 ${tag.name}',
                enabled: controlsEnabled,
                onSelected: (choice) {
                  if (choice == 'rename') {
                    onRename();
                  } else {
                    unawaited(controller.disconnect());
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'rename', child: Text('重命名')),
                  if (connected)
                    const PopupMenuItem(
                      value: 'disconnect',
                      child: Text('断开连接'),
                    ),
                ],
              ),
            ],
          ),
          if (connecting || disconnecting) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ] else if (connected) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.battery_std_outlined,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    battery == null ? '电量暂不可用' : '电量 $battery%',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (canRing) ...[
              FilledButton.icon(
                onPressed: controlsEnabled && !controller.alertRequested
                    ? () => controller.sendAlert(true)
                    : null,
                icon: const Icon(Icons.volume_up_outlined),
                label: const Text('响铃'),
              ),
              OutlinedButton.icon(
                onPressed: controlsEnabled
                    ? () => controller.sendAlert(false)
                    : null,
                icon: const Icon(Icons.volume_off_outlined),
                label: const Text('停止响铃'),
              ),
              if (controller.sendingAlert || controller.alertRequested)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    controller.sendingAlert ? '正在发送指令…' : '响铃指令已发送',
                    textAlign: TextAlign.center,
                  ),
                ),
            ] else
              const Text('此标签未提供响铃控制。'),
          ] else
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton(
                onPressed: controlsEnabled
                    ? () => controller.connect(tag)
                    : null,
                child: const Text('连接'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScanPage extends StatefulWidget {
  const _ScanPage({required this.controller});

  final TagController controller;

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.startScan());
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) => Scaffold(
        appBar: AppBar(title: const Text('添加标签')),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  Text(
                    '附近的标签',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text('长按标签约 3 秒，听到两声提示音后将它靠近手机。'),
                  const SizedBox(height: 20),
                  if (controller.error case final error?) ...[
                    _Message(error),
                    const SizedBox(height: 12),
                  ],
                  if (controller.scanning) ...[
                    const LinearProgressIndicator(semanticsLabel: '正在搜索附近的标签'),
                    const SizedBox(height: 12),
                    const Text('正在搜索…'),
                  ] else if (controller.nearby.isEmpty &&
                      controller.error == null)
                    const Text('未发现标签。请确认标签已开机后重试。'),
                  for (final tag in controller.nearby)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bluetooth_rounded),
                      title: Text(tag.name),
                      subtitle: Text(tag.id),
                      trailing: controller.connectingId == tag.id
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : TextButton(
                              onPressed: controller.busy
                                  ? null
                                  : () => _select(tag),
                              child: const Text('连接'),
                            ),
                    ),
                  if (!controller.scanning)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        onPressed: controller.busy
                            ? null
                            : controller.startScan,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新搜索'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _select(Tag tag) async {
    final controller = widget.controller;
    final isNew = !controller.tags.any((saved) => saved.id == tag.id);
    final connected = await controller.connect(tag);
    if (mounted && connected) Navigator.of(context).pop(isNew ? tag : null);
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.tag, required this.isNew});

  final Tag tag;
  final bool isNew;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.tag.customName ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_name.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isNew ? '给物品取个名字' : '重命名'),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 32,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        decoration: const InputDecoration(labelText: '物品名称', hintText: '例如：耳机'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.isNew ? '跳过' : '取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(message, style: TextStyle(color: colors.onErrorContainer)),
      ),
    );
  }
}
