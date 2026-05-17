
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'data/services/wifi_scan_service.dart';
import 'data/services/network_scan_service.dart';
import 'data/services/database_service.dart';
import 'data/services/device_db.dart';
import 'data/services/sensor_service.dart';
import 'services/api_service.dart';
import 'services/local_database.dart';
import 'services/websocket_service.dart';
import 'presentation/blocs/scan/scan_cubit.dart';
import 'presentation/blocs/channel/channel_cubit.dart';
import 'presentation/blocs/device/device_cubit.dart';
import 'presentation/blocs/heatmap/heatmap_cubit.dart';
import 'presentation/blocs/advisor/advisor_cubit.dart';
import 'presentation/blocs/history/history_cubit.dart';
import 'presentation/blocs/security/security_cubit.dart';
import 'presentation/blocs/settings/settings_cubit.dart';
import 'presentation/screens/home_shell.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/security_screen.dart';
import 'presentation/screens/history_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/screens/advisor_screen.dart';
import 'presentation/screens/time_machine_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.card,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Check onboarding
  final prefs = await SharedPreferences.getInstance();
  final onboardingDone =
      prefs.getBool(AppConstants.prefOnboardingDone) ?? false;

  // Load OUI vendor database
  final ouiResolver = OuiResolver();
  try {
    final csv = await rootBundle.loadString('assets/oui.csv');
    await ouiResolver.load(csv);
  } catch (_) {
    // OUI database not bundled – vendor lookup returns 'Unknown'
  }

  // ── Service instantiation ────────────────────────────────────────────────
  final localDb   = LocalDatabase();
  final db        = DatabaseService();
  final deviceDb  = DeviceDb();
  final wifiSvc   = WifiScanService();
  final netSvc    = NetworkScanService();
  final sensorSvc = SensorService();
  final wsSvc     = WebSocketService();

  // ApiService: updated for physical device using PC's LAN IP
  final apiSvc = ApiService(
    localDb,
    baseUrl: 'http://10.123.0.46:8000/api',
  );

  // Connect WebSocket (non-blocking)
  wsSvc.connect();

  runApp(SignalSightApp(
    onboardingDone: onboardingDone,
    db: db,
    deviceDb: deviceDb,
    wifiService: wifiSvc,
    netService: netSvc,
    sensorService: sensorSvc,
    ouiResolver: ouiResolver,
    apiService: apiSvc,
    wsService: wsSvc,
  ));
}

class SignalSightApp extends StatelessWidget {
  final bool onboardingDone;
  final DatabaseService db;
  final DeviceDb deviceDb;
  final WifiScanService wifiService;
  final NetworkScanService netService;
  final SensorService sensorService;
  final OuiResolver ouiResolver;
  final ApiService apiService;
  final WebSocketService wsService;

  const SignalSightApp({
    super.key,
    required this.onboardingDone,
    required this.db,
    required this.deviceDb,
    required this.wifiService,
    required this.netService,
    required this.sensorService,
    required this.ouiResolver,
    required this.apiService,
    required this.wsService,
  });

  @override
  Widget build(BuildContext context) {
    // Instantiate cubits up-front so we can wire siblings
    final scanCubit     = ScanCubit(wifiService, db, apiService);
    final channelCubit  = ChannelCubit(apiService);
    final securityCubit = SecurityCubit(apiService);

    // ── Offline-first wiring: after each scan, push data into siblings ──────
    scanCubit.bindSiblings(
      channelCubit: channelCubit,
      securityCubit: securityCubit,
    );

    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: scanCubit),
        BlocProvider.value(value: channelCubit),
        BlocProvider.value(value: securityCubit),
        BlocProvider(
          create: (_) => DeviceCubit(deviceDb),
        ),
        BlocProvider(
          create: (_) => HeatmapCubit(sensorService, wifiService, db),
        ),
        BlocProvider(
          create: (_) => AdvisorCubit(apiService),
        ),
        BlocProvider(
          create: (_) => HistoryCubit(db, apiService),
        ),
        BlocProvider(
          create: (_) => SettingsCubit(apiService),
        ),
      ],
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, settingsState) {
          return MaterialApp(
            title: 'SignalSight',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark.copyWith(
              colorScheme: AppTheme.dark.colorScheme.copyWith(
                primary: _getAccentColor(settingsState.accentColor),
              ),
            ),
            initialRoute: onboardingDone ? '/home' : '/onboarding',
            routes: {
              '/onboarding':     (_) => const OnboardingScreen(),
              '/home':           (_) => const HomeShell(),
              '/security':       (_) => const SecurityScreen(),
              '/history':        (_) => const HistoryScreen(),
              '/settings':       (_) => const SettingsScreen(),
              '/advisor':        (_) => const AdvisorScreen(),
              '/time_machine':   (_) => const TimeMachineScreen(),
            },
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.noScaling,
                ),
                child: child!,
              );
            },
          );
        },
      ),
    );
  }

  Color _getAccentColor(String name) {
    switch (name) {
      case 'purple': return AppColors.purple;
      case 'emerald': return AppColors.emerald;
      case 'cyan': 
      default: return AppColors.cyan;
    }
  }
}
