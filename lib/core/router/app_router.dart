import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/browse/screens/browse_screen.dart';
import '../../features/novel/screens/novel_detail_screen.dart';
import '../../features/reader/screens/reader_screen.dart';
import '../../features/library/screens/library_screen.dart';
import '../../features/ranking/screens/ranking_screen.dart';
import '../../features/search/screens/search_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/genres/screens/genres_screen.dart';
import '../../features/profile/screens/about_screen.dart';
import '../../features/profile/screens/faq_screen.dart';
import '../../shared/widgets/main_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (_, __) => const RegisterScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) => const HomeScreen(),
          ),
          GoRoute(
            path: '/library',
            builder: (_, __) => const LibraryScreen(),
          ),
          GoRoute(
            path: '/ranking',
            builder: (_, __) => const RankingScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const ProfileScreen(),
          ),
        ],
      ),
      // Full-screen routes (no bottom nav) — Store Guidelines
      GoRoute(
        path: '/browse',
        builder: (_, state) {
          final extra = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : null;
          final openFilter = extra?['openFilter'] as bool? ?? false;
          final rawTeamIds = extra?['teamIds'];
          final teamIds = rawTeamIds is List ? rawTeamIds.cast<int>() : null;
          final hasOtherKeys = extra != null &&
              extra.keys.any((k) => k != 'openFilter' && k != 'teamIds');
          BrowseFilter? filter;
          if (hasOtherKeys) {
            filter = BrowseFilter(
              genreId:   extra!['genreId']   as int?,
              genreName: extra['genreName']  as String? ?? extra['genreSlug'] as String?,
              status:    extra['status']     as String?,
              label:     extra['label']      as String?,
              teamIds:   teamIds,
            );
          } else if (teamIds != null) {
            filter = BrowseFilter(
              teamIds: teamIds,
              label:   extra?['label'] as String?,
            );
          }
          return BrowseScreen(initialFilter: filter, openFilter: openFilter);
        },
      ),
      GoRoute(
        path: '/search',
        builder: (_, __) => const SearchScreen(),
      ),
      GoRoute(
        path: '/genres',
        builder: (_, __) => const GenresScreen(),
      ),
      GoRoute(
        path: '/about',
        builder: (_, __) => const AboutScreen(),
      ),
      GoRoute(
        path: '/faq',
        builder: (_, __) => const FaqScreen(),
      ),
      GoRoute(
        path: '/novel/:id',
        builder: (_, state) {
          final id = int.parse(state.pathParameters['id']!);
          return NovelDetailScreen(novelId: id);
        },
      ),
      GoRoute(
        path: '/reader/:novelId/:chapterId',
        builder: (_, state) {
          final novelId   = int.parse(state.pathParameters['novelId']!);
          final chapterId = int.parse(state.pathParameters['chapterId']!);
          final extra = state.extra as Map<String, dynamic>?;
          return ReaderScreen(
            novelId:      novelId,
            chapterId:    chapterId,
            chapterTitle:  extra?['chapterTitle']  as String? ?? '',
            chapterNumber: extra?['chapterNumber'] as int?    ?? 0,
            // Optional pre-computed adjacent — giúp skip API calls
            prevChapterId:    extra?['prevChapterId']    as int?,
            prevChapterTitle: extra?['prevChapterTitle'] as String?,
            prevChapterNum:   extra?['prevChapterNum']   as int?,
            nextChapterId:    extra?['nextChapterId']    as int?,
            nextChapterTitle: extra?['nextChapterTitle'] as String?,
            nextChapterNum:   extra?['nextChapterNum']   as int?,
          );
        },
      ),
    ],
  );
});
