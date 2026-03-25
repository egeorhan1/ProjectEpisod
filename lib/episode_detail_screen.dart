import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EpisodeDetailScreen extends StatefulWidget {
  final Map episode;
  final String showName;
  final int showId;
  final int seasonNumber;

  const EpisodeDetailScreen({
    super.key,
    required this.episode,
    required this.showName,
    required this.showId,
    required this.seasonNumber
  });

  @override
  State<EpisodeDetailScreen> createState() => _EpisodeDetailScreenState();
}

class _EpisodeDetailScreenState extends State<EpisodeDetailScreen> {
  final _supabase = Supabase.instance.client;
  final _commentController = TextEditingController();
  double userRating = 0;
  double averageEpoint = 0;
  List comments = [];
  bool isInitialLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  // --- TÜM VERİLERİ YÜKLE ---
  Future<void> _loadAllData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => isInitialLoading = false);
      return;
    }

    try {
      final results = await Future.wait<dynamic>([
        _supabase.from('episode_ratings').select().eq('user_id', user.id).eq('show_id', widget.showId).eq('season_number', widget.seasonNumber).eq('episode_number', widget.episode['episode_number']).maybeSingle(),
        _supabase.from('episode_ratings').select('rating').eq('show_id', widget.showId).eq('season_number', widget.seasonNumber).eq('episode_number', widget.episode['episode_number']),
        _supabase.from('comments').select('*, profiles(username)').eq('show_id', widget.showId).eq('season_number', widget.seasonNumber).eq('episode_number', widget.episode['episode_number']).order('created_at', ascending: false),
      ]);

      final userRes = results[0];
      final allRes = results[1] as List;
      final commentRes = results[2] as List;

      double avg = 0;
      if (allRes.isNotEmpty) {
        final total = allRes.fold<double>(0, (sum, item) => sum + (item['rating'] as num).toDouble());
        avg = total / allRes.length;
      }

      if (mounted) {
        setState(() {
          userRating = userRes != null ? (userRes['rating'] as num).toDouble() : 0;
          averageEpoint = avg;
          comments = commentRes;
          isInitialLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Load Data Error: $e");
      if (mounted) setState(() => isInitialLoading = false);
    }
  }

  // --- PUAN KAYDETME ---
  Future<void> _saveRating(double val) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You must be logged in to rate!"), backgroundColor: Colors.red));
      return;
    }

    try {
      await _supabase.from('episode_ratings').upsert({
        'user_id': user.id,
        'show_id': widget.showId,
        'season_number': widget.seasonNumber,
        'episode_number': widget.episode['episode_number'],
        'rating': val,
      });

      await _loadAllData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Rating saved: ${val.toInt()}/10"), backgroundColor: const Color(0xFF00E054), duration: const Duration(milliseconds: 700))
        );
      }
    } catch (e) {
      debugPrint("Save Rating Error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to save rating: $e"), backgroundColor: Colors.red));
    }
  }

  // --- YORUM KAYDETME ---
  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final user = _supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You must be logged in to comment!"), backgroundColor: Colors.red));
      return;
    }

    _commentController.clear();

    try {
      await _supabase.from('comments').insert({
        'user_id': user.id,
        'show_id': widget.showId,
        'season_number': widget.seasonNumber,
        'episode_number': widget.episode['episode_number'],
        'content': text
      });

      await _loadAllData();

    } catch (e) {
      debugPrint("Post Comment Error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Comment error: $e"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14181C),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("S${widget.seasonNumber}E${widget.episode['episode_number']}",
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.8), Colors.transparent],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Container(color: const Color(0xFF14181C)),

          RefreshIndicator(
            onRefresh: _loadAllData,
            color: const Color(0xFF00E054),
            backgroundColor: const Color(0xFF14181C),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24.0, 10.0, 24.0, 100.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildScores(),
                        const SizedBox(height: 32),
                        _buildRatingPicker(),
                        const SizedBox(height: 32),
                        _buildOverview(),
                        const SizedBox(height: 40),
                        const Text("COMMENTS", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2)),
                        const SizedBox(height: 16),
                        _buildCommentInput(),
                        // ARAYI KAPATTIK! SizedBox'ı kaldırdık. Listeyi direkt bağlıyoruz.
                        _buildCommentList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGETLAR ---
  Widget _buildHeader() {
    return Stack(
      children: [
        widget.episode['still_path'] != null
            ? CachedNetworkImage(imageUrl: "https://image.tmdb.org/t/p/w780${widget.episode['still_path']}", width: double.infinity, height: 280, fit: BoxFit.cover)
            : Container(height: 280, width: double.infinity, color: Colors.white10, child: const Icon(Icons.movie, color: Colors.white24, size: 50)),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            height: 100,
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, const Color(0xFF14181C)])),
          ),
        ),
      ],
    );
  }

  Widget _buildScores() => Row(children: [
    _scoreItem("TMDB", "${widget.episode['vote_average']?.toStringAsFixed(1)}", Colors.amber, false),
    const SizedBox(width: 24),
    _scoreItem("EPOINT", averageEpoint > 0 ? averageEpoint.toStringAsFixed(1) : "N/A", const Color(0xFF00E054), true)
  ]);

  Widget _scoreItem(String l, String v, Color c, bool isE) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Row(children: [isE ? Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)), child: const Text("E", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11))) : Icon(Icons.star, color: c, size: 16), const SizedBox(width: 8), Text(v, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))])]);

  Widget _buildRatingPicker() => Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
      child: Slider(value: userRating, min: 0, max: 10, divisions: 10, activeColor: const Color(0xFF00E054), label: userRating.toInt().toString(), onChanged: (v) => setState(() => userRating = v), onChangeEnd: (v) => _saveRating(v))
  );

  Widget _buildOverview() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("OVERVIEW", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2)), const SizedBox(height: 12), Text(widget.episode['overview'] != "" ? widget.episode['overview'] : "No summary available.", style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.6))]);

  // YENİ UI: HAP ŞEKLİNDE MODERN YORUM YAZMA KUTUSU
  Widget _buildCommentInput() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF1E2329), // Arka plandan hafif açık
      borderRadius: BorderRadius.circular(30), // Tam yuvarlak köşeler (hap)
      border: Border.all(color: Colors.white10),
    ),
    padding: const EdgeInsets.only(left: 20, right: 6, top: 6, bottom: 6),
    child: Row(
        children: [
          Expanded(
              child: TextField(
                  controller: _commentController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                      hintText: "Add a comment...",
                      hintStyle: TextStyle(color: Colors.white30, fontSize: 14),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero
                  )
              )
          ),
          Container(
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00E054)),
            child: IconButton(
                iconSize: 18,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
                onPressed: _postComment,
                icon: const Icon(Icons.send, color: Colors.black)
            ),
          )
        ]
    ),
  );

  // YENİ UI: DÜZENLİ, ARALARI ÇİZGİLİ VE SIFIR BOŞLUKLU LİSTE
  Widget _buildCommentList() {
    if (comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 24.0),
        child: Text("No comments yet. Be the first to start the conversation!", style: TextStyle(color: Colors.white30, fontSize: 13, fontStyle: FontStyle.italic)),
      );
    }

    return ListView.separated( // Liste elemanları arasına çizgi çeker
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 24), // Sadece List'in üstüne boşluk verdik, o iğrenç default gap'i sildik.
        itemCount: comments.length,
        separatorBuilder: (context, i) => const Divider(color: Colors.white10, height: 32), // Yorum araları estetik çizgi
        itemBuilder: (context, i) {
          final c = comments[i];
          final u = c['profiles'] != null ? c['profiles']['username'] : "User";
          return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                    radius: 18, // Profil resmi biraz büyüdü
                    backgroundColor: const Color(0xFF2C3440),
                    child: Text(u[0].toUpperCase(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF00E054)))
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(u, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 6),
                          Text(c['content'], style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4))
                        ]
                    )
                )
              ]
          );
        }
    );
  }
}