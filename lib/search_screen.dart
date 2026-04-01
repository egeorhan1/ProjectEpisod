import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_config.dart';
import 'show_detail_screen.dart';
import 'other_profile_screen.dart';
import 'person_detail_screen.dart';
import 'theme/app_colors.dart';
import 'widgets/episod_user_avatar.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  // Veriler
  List searchResults = []; // Diziler
  List actorResults = [];  // Oyuncular
  List userResults = [];   // Kullanıcılar

  bool isSearching = false;
  bool isMoreLoading = false;
  int currentPage = 1;

  // Filtreler
  String selectedGenreId = "";
  String selectedCountryCode = "";
  String selectedSortBy = "popularity.desc";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // --- KAYDIRMA (SCROLL) DÜZELTMESİ ---
    _scrollController.addListener(() {
      // Sayfanın bitmesine 400 piksel kala yeni sayfayı yüklemeye başla (Pürüzsüzlük için)
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
        if (!isMoreLoading && !isSearching && searchResults.isNotEmpty && _tabController.index == 0) {
          _loadMoreShows();
        }
      }
    });

    _applyFilters();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
    _tabController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // --- API VE ARAMA MOTORU ---

  Future<void> _applyFilters() async {
    setState(() { isSearching = true; currentPage = 1; searchResults = []; });
    final q = _controller.text.trim();
    if (q.isEmpty) {
      await _fetchDiscoverShows();
    } else {
      await _searchAll(q);
    }
  }

  // Poster'ı veya bilgisi olmayan dizileri filtrele
  List _filterShows(List shows) => shows.where((s) =>
    s['poster_path'] != null &&
    s['poster_path'] != '' &&
    s['overview'] != null &&
    (s['overview'] as String).isNotEmpty
  ).toList();

  Future<void> _searchAll(String query) async {
    setState(() => isSearching = true);
    try {
      final tvUrl = Uri.parse('${ApiConfig.baseUrl}/search/tv?api_key=${ApiConfig.apiKey}&query=$query&page=$currentPage');
      final personUrl = Uri.parse('${ApiConfig.baseUrl}/search/person?api_key=${ApiConfig.apiKey}&query=$query');
      final keywordUrl = Uri.parse('${ApiConfig.baseUrl}/search/keyword?api_key=${ApiConfig.apiKey}&query=$query');
      final userQuery = _supabase.from('profiles').select().ilike('username', '%$query%').limit(15);

      final responses = await Future.wait<dynamic>([
        http.get(tvUrl),
        http.get(personUrl),
        http.get(keywordUrl),
        userQuery,
      ]);

      final List tvResults = _filterShows(json.decode((responses[0] as http.Response).body)['results']);
      final List keywords = json.decode((responses[2] as http.Response).body)['results'];

      // Keyword ID'lerini al ve keyword'e göre dizi ara
      List keywordShows = [];
      if (keywords.isNotEmpty) {
        final keywordIds = keywords.take(5).map((k) => k['id'].toString()).join('|');
        final discoverUrl = Uri.parse('${ApiConfig.baseUrl}/discover/tv?api_key=${ApiConfig.apiKey}&with_keywords=$keywordIds&sort_by=popularity.desc');
        final discoverRes = await http.get(discoverUrl);
        if (discoverRes.statusCode == 200) {
          keywordShows = _filterShows(json.decode(discoverRes.body)['results']);
        }
      }

      // Doğrudan arama sonuçlarını keyword sonuçlarıyla birleştir (tekrarsız)
      final existingIds = tvResults.map((s) => s['id']).toSet();
      final uniqueKeywordShows = keywordShows.where((s) => !existingIds.contains(s['id'])).toList();
      final merged = [...tvResults, ...uniqueKeywordShows];

      if (mounted) {
        setState(() {
          searchResults = merged;
          actorResults = json.decode((responses[1] as http.Response).body)['results'];
          userResults = responses[3] as List;
          isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isSearching = false);
    }
  }

  Future<void> _fetchDiscoverShows() async {
    String url = '${ApiConfig.baseUrl}/discover/tv?api_key=${ApiConfig.apiKey}&sort_by=$selectedSortBy&page=$currentPage';
    if (selectedGenreId.isNotEmpty) url += '&with_genres=$selectedGenreId';
    if (selectedCountryCode.isNotEmpty) url += '&with_origin_country=$selectedCountryCode';

    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final List results = _filterShows(json.decode(res.body)['results']);
        if (mounted) {
          setState(() {
            if (currentPage == 1) {
              searchResults = results;
            } else {
              searchResults.addAll(results);
            }
            isSearching = false;
          });
        }
      }
    } catch (e) { if (mounted) setState(() => isSearching = false); }
  }

  // --- SAYFA ATLAMA (PAGINATION) MANTIĞI ---
  Future<void> _loadMoreShows() async {
    if (isMoreLoading) return;
    setState(() => isMoreLoading = true); // Yükleniyor durumunu aç
    currentPage++; // Sayfayı artır

    final q = _controller.text.trim();
    if (q.isEmpty) {
      await _fetchDiscoverShows(); // Popülerlerde kaydırıyorsa
    } else {
      await _fetchMoreTvShows(q);  // Bir şey aratıp kaydırıyorsa
    }

    if (mounted) {
      setState(() => isMoreLoading = false); // Yükleniyor durumunu kapat
    }
  }

  // Sadece TV Şovlarının sonraki sayfalarını çeker (Arama yaparken aşağı kaydırma için)
  Future<void> _fetchMoreTvShows(String query) async {
    try {
      final tvUrl = Uri.parse('${ApiConfig.baseUrl}/search/tv?api_key=${ApiConfig.apiKey}&query=$query&page=$currentPage');
      final res = await http.get(tvUrl);
      if (res.statusCode == 200) {
        final List results = _filterShows(json.decode(res.body)['results']);
        if (mounted) {
          setState(() {
            searchResults.addAll(results); // Altına ekle
          });
        }
      }
    } catch (e) {
      debugPrint("Pagination search error: $e");
    }
  }

  void _onSearchChanged(String val) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _applyFilters());
  }

  // --- UI KISMI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: TextField(
          controller: _controller,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: "Search shows, actors or users...",
            hintStyle: TextStyle(color: AppColors.textSecondary),
            border: InputBorder.none,
          ),
          onChanged: _onSearchChanged,
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [Tab(text: "Shows"), Tab(text: "Actors"), Tab(text: "Users")],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildShowsTab(),
          _buildActorsTab(),
          _buildUsersTab(),
        ],
      ),
    );
  }

  Widget _buildShowsTab() {
    if (isSearching && currentPage == 1) return const Center(child: CircularProgressIndicator(color: AppColors.accent));

    return Stack(
      children: [
        GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 80), // Alttan boşluk bıraktık ki yükleniyor ikonu filmleri kapatmasın
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.67, crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: searchResults.length,
          itemBuilder: (context, i) => _buildPosterTile(searchResults[i]),
        ),

        // --- ZARİF YÜKLENİYOR ANİMASYONU ---
        if (isMoreLoading)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceAlt,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10)],
                ),
                child: const SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 3),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActorsTab() {
    if (isSearching) return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    if (actorResults.isEmpty) return const Center(child: Text("No actors found.", style: TextStyle(color: AppColors.textMuted)));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: actorResults.length,
      itemBuilder: (context, i) {
        final actor = actorResults[i];
        return ListTile(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => PersonDetailScreen(personId: actor['id'], personName: actor['name']))),
          leading: CircleAvatar(
            backgroundColor: AppColors.elevated,
            backgroundImage: actor['profile_path'] != null ? NetworkImage("https://image.tmdb.org/t/p/w185${actor['profile_path']}") : null,
            child: actor['profile_path'] == null ? const Icon(Icons.person, color: AppColors.textMuted) : null,
          ),
          title: Text(actor['name'] ?? '', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          subtitle: Text(actor['known_for_department'] ?? 'Acting', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        );
      },
    );
  }

  Widget _buildUsersTab() {
    if (isSearching) return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    if (userResults.isEmpty) return const Center(child: Text("No users found.", style: TextStyle(color: AppColors.textMuted)));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: userResults.length,
      itemBuilder: (context, i) {
        final user = userResults[i];
        return ListTile(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => OtherUserProfileScreen(userId: user['id']))),
          leading: EpisodUserAvatar(username: user['username'] ?? "User", radius: 20, fontSize: 16),
          title: Text(user['username'] ?? 'User', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textMuted),
        );
      },
    );
  }

  Widget _buildPosterTile(Map show) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => ShowDetailScreen(show: show))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: "https://image.tmdb.org/t/p/w342${show['poster_path']}",
          fit: BoxFit.cover,
          errorWidget: (c, u, e) => Container(color: AppColors.elevated, child: const Icon(Icons.tv, color: AppColors.textMuted)),
        ),
      ),
    );
  }
}