import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'other_profile_screen.dart'; // YENİ: Başka profil sayfasını import ettik

class FollowListScreen extends StatefulWidget {
  final String userId;
  final String title;
  final bool isFollowers;

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.title,
    required this.isFollowers
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  final _supabase = Supabase.instance.client;
  List users = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchList();
  }

  Future<void> _fetchList() async {
    try {
      final String columnToMatch = widget.isFollowers ? 'following_id' : 'follower_id';
      final String columnToSelect = widget.isFollowers ? 'follower_id' : 'following_id';

      final res = await _supabase
          .from('follows')
          .select('profiles!follows_${columnToSelect}_fkey(id, username)')
          .eq(columnToMatch, widget.userId);

      if (mounted) {
        setState(() {
          users = (res as List).map((item) => item['profiles']).toList();
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("List load error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14181C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14181C),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.white),
            onPressed: () => Navigator.pop(context)
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E054)))
          : users.isEmpty
          ? Center(child: Text("No ${widget.title.toLowerCase()} yet.", style: const TextStyle(color: Colors.white24)))
          : ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: users.length,
        separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
        itemBuilder: (context, index) {
          final user = users[index];
          final String uName = user['username'] ?? "User";

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF2C3440),
              child: Text(uName[0].toUpperCase(), style: const TextStyle(color: Color(0xFF00E054), fontWeight: FontWeight.bold)),
            ),
            title: Text(uName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 12),

            // ARTIK BURASI ÇALIŞIYOR!
            onTap: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (c) => OtherUserProfileScreen(userId: user['id'])
                  )
              );
            },
          );
        },
      ),
    );
  }
}