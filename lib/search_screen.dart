import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../api_config.dart';
import 'show_detail_screen.dart';
import 'other_profile_screen.dart';
import 'theme/app_colors.dart';
import 'widgets/episod_user_avatar.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  // -- SHOWS DEĞİŞKENLERİ --
  List searchResults = [];
  bool isSearching = false;
  bool isMoreLoading = false;
  int currentPage = 1;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String selectedGenreId = "";
  String selectedCountryCode = "";
  String selectedSortBy = "popularity.desc";

  // -- PEOPLE DEĞİŞKENLERİ --
  late TabController _tabController;
  Timer? _debounce;
  List userResults = [];
  bool isSearchingUsers = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _tabController.addListener(() {
      setState(() {});
    });

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 300) {
        if (!isMoreLoading &&
            !isSearching &&
            searchResults.isNotEmpty &&
            _tabController.index == 0) {
          _loadMoreShows();
        }
      }
    });

    // İlk açılışta popüler dizileri yükle
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

  // --- TMDB DATA ---
  final List<Map<String, String>> sortOptions = [
    {"name": "Popularity (Descending)", "value": "popularity.desc"},
    {"name": "Rating (Highest)", "value": "vote_average.desc"},
    {"name": "Release Date (Newest)", "value": "first_air_date.desc"},
  ];

  final List<Map<String, String>> genres = [
    {"name": "All Genres", "id": ""},
    {"name": "Action & Adventure", "id": "10759"},
    {"name": "Drama", "id": "18"},
    {"name": "Comedy", "id": "35"},
    {"name": "Crime", "id": "80"},
    {"name": "Mystery", "id": "9648"},
    {"name": "Sci-Fi & Fantasy", "id": "10765"},
  ];

  final List<Map<String, String>> countries = [
    {"name": "Worldwide", "code": ""},
    {"name": "Turkey 🇹🇷", "code": "TR"},
    {"name": "USA 🇺🇸", "code": "US"},
    {"name": "South Korea 🇰🇷", "code": "KR"},
    {"name": "UK 🇬🇧", "code": "GB"},
    {"name": "Japan 🇯🇵", "code": "JP"},
  ];

  String _getGenreName(String id) => genres.firstWhere(
    (g) => g['id'] == id,
    orElse: () => {'name': ''},
  )['name']!;
  String _getCountryName(String code) => countries.firstWhere(
    (c) => c['code'] == code,
    orElse: () => {'name': ''},
  )['name']!;
  String _getSortName(String value) =>
      sortOptions.firstWhere((s) => s['value'] == value)['name']!;

  // --- MERKEZİ ARAMA VE FİLTRELEME YÖNETİCİSİ ---
  Future<void> _applyFilters() async {
    setState(() {
      isSearching = true;
      currentPage = 1;
      searchResults = [];
    });

    final q = _controller.text.trim();
    if (q.isEmpty) {
      await _fetchShows(); // Kelime yoksa TMDB Discover API
    } else {
      await _searchShows(q); // Kelime varsa Search API + Local Filtre
    }
  }

  // Çarpı (X) tuşuna basıldığında filtreleri sıfırlar
  Future<void> _clearFilters() async {
    setState(() {
      selectedGenreId = "";
      selectedCountryCode = "";
      selectedSortBy = "popularity.desc";
    });
    await _applyFilters();
  }

  Future<void> _loadMoreShows() async {
    setState(() => isMoreLoading = true);
    currentPage++;
    final q = _controller.text.trim();
    if (q.isEmpty) {
      await _fetchShows(isLoadMore: true);
    } else {
      await _searchShows(q, isLoadMore: true);
    }
  }

  // 1. DÜZ KEŞİF (Kelime araması yokken çalışır - TMDB filtreleri destekler)
  Future<void> _fetchShows({bool isLoadMore = false}) async {
    String urlString =
        '${ApiConfig.baseUrl}/discover/tv?api_key=${ApiConfig.apiKey}&language=en-US&sort_by=$selectedSortBy&page=$currentPage';

    if (selectedGenreId.isNotEmpty)
      urlString += '&with_genres=$selectedGenreId';
    if (selectedCountryCode.isNotEmpty)
      urlString += '&with_origin_country=$selectedCountryCode';
    if (selectedSortBy.contains('vote_average'))
      urlString += '&vote_count.gte=100';

    try {
      final response = await http.get(Uri.parse(urlString));
      if (response.statusCode == 200) {
        final List newResults = json.decode(response.body)['results'];
        if (mounted) {
          setState(() {
            if (isLoadMore)
              searchResults.addAll(newResults);
            else
              searchResults = newResults;
            isSearching = false;
            isMoreLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted)
        setState(() {
          isSearching = false;
          isMoreLoading = false;
        });
    }
  }

  // 2. KELİME ARAMASI (TMDB arama uç noktasını kullanır, filtreleri LOKAL uygular)
  Future<void> _searchShows(String query, {bool isLoadMore = false}) async {
    final url = Uri.parse(
      '${ApiConfig.baseUrl}/search/tv?api_key=${ApiConfig.apiKey}&query=$query&language=en-US&page=$currentPage',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        List rawResults = json.decode(response.body)['results'];

        // YENİ: TMDB Search API filtre desteklemediği için lokal filtreleme yapıyoruz!
        List filteredResults = rawResults.where((show) {
          bool matchesGenre = true;
          if (selectedGenreId.isNotEmpty) {
            matchesGenre =
                show['genre_ids'] != null &&
                (show['genre_ids'] as List).contains(
                  int.parse(selectedGenreId),
                );
          }
          bool matchesCountry = true;
          if (selectedCountryCode.isNotEmpty) {
            matchesCountry =
                show['origin_country'] != null &&
                (show['origin_country'] as List).contains(selectedCountryCode);
          }
          return matchesGenre && matchesCountry;
        }).toList();

        // Lokal Sıralama
        if (selectedSortBy == 'popularity.desc') {
          filteredResults.sort(
            (a, b) => (b['popularity'] as num? ?? 0).compareTo(
              a['popularity'] as num? ?? 0,
            ),
          );
        } else if (selectedSortBy == 'vote_average.desc') {
          filteredResults.sort(
            (a, b) => (b['vote_average'] as num? ?? 0).compareTo(
              a['vote_average'] as num? ?? 0,
            ),
          );
        } else if (selectedSortBy == 'first_air_date.desc') {
          filteredResults.sort(
            (a, b) => (b['first_air_date'] ?? '').compareTo(
              a['first_air_date'] ?? '',
            ),
          );
        }

        if (mounted) {
          setState(() {
            if (isLoadMore)
              searchResults.addAll(filteredResults);
            else
              searchResults = filteredResults;
            isSearching = false;
            isMoreLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => isSearching = false);
    }
  }

  // --- API FUNCTIONS (USERS) ---
  Future<void> searchUsers(String query) async {
    setState(() => isSearchingUsers = true);
    try {
      final res = await _supabase
          .from('profiles')
          .select()
          .ilike('username', '%$query%')
          .limit(20);
      if (mounted) setState(() => userResults = res);
    } catch (e) {
      debugPrint("User search error: $e");
    } finally {
      if (mounted) setState(() => isSearchingUsers = false);
    }
  }

  // --- REAL-TIME SEARCH (DEBOUNCE) ---
  void _onSearchChanged(String val) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final q = val.trim();
      setState(() {
        isSearching = true;
        currentPage = 1;
        searchResults = [];
        if (q.isEmpty) userResults.clear();
      });

      if (q.isEmpty) {
        _fetchShows();
      } else {
        _searchShows(q);
        searchUsers(q);
      }
    });
  }

  // --- UI HELPERS ---
  void _openFilterMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.elevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Filter and Sort",
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                _buildDropdown(
                  "SORT BY",
                  selectedSortBy,
                  sortOptions
                      .map(
                        (s) => DropdownMenuItem(
                          value: s['value'],
                          child: Text(s['name']!),
                        ),
                      )
                      .toList(),
                  (val) => setModalState(() => selectedSortBy = val!),
                ),
                _buildDropdown(
                  "COUNTRY",
                  selectedCountryCode,
                  countries
                      .map(
                        (c) => DropdownMenuItem(
                          value: c['code'],
                          child: Text(c['name']!),
                        ),
                      )
                      .toList(),
                  (val) => setModalState(() => selectedCountryCode = val!),
                ),
                _buildDropdown(
                  "GENRE",
                  selectedGenreId,
                  genres
                      .map(
                        (g) => DropdownMenuItem(
                          value: g['id'],
                          child: Text(g['name']!),
                        ),
                      )
                      .toList(),
                  (val) => setModalState(() => selectedGenreId = val!),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _applyFilters(); // YENİ: Filtreler uygulandığında güncel listeyi çağır
                  },
                  child: const Text(
                    "SHOW RESULTS",
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    List<DropdownMenuItem<String>> items,
    Function(String?) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: AppColors.background,
              isExpanded: true,
              items: items,
              onChanged: onChanged,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool hasActiveFilter =
        (selectedGenreId.isNotEmpty ||
        selectedCountryCode.isNotEmpty ||
        selectedSortBy != "popularity.desc");

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: TextField(
          controller: _controller,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: "Search shows or people...",
            hintStyle: TextStyle(color: AppColors.textSecondary),
            border: InputBorder.none,
          ),
          onChanged: _onSearchChanged,
        ),
        actions: [
          if (_tabController.index == 0)
            IconButton(
              icon: Icon(
                Icons.tune,
                color: hasActiveFilter
                    ? AppColors.accent
                    : AppColors.textPrimary,
              ),
              onPressed: _openFilterMenu,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: "Shows"),
            Tab(text: "People"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildShowsTab(hasActiveFilter), _buildUsersTab()],
      ),
    );
  }

  // --- SHOWS SEKME İÇERİĞİ ---
  Widget _buildShowsTab(bool hasActiveFilter) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // YENİ: Arama yapılıyorken de filtre çipleri görünsün diye text.isEmpty şartı kaldırıldı
        if (hasActiveFilter)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text(
                    "Filters: ",
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (selectedSortBy != "popularity.desc")
                    _buildFilterChip(
                      _getSortName(selectedSortBy),
                      isSort: true,
                    ),
                  if (selectedGenreId.isNotEmpty)
                    _buildFilterChip(_getGenreName(selectedGenreId)),
                  if (selectedCountryCode.isNotEmpty)
                    _buildFilterChip(_getCountryName(selectedCountryCode)),
                  GestureDetector(
                    onTap:
                        _clearFilters, // YENİ: Çarpıya basınca gerçekten sıfırla
                    child: const Icon(
                      Icons.cancel,
                      size: 20,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
          ),

        Expanded(
          child: isSearching
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                )
              : searchResults.isEmpty
              ? const Center(
                  child: Text(
                    "No shows found.",
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.67,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: searchResults.length,
                  itemBuilder: (context, index) =>
                      _buildPosterTile(searchResults[index]),
                ),
        ),
        if (isMoreLoading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          ),
      ],
    );
  }

  // --- PEOPLE SEKME İÇERİĞİ ---
  Widget _buildUsersTab() {
    if (_controller.text.trim().isEmpty) {
      return const Center(
        child: Text(
          "Type a username to find people",
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    if (isSearchingUsers)
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    if (userResults.isEmpty)
      return const Center(
        child: Text(
          "No users found.",
          style: TextStyle(color: AppColors.textMuted),
        ),
      );

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: userResults.length,
      separatorBuilder: (context, index) =>
          const Divider(color: AppColors.divider, height: 1),
      itemBuilder: (context, index) {
        final user = userResults[index];
        final String uName = user['username'] ?? "User";

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          leading: EpisodUserAvatar(username: uName, radius: 22, fontSize: 18),
          title: Text(
            uName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          trailing: const Icon(
            Icons.arrow_forward_ios,
            color: AppColors.textMuted,
            size: 14,
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (c) => OtherUserProfileScreen(userId: user['id']),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip(String label, {bool isSort = false}) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.elevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSort ? AppColors.accentSecondary : AppColors.accent,
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSort ? AppColors.accentSecondary : AppColors.accent,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildPosterTile(Map show) {
    final rating = show['vote_average']?.toStringAsFixed(1) ?? '0.0';
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ShowDetailScreen(show: show)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: show['poster_path'] != null
                ? CachedNetworkImage(
                    imageUrl: "${ApiConfig.imageBaseUrl}${show['poster_path']}",
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: AppColors.elevated),
                  )
                : Container(
                    color: AppColors.elevated,
                    child: const Icon(Icons.tv, color: AppColors.textMuted),
                  ),
          ),
          if (rating != '0.0')
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.overlayDark,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star, size: 10, color: AppColors.accent),
                    const SizedBox(width: 2),
                    Text(
                      rating,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
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
}
