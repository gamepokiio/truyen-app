import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/ad_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await AdService.instance.initialize();
  runApp(const ProviderScope(child: TruyenApp()));
}

class TruyenApp extends ConsumerWidget {
  const TruyenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'TruyenCV',
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}
