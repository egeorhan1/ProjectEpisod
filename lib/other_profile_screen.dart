import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_list_screen.dart';
import 'follow_list_screen.dart';

class OtherUserProfileScreen extends StatefulWidget {
  final String userId; // Görüntüleyeceğimiz kişinin ID'si

  const OtherUserProfileScreen({super.key, required this.userId});

  @override
  State<OtherUserProfileScreen> createState() => _OtherUserProfileScreenState();
}

class _OtherUserProfileScreenState extends State<OtherUserProfileScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? profileData;

  int watchedCount = 0;
  int likedCount = 0;
  int totalEpisodesCount = 0;
  int followersCount = 0;
  int followingCount = 0;

  bool isLoading = true;
  bool isFollowing = false; // Bu kişiyi takip ediyor muyum?

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return;

    try {
      final results = await Future.wait<dynamic>([
        _supabase.from('profiles').select().eq('id', widget.userId).single(),
        _supabase.from('watched_shows').select('*').eq('user_id', widget.userId).count(CountOption.exact),
        _supabase.from('liked_shows').select('*').eq('user_id', widget.userId).count(CountOption.exact),
        _supabase.from('watched_episodes').select('*').eq('user_id', widget.userId).count(CountOption.exact),
        _supabase.from('follows').select('*').eq('following_id', widget.userId).count(CountOption.exact),
        _supabase.from('follows').select('*').eq('follower_id', widget.userId).count(CountOption.exact),
        _supabase.from('follows').select().eq('follower_id', currentUser.id).eq('following_id', widget.userId).maybeSingle(),
      ]);

      if (mounted) {
        setState(() {
          profileData = results[0] as Map<String, dynamic>;
          watchedCount = (results[1] as PostgrestResponse).count ?? 0;
          likedCount = (results[2] as PostgrestResponse).count ?? 0;
          totalEpisodesCount = (results[3] as PostgrestResponse).count ?? 0;
          followersCount = (results[4] as PostgrestResponse).count ?? 0;
          followingCount = (results[5] as PostgrestResponse).count ?? 0;

          isFollowing = results[6] != null;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Other profile load error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _toggleFollow() async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return;

    try {
      if (isFollowing) {
        // TAKİBİ BIRAK
        await _supabase.from('follows').delete().eq('follower_id', currentUser.id).eq('following_id', widget.userId);
        // Bildirimi sil
        await _supabase.from('activities').delete().eq('actor_id', currentUser.id).eq('user_id', widget.userId).eq('action_type', 'follow');

        setState(() { isFollowing = false; followersCount--; });
      } else {
        // TAKİP ET
        await _supabase.from('follows').insert({
          'follower_id': currentUser.id,
          'following_id': widget.userId
        });
        // BİLDİRİM GÖNDER
        await _supabase.from('activities').insert({
          'user_id': widget.userId,
          'actor_id': currentUser.id,
          'action_type': 'follow'
        });

        setState(() { isFollowing = true; followersCount++; });
      }
    } catch (e) {
      debugPrint("Follow error: $e");
    }
  }

  void _openFollowList(String uid, String title, bool isFollowers) {
    Navigator.push(context, MaterialPageRoute(builder: (c) => FollowListScreen(userId: uid, title: title, isFollowers: isFollowers))).then((_) => _loadData());
  }

  // GÜNCELLENDİ: Başkasının listesini doğru ID ile açar
  void _openUserList(String t, String n) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (c) => UserListScreen(
                tableName: t,
                title: n,
                userId: widget.userId // Görüntülenen kişinin ID'sini yolluyoruz
            )
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(backgroundColor: Color(0xFF14181C), body: Center(child: CircularProgressIndicator(color: Color(0xFF00E054))));

    final username = profileData?['username'] ?? "User";
    final currentUser = _supabase.auth.currentUser;
    final isMyProfile = currentUser?.id == widget.userId;

    return Scaffold(
      backgroundColor: const Color(0xFF14181C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
                child: CircleAvatar(
                    radius: 45,
                    backgroundColor: const Color(0xFF2C3440),
                    child: Text(username[0].toUpperCase(), style: const TextStyle(fontSize: 35, color: Color(0xFF00E054), fontWeight: FontWeight.bold))
                )
            ),
            const SizedBox(height: 16),
            Text(username, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),

            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _openFollowList(widget.userId, "Followers", true),
                  child: Text("$followersCount Followers", style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text("•", style: TextStyle(color: Colors.white24, fontSize: 13)),
                ),
                GestureDetector(
                  onTap: () => _openFollowList(widget.userId, "Following", false),
                  child: Text("$followingCount Following", style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (!isMyProfile)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: ElevatedButton(
                  onPressed: _toggleFollow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFollowing ? Colors.transparent : const Color(0xFF00E054),
                    foregroundColor: isFollowing ? Colors.white : Colors.black,
                    side: isFollowing ? const BorderSide(color: Colors.white54) : BorderSide.none,
                    minimumSize: const Size(double.infinity, 45),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Text(isFollowing ? "Following" : "Follow", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),

            const SizedBox(height: 30),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _buildStat("SHOWS", watchedCount.toString()),
              _buildStat("EPISODES", totalEpisodesCount.toString()),
              _buildStat("LIKES", likedCount.toString()),
            ]),

            const SizedBox(height: 40),
            const Divider(color: Colors.white10, height: 1),

            // YENİ: Başkasının listelerini görme menüleri
            _buildMenuTile(
                icon: Icons.remove_red_eye,
                title: "$username's Watched Series",
                count: watchedCount,
                onTap: () => _openUserList("watched_shows", "WATCHED BY $username")
            ),
            _buildMenuTile(
                icon: Icons.favorite,
                title: "$username's Liked Series",
                count: likedCount,
                onTap: () => _openUserList("liked_shows", "LIKED BY $username")
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String l, String v) => Column(children: [Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)), const SizedBox(height: 4), Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 1.2))]);

  Widget _buildMenuTile({required IconData icon, required String title, int? count, required VoidCallback onTap}) => ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.white70, size: 22),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
      trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (count != null) Text(count.toString(), style: const TextStyle(color: Color(0xFF00E054), fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14)
          ]
      )
  );
}