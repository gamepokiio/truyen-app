import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _accent = Color(0xFF1E3A8A); // navy

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    if (loc.startsWith('/library'))       return 0;
    if (loc.startsWith('/home'))          return 1;
    if (loc.startsWith('/ranking'))       return 2;
    if (loc.startsWith('/notifications')) return 3;
    if (loc.startsWith('/profile'))       return 4;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            );
          }),
        ),
        child: NavigationBar(
        selectedIndex: idx,
        height: 64,
        indicatorColor: _accent.withValues(alpha: 0.15),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black12,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/library');       break;
            case 1: context.go('/home');          break;
            case 2: context.go('/ranking');       break;
            case 3: context.go('/notifications'); break;
            case 4: context.go('/profile');       break;
          }
        },
        destinations: [
          NavigationDestination(
            icon:         Icon(Icons.bookmarks_outlined,        size: 24),
            selectedIcon: Icon(Icons.bookmarks_rounded,         size: 24, color: _accent),
            label: 'Tủ truyện',
          ),
          NavigationDestination(
            icon:         Icon(Icons.home_outlined,             size: 24),
            selectedIcon: Icon(Icons.home_rounded,              size: 24, color: _accent),
            label: 'Trang chủ',
          ),
          NavigationDestination(
            icon:         Icon(Icons.leaderboard_outlined,      size: 24),
            selectedIcon: Icon(Icons.leaderboard_rounded,       size: 24, color: _accent),
            label: 'Xếp Hạng',
          ),
          NavigationDestination(
            icon:         Badge(smallSize: 8, child: Icon(Icons.notifications_outlined,  size: 24)),
            selectedIcon: Badge(smallSize: 8, child: Icon(Icons.notifications_rounded,   size: 24, color: _accent)),
            label: 'Thông Báo',
          ),
          NavigationDestination(
            icon:         Icon(Icons.person_outline,            size: 24),
            selectedIcon: Icon(Icons.person_rounded,            size: 24, color: _accent),
            label: 'Tài Khoản',
          ),
        ],
        ),
      ),
    );
  }
}
