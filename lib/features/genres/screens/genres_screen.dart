import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/browse/widgets/filter_bottom_sheet.dart';

const _teal = Color(0xFF22D3EE);

class GenresScreen extends ConsumerWidget {
  const GenresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genreAsync = ref.watch(genreListProvider);
    final teamAsync  = ref.watch(teamListProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Thể Loại',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Thể loại ──
            const _SectionLabel('Thể loại'),
            const SizedBox(height: 12),
            genreAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: _teal, strokeWidth: 2)),
              error: (_, __) => const Text('Không tải được thể loại', style: TextStyle(color: Colors.grey)),
              data: (genres) => genres.isEmpty
                  ? const Text('Không có thể loại', style: TextStyle(color: Colors.grey))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: genres.map((g) => _NavChip(
                        label: g.name,
                        onTap: () => context.push('/browse', extra: {
                          'genreId': g.id,
                          'label':   g.name,
                        }),
                      )).toList(),
                    ),
            ),

            const SizedBox(height: 28),

            // ── Tag (Nhóm dịch) ──
            const _SectionLabel('Tag'),
            const SizedBox(height: 12),
            teamAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: _teal, strokeWidth: 2)),
              error: (_, __) => const Text('Không tải được tag', style: TextStyle(color: Colors.grey)),
              data: (teams) => teams.isEmpty
                  ? const Text('Không có tag', style: TextStyle(color: Colors.grey))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: teams.map((t) => _NavChip(
                        label: t.name,
                        onTap: () => context.push('/browse', extra: {
                          'teamIds': [t.id],
                          'label':   t.name,
                        }),
                      )).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1E293B),
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NavChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}
