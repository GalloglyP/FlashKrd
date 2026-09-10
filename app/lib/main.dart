import 'package:flashkrd/app_state.dart';
import 'package:flashkrd/decks_screen.dart';
import 'package:flashkrd/store.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(Store());
  await state.load();
  runApp(FlashKrdApp(state: state));
}

class FlashKrdApp extends StatelessWidget {
  const FlashKrdApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlashKrd',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF1E4FB8),
          onPrimary: Colors.white,
          surface: Color(0xFFF6F6F2),
          onSurface: Colors.black,
          error: Color(0xFFB00020),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F6F2),
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _NoTransitionsBuilder(),
          },
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFE8E4DA),
          foregroundColor: Colors.black,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
      ),
      home: DecksScreen(state: state),
    );
  }
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
