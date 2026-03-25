import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_config.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'activity_screen.dart';
import 'profile_screen.dart';
import 'auth_screen.dart'; // Yeni oluşturacağımız ekran

void main() async {
  // 1. Flutter bağlamını hazırla
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Supabase'i senin API bilgilerinle uyandır
  await Supabase.initialize(
    url: ApiConfig.supabaseUrl,
    anonKey: ApiConfig.supabaseAnonKey,
  );

  runApp(const EpisodApp());
}

class EpisodApp extends StatelessWidget {
  const EpisodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Episod',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF14181C),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        // Genel yeşil tonlarını tema bazında ayarla
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E054),
          secondary: Color(0xFF00E054),
        ),
      ),
      // 3. Oturum kontrolü yapan ana giriş noktası
      home: const AuthGate(),
    );
  }
}

// OTURUM GEÇİDİ: Giriş yapılıp yapılmadığını kontrol eder
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Eğer bir oturum varsa (session != null) ana ekrana git
        final session = snapshot.data?.session;
        if (session != null) {
          return const MainScreen();
        }
        // Oturum yoksa giriş ekranına yönlendir
        return const AuthScreen();
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const HomeScreen(),
    const SearchScreen(),
    const ActivityScreen(),
    const ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF14181C),
        selectedItemColor: const Color(0xFF00E054),
        unselectedItemColor: Colors.grey,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.flash_on), label: 'Activity'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}