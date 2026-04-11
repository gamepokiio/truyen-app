import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/api/novel_api.dart';
import '../../../shared/models/novel_model.dart';
import '../screens/browse_screen.dart';

// ─── Providers (cached per session) ──────────────────────────────────────────

final genreListProvider = FutureProvider<List<NovelTerm>>((ref) async {
  final api = NovelApi(ref.read(cachedDioProvider)); // cached — genre list hiếm thay đổi
  final raw = await api.getGenres(perPage: 100);
  return raw
      .map((g) => NovelTerm(
            id: (g['id'] as num).toInt(),
            name: g['name'] as String? ?? '',
          ))
      .where((g) => g.name.isNotEmpty && !kExcludedGenreIds.contains(g.id))
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
});

final teamListProvider = FutureProvider<List<NovelTerm>>((ref) async {
  final api = NovelApi(ref.read(cachedDioProvider)); // cached
  final raw = await api.getTeams(perPage: 100);
  return raw
      .map((t) => NovelTerm(
            id: (t['id'] as num).toInt(),
            name: t['name'] as String? ?? '',
          ))
      .where((t) => t.name.isNotEmpty)
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
});

// ─── Sort options ──────────────────────────────────────────────────────────────

class _SortOpt {
  final String label;
  final String orderby; // internal key
  final String order;
  const _SortOpt(this.label, this.orderby, this.order);
}

const _sortOpts = [
  _SortOpt('Mới cập nhật', 'modified', 'desc'),
  _SortOpt('Mới đăng',     'date',     'desc'),
  _SortOpt('Lượt đọc',    'views',    'desc'),
  _SortOpt('Đánh giá',    'rating',   'desc'),
  _SortOpt('Tên truyện',  'title',    'asc'),
];

// ─── Status options ───────────────────────────────────────────────────────────

const _statusOpts = [
  ('Đang ra',    'ongoing'),
  ('Hoàn thành', 'completed'),
  ('Tạm dừng',   'source_hiatus'),
];

// ─── Bottom sheet ─────────────────────────────────────────────────────────────

class FilterBottomSheet extends ConsumerStatefulWidget {
  final BrowseFilter currentFilter;
  final ValueChanged<BrowseFilter> onApply;

  const FilterBottomSheet({
    super.key,
    required this.currentFilter,
    required this.onApply,
  });

  @override
  ConsumerState<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends ConsumerState<FilterBottomSheet> {
  late String   _orderby;
  late String   _order;
  late String?  _status;
  late Set<int> _genreIds;
  late Set<int> _teamIds;

  static const _teal = Color(0xFF22D3EE);

  @override
  void initState() {
    super.initState();
    // Chỉ pre-select sort nếu user đã chọn trước đó (không phải default 'modified')
    _orderby  = widget.currentFilter.explicitOrderby ?? '';
    _order    = widget.currentFilter.order;
    _status   = widget.currentFilter.status;
    _genreIds = {
      ...?widget.currentFilter.genreIds,
      if (widget.currentFilter.genreId != null &&
          (widget.currentFilter.genreIds?.isEmpty ?? true))
        widget.currentFilter.genreId!,
    };
    _teamIds = {...?widget.currentFilter.teamIds};
  }

  void _reset() => setState(() {
        _orderby  = '';
        _order    = 'desc';
        _status   = null;
        _teamIds  = {};
        _genreIds = {};
      });

  void _apply() {
    widget.onApply(BrowseFilter(
      orderby:         _orderby.isEmpty ? 'modified' : _orderby,
      explicitOrderby: _orderby.isEmpty ? null : _orderby,
      order:           _order,
      status:          _status,
      genreIds:        _genreIds.isEmpty ? null : _genreIds.toList(),
      teamIds:         _teamIds.isEmpty  ? null : _teamIds.toList(),
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final genreAsync = ref.watch(genreListProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ─────────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // ── Header ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
            child: Row(
              children: [
                const Text('Bộ lọc',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: _reset,
                  child: const Text('Đặt lại',
                      style: TextStyle(color: _teal, fontSize: 13)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Content ────────────────────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sắp xếp
                  _Label('Sắp xếp'),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _sortOpts.map((opt) => _Chip(
                      label: opt.label,
                      selected: _orderby == opt.orderby,
                      onTap: () => setState(() {
                        _orderby = opt.orderby;
                        _order   = opt.order;
                      }),
                    )).toList(),
                  ),
                  const SizedBox(height: 18),
                  // Tình trạng
                  _Label('Tình trạng'),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _statusOpts.map((s) => _Chip(
                      label: s.$1,
                      selected: _status == s.$2,
                      onTap: () => setState(() =>
                          _status = (_status == s.$2) ? null : s.$2),
                    )).toList(),
                  ),
                  const SizedBox(height: 18),
                  // Thể loại
                  Row(
                    children: [
                      _Label('Thể loại'),
                      if (_genreIds.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _teal,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${_genreIds.length}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  genreAsync.when(
                    loading: () => const SizedBox(
                      height: 40,
                      child: Center(
                          child: CircularProgressIndicator(
                              color: _teal, strokeWidth: 2)),
                    ),
                    error: (_, __) => const Text('Không tải được thể loại',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                    data: (genres) => Wrap(
                      spacing: 8, runSpacing: 8,
                      children: genres.map((g) {
                        final sel = _genreIds.contains(g.id);
                        return _Chip(
                          label: g.name,
                          selected: sel,
                          onTap: () => setState(() =>
                              sel ? _genreIds.remove(g.id)
                                  : _genreIds.add(g.id)),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Nhóm dịch
                  _buildTeamSection(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          // ── Apply button ────────────────────────────────────────────────
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 10, 20, MediaQuery.of(context).padding.bottom + 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _apply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Áp dụng',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Team section ──────────────────────────────────────────────────────────

  Widget _buildTeamSection() {
    final teamAsync = ref.watch(teamListProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Label('Tag'),
            if (_teamIds.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: _teal, borderRadius: BorderRadius.circular(10)),
                child: Text('${_teamIds.length}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        teamAsync.when(
          loading: () => const SizedBox(
              height: 40,
              child: Center(
                  child: CircularProgressIndicator(color: _teal, strokeWidth: 2))),
          error: (_, __) => const Text('Không tải được nhóm dịch',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          data: (teams) => teams.isEmpty
              ? const Text('Không có nhóm dịch',
                  style: TextStyle(color: Colors.grey, fontSize: 13))
              : Wrap(
                  spacing: 8, runSpacing: 8,
                  children: teams.map((t) {
                    final sel = _teamIds.contains(t.id);
                    return _Chip(
                      label: t.name,
                      selected: sel,
                      onTap: () => setState(() =>
                          sel ? _teamIds.remove(t.id) : _teamIds.add(t.id)),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF374151))),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  static const _teal = Color(0xFF22D3EE);

  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _teal : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? _teal : Colors.grey.shade200, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.normal,
            color:
                selected ? Colors.white : const Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}
