import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'show_detail_screen.dart';

class UserListScreen extends StatefulWidget {
  final String tableName;
  final String title;
  final String? userId; // OPSİYONEL: Boşsa giriş yapan kullanıcıyı baz alır

  const UserListScreen({
    super.key,
    required this.tableName,
    required this.title,
    this.userId
  });

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
    // Eğer widget'tan userId gelmediyse, mevcut oturum açmış kullanıcıyı al
    final targetId = widget.userId ?? _supabase.auth.currentUser?.id;
    if (targetId == null) return;

    try {
      final data = await _supabase
          .from(widget.tableName)
          .select()
          .eq('user_id', targetId) // Hedef kullanıcının verilerini filtrele
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          shows = data;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("List fetch error: $e");
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
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () => Navigator.pop(context)
        ),
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
          crossAxisCount: 3,
          childAspectRatio: 0.67,
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
              ).then((_) => _fetchList());
            },
            child: Hero(
              tag: 'list_poster_${show['show_id']}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: "https://image.tmdb.org/t/p/w342${show['poster_path']}",
                  fit: BoxFit.cover,
                  placeholder: (c, u) => Container(color: Colors.white10),
                  errorWidget: (c, u, e) => Container(color: Colors.white10, child: const Icon(Icons.error)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}