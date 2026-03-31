import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_list_screen.dart';
import 'follow_list_screen.dart';
import 'theme/app_colors.dart';
import 'widgets/episod_user_avatar.dart';

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

  int followersCount = 0;
  int followingCount = 0;

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
        // 1. Profil bilgilerini çek
        _supabase.from('profiles').select().eq('id', user.id).single(),

        // 2. Sadece bu kullanıcının izlediği dizileri say
        _supabase
            .from('watched_shows')
            .select('*')
            .eq('user_id', user.id)
            .count(CountOption.exact),

        // 3. Sadece bu kullanıcının beğendiği dizileri say
        _supabase
            .from('liked_shows')
            .select('*')
            .eq('user_id', user.id)
            .count(CountOption.exact),

        // 4. Sadece bu kullanıcının izlediği bölümleri say
        _supabase
            .from('watched_episodes')
            .select('*')
            .eq('user_id', user.id)
            .count(CountOption.exact),

        // 5. Takipçi ve Takip Edilen sayıları (Zaten ID ile filtrelenmişti)
        _supabase
            .from('follows')
            .select('*')
            .eq('following_id', user.id)
            .count(CountOption.exact),
        _supabase
            .from('follows')
            .select('*')
            .eq('follower_id', user.id)
            .count(CountOption.exact),
      ]);

      if (mounted) {
        setState(() {
          profileData = results[0] as Map<String, dynamic>;
          watchedCount = (results[1] as PostgrestResponse).count ?? 0;
          likedCount = (results[2] as PostgrestResponse).count ?? 0;
          totalEpisodesCount = (results[3] as PostgrestResponse).count ?? 0;
          followersCount = (results[4] as PostgrestResponse).count ?? 0;
          followingCount = (results[5] as PostgrestResponse).count ?? 0;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Profile load error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading)
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );

    final username = profileData?['username'] ?? "User";
    final userId = _supabase.auth.currentUser!.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.error),
            onPressed: () => _supabase.auth.signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.accent,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Center(
                child: EpisodUserAvatar(
                  username: username,
                  radius: 45,
                  fontSize: 35,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                username,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),

              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => _openFollowList(userId, "Followers", true),
                    child: Text(
                      "$followersCount Followers",
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      "•",
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _openFollowList(userId, "Following", false),
                    child: Text(
                      "$followingCount Following",
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat("SHOWS", watchedCount.toString()),
                  _buildStat("EPISODES", totalEpisodesCount.toString()),
                  _buildStat("LIKES", likedCount.toString()),
                ],
              ),
              const SizedBox(height: 40),
              const Divider(color: AppColors.divider, height: 1),
              _buildMenuTile(
                icon: Icons.remove_red_eye,
                title: "Watched Series",
                count: watchedCount,
                onTap: () => _openUserList("watched_shows", "WATCHED SERIES"),
              ),
              _buildMenuTile(
                icon: Icons.favorite,
                title: "Liked Series",
                count: likedCount,
                onTap: () => _openUserList("liked_shows", "LIKED SERIES"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openUserList(String t, String n) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => UserListScreen(tableName: t, title: n),
      ),
    ).then((_) => _loadData());
  }

  void _openFollowList(String uid, String title, bool isFollowers) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => FollowListScreen(
          userId: uid,
          title: title,
          isFollowers: isFollowers,
        ),
      ),
    ).then((_) => _loadData());
  }

  Widget _buildStat(String l, String v) => Column(
    children: [
      Text(
        v,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        l,
        style: const TextStyle(
          fontSize: 10,
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    ],
  );

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    int? count,
    required VoidCallback onTap,
  }) => ListTile(
    onTap: onTap,
    leading: Icon(icon, color: AppColors.textSecondary, size: 22),
    title: Text(
      title,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (count != null)
          Text(
            count.toString(),
            style: const TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
        const SizedBox(width: 8),
        const Icon(
          Icons.arrow_forward_ios,
          color: AppColors.textMuted,
          size: 14,
        ),
      ],
    ),
  );
}
