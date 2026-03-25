import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_list_screen.dart';
import 'show_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? profileData;
  int watchedCount = 0;
  int likedCount = 0;
  int totalEpisodesCount = 0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final results = await Future.wait<dynamic>([
        _supabase.from('profiles').select().eq('id', user.id).single(),
        _supabase.from('watched_shows').select('*').count(CountOption.exact),
        _supabase.from('liked_shows').select('*').count(CountOption.exact),
        _supabase.from('watched_episodes').select('*').count(CountOption.exact),
      ]);

      if (mounted) {
        setState(() {
          profileData = results[0] as Map<String, dynamic>;
          watchedCount = (results[1] as PostgrestResponse).count ?? 0;
          likedCount = (results[2] as PostgrestResponse).count ?? 0;
          totalEpisodesCount = (results[3] as PostgrestResponse).count ?? 0;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(backgroundColor: Color(0xFF14181C), body: Center(child: CircularProgressIndicator(color: Color(0xFF00E054))));

    final username = profileData?['username'] ?? "User";

    return Scaffold(
      backgroundColor: const Color(0xFF14181C),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, actions: [IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent), onPressed: () => _supabase.auth.signOut())]),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: const Color(0xFF00E054),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Center(child: CircleAvatar(radius: 45, backgroundColor: const Color(0xFF2C3440), child: Text(username[0].toUpperCase(), style: const TextStyle(fontSize: 35, color: Color(0xFF00E054), fontWeight: FontWeight.bold)))),
              const SizedBox(height: 16),
              Text(username, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 30),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _buildStat("SHOWS", watchedCount.toString()),
                _buildStat("EPISODES", totalEpisodesCount.toString()),
                _buildStat("LIKES", likedCount.toString()),
              ]),
              const SizedBox(height: 40),
              const Divider(color: Colors.white10, height: 1),
              _buildMenuTile(icon: Icons.remove_red_eye, title: "Watched Series", count: watchedCount, onTap: () => _openUserList("watched_shows", "WATCHED SERIES")),
              _buildMenuTile(icon: Icons.favorite, title: "Liked Series", count: likedCount, onTap: () => _openUserList("liked_shows", "LIKED SERIES")),
            ],
          ),
        ),
      ),
    );
  }

  void _openUserList(String t, String n) {
    Navigator.push(context, MaterialPageRoute(builder: (c) => UserListScreen(tableName: t, title: n))).then((_) => _loadData());
  }

  Widget _buildStat(String l, String v) => Column(children: [Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)), const SizedBox(height: 4), Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 1.2))]);

  Widget _buildMenuTile({required IconData icon, required String title, int? count, required VoidCallback onTap}) => ListTile(onTap: onTap, leading: Icon(icon, color: Colors.white70, size: 22), title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)), trailing: Row(mainAxisSize: MainAxisSize.min, children: [if (count != null) Text(count.toString(), style: const TextStyle(color: Color(0xFF00E054), fontWeight: FontWeight.bold)), const SizedBox(width: 8), const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14)]));
}