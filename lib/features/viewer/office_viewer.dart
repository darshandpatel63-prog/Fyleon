import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';
import 'office_parser.dart';

/// Basic DOCX / XLSX / PPTX preview (text + tables). Formatting is not
/// preserved yet; real Office-level viewing/editing is a later phase.
class OfficeViewerScreen extends StatefulWidget {
  const OfficeViewerScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<OfficeViewerScreen> createState() => _OfficeViewerScreenState();
}

class _OfficeViewerScreenState extends State<OfficeViewerScreen> {
  late final Future<OfficeResult> _future = compute(parseOffice, widget.item.path);
  int _sheet = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<OfficeResult>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final e = snap.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  e is FormatException ? e.message : 'Could not open this file.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final r = snap.data!;
          return Column(
            children: [
              _notice(context),
              Expanded(child: _content(context, r)),
            ],
          );
        },
      ),
    );
  }

  Widget _notice(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        'Basic preview: text and tables only. Layout, images and formatting are not shown yet.',
        style: TextStyle(fontSize: 12.5),
      ),
    );
  }

  Widget _content(BuildContext context, OfficeResult r) {
    switch (widget.item.kind) {
      case FileKind.word:
        return _doc(context, r);
      case FileKind.excel:
        return _sheets(context, r);
      case FileKind.powerpoint:
        return _slides(context, r);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _doc(BuildContext context, OfficeResult r) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
          ),
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final para in r.paragraphs)
                  Padding(
                    padding: EdgeInsets.only(bottom: para.level > 0 ? 10 : 8, top: para.level > 0 ? 8 : 0),
                    child: Text(
                      para.text.isEmpty ? ' ' : para.text,
                      style: para.level == 0
                          ? theme.bodyMedium?.copyWith(height: 1.5)
                          : theme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: (26 - para.level * 2).toDouble(),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _slides(BuildContext context, OfficeResult r) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      itemCount: r.slides.length,
      itemBuilder: (context, i) {
        final s = r.slides[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Slide ${s.number}', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 8),
              if (s.lines.isEmpty)
                Text('(no text)', style: TextStyle(color: scheme.onSurfaceVariant))
              else ...[
                Text(s.lines.first, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                for (final line in s.lines.skip(1))
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text(line)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sheets(BuildContext context, OfficeResult r) {
    final scheme = Theme.of(context).colorScheme;
    final sheet = r.sheets[_sheet.clamp(0, r.sheets.length - 1)];
    final cols = sheet.rows.fold<int>(0, (m, row) => row.length > m ? row.length : m);
    const cellW = 120.0;
    const rowHeaderW = 44.0;
    String colName(int i) {
      var n = i;
      var s = '';
      do {
        s = String.fromCharCode(65 + n % 26) + s;
        n = n ~/ 26 - 1;
      } while (n >= 0);
      return s;
    }

    return Column(
      children: [
        if (r.sheets.length > 1)
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: r.sheets.length,
              separatorBuilder: (context, i) => const SizedBox(width: 8),
              itemBuilder: (context, i) => ChoiceChip(
                label: Text(r.sheets[i].name),
                selected: i == _sheet,
                onSelected: (_) => setState(() => _sheet = i),
              ),
            ),
          ),
        if (sheet.truncated)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('Showing the first 300 rows and 40 columns.', style: TextStyle(fontSize: 12)),
          ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: rowHeaderW + cols * cellW,
              child: ListView.builder(
                itemCount: sheet.rows.length + 1,
                itemBuilder: (context, i) {
                  final header = i == 0;
                  final row = header ? const <String>[] : sheet.rows[i - 1];
                  return Container(
                    decoration: BoxDecoration(
                      color: header ? scheme.primaryContainer.withValues(alpha: 0.5) : null,
                      border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: rowHeaderW,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                            child: Text(header ? '' : '$i', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
                          ),
                        ),
                        for (var c = 0; c < cols; c++)
                          SizedBox(
                            width: cellW,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                              child: Text(
                                header ? colName(c) : (c < row.length ? row[c] : ''),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: header ? FontWeight.w700 : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
