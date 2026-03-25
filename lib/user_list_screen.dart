import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'show_detail_screen.dart';

class UserListScreen extends StatefulWidget {
  final String tableName;
  final String title;

  const UserListScreen({super.key, required this.tableName, required this.title});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final _supabase = Supabase.instance.client;
  List shows = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchList();
  }

  Future<void> _fetchList() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await _supabase
          .from(widget.tableName)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          shows = data;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14181C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E054)))
          : shows.isEmpty
          ? const Center(child: Text("No shows found", style: TextStyle(color: Colors.white24)))
          : GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, // Yan yana 3 poster
          childAspectRatio: 0.67, // Poster oranı
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: shows.length,
        itemBuilder: (context, index) {
          final show = shows[index];
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShowDetailScreen(show: {
                    'id': show['show_id'],
                    'name': show['show_name'],
                    'poster_path': show['poster_path'],
                  }),
                ),
              ).then((_) => _fetchList()); // Geri dönünce listeyi tazele
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: "https://image.tmdb.org/t/p/w342${show['poster_path']}",
                fit: BoxFit.cover,
                placeholder: (c, u) => Container(color: Colors.white10),
                errorWidget: (c, u, e) => Container(color: Colors.white10, child: const Icon(Icons.error)),
              ),
            ),
          );
        },
      ),
    );
  }
}