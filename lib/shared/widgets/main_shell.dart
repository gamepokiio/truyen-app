import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _teal = Color(0xFF22D3EE);

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    if (loc.startsWith('/library')) return 0;
    if (loc.startsWith('/home'))    return 1;
    if (loc.startsWith('/ranking')) return 2;
    if (loc.startsWith('/profile')) return 3;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        indicatorColor: _teal.withValues(alpha: 0.15),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black12,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/library'); break;
            case 1: context.go('/home');    break;
            case 2: context.go('/ranking'); break;
            case 3: context.go('/profile'); break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon:         Icon(Icons.bookmarks_outlined,   size: 24),
            selectedIcon: Icon(Icons.bookmarks_rounded,    size: 24, color: _teal),
            label: 'Tủ truyện',
          ),
          NavigationDestination(
            icon:         Icon(Icons.home_outlined,        size: 24),
            selectedIcon: Icon(Icons.home_rounded,         size: 24, color: _teal),
            label: 'Trang chủ',
          ),
          NavigationDestination(
            icon:         Icon(Icons.leaderboard_outlined, size: 24),
            selectedIcon: Icon(Icons.leaderboard_rounded,  size: 24, color: _teal),
            label: 'Xếp Hạng',
          ),
          NavigationDestination(
            icon:         Icon(Icons.person_outline,       size: 24),
            selectedIcon: Icon(Icons.person_rounded,       size: 24, color: _teal),
            label: 'Tài Khoản',
          ),
        ],
      ),
    );
  }
}
