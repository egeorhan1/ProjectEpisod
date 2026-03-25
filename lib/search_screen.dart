import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../api_config.dart';
import 'show_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  List searchResults = [];
  bool isSearching = false;
  bool isMoreLoading = false;
  int currentPage = 1;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Selected Filter Values
  String selectedGenreId = "";
  String selectedCountryCode = "";
  String selectedSortBy = "popularity.desc";

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
        if (!isMoreLoading && !isSearching && searchResults.isNotEmpty) {
          loadMoreShows();
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // --- TMDB DATA (English) ---
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

  String _getGenreName(String id) => genres.firstWhere((g) => g['id'] == id, orElse: () => {'name': ''})['name']!;
  String _getCountryName(String code) => countries.firstWhere((c) => c['code'] == code, orElse: () => {'name': ''})['name']!;
  String _getSortName(String value) => sortOptions.firstWhere((s) => s['value'] == value)['name']!;

  // --- API FUNCTIONS ---
  Future<void> applyFilters() async {
    setState(() {
      isSearching = true;
      currentPage = 1;
      searchResults = [];
      _controller.clear();
    });
    await fetchShows();
  }

  Future<void> loadMoreShows() async {
    setState(() => isMoreLoading = true);
    currentPage++;
    await fetchShows(isLoadMore: true);
  }

  Future<void> fetchShows({bool isLoadMore = false}) async {
    // Language changed to en-US
    String urlString = '${ApiConfig.baseUrl}/discover/tv?api_key=${ApiConfig.apiKey}&language=en-US&sort_by=$selectedSortBy&page=$currentPage';

    if (selectedGenreId.isNotEmpty) urlString += '&with_genres=$selectedGenreId';
    if (selectedCountryCode.isNotEmpty) urlString += '&with_origin_country=$selectedCountryCode';
    if (selectedSortBy.contains('vote_average')) urlString += '&vote_count.gte=100';

    try {
      final response = await http.get(Uri.parse(urlString));
      if (response.statusCode == 200) {
        final List newResults = json.decode(response.body)['results'];
        setState(() {
          if (isLoadMore) {
            searchResults.addAll(newResults);
          } else {
            searchResults = newResults;
          }
          isSearching = false;
          isMoreLoading = false;
        });
      }
    } catch (e) {
      setState(() { isSearching = false; isMoreLoading = false; });
    }
  }

  Future<void> searchShows(String query) async {
    if (query.isEmpty) return;
    setState(() {
      isSearching = true;
      searchResults = [];
      currentPage = 1;
      selectedGenreId = "";
      selectedCountryCode = "";
      selectedSortBy = "popularity.desc";
    });
    // Language changed to en-US
    final url = Uri.parse('${ApiConfig.baseUrl}/search/tv?api_key=${ApiConfig.apiKey}&query=$query&language=en-US&page=$currentPage');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          searchResults = json.decode(response.body)['results'];
          isSearching = false;
        });
      }
    } catch (e) {
      setState(() => isSearching = false);
    }
  }

  // --- UI HELPERS ---
  void _openFilterMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2C3440),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Filter and Sort", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                _buildDropdown("SORT BY", selectedSortBy, sortOptions.map((s) => DropdownMenuItem(value: s['value'], child: Text(s['name']!))).toList(), (val) => setModalState(() => selectedSortBy = val!)),
                _buildDropdown("COUNTRY", selectedCountryCode, countries.map((c) => DropdownMenuItem(value: c['code'], child: Text(c['name']!))).toList(), (val) => setModalState(() => selectedCountryCode = val!)),
                _buildDropdown("GENRE", selectedGenreId, genres.map((g) => DropdownMenuItem(value: g['id'], child: Text(g['name']!))).toList(), (val) => setModalState(() => selectedGenreId = val!)),
                const SizedBox(height: 30),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E054), minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () { Navigator.pop(context); applyFilters(); },
                  child: const Text("SHOW RESULTS", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<DropdownMenuItem<String>> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: const Color(0xFF14181C), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(value: value, dropdownColor: const Color(0xFF14181C), isExpanded: true, items: items, onChanged: onChanged, style: const TextStyle(color: Colors.white)),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool hasActiveFilter = (selectedGenreId.isNotEmpty || selectedCountryCode.isNotEmpty || selectedSortBy != "popularity.desc");

    return Scaffold(
      backgroundColor: const Color(0xFF14181C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14181C),
        elevation: 0,
        title: TextField(
          controller: _controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: "Search shows...", hintStyle: TextStyle(color: Colors.grey), border: InputBorder.none),
          onSubmitted: searchShows,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.tune, color: hasActiveFilter ? const Color(0xFF00E054) : Colors.white),
            onPressed: _openFilterMenu,
          )
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- ACTIVE FILTER CHIPS ---
          if (hasActiveFilter && !isSearching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text("Filters: ", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    if (selectedSortBy != "popularity.desc") _buildFilterChip(_getSortName(selectedSortBy), isSort: true),
                    if (selectedGenreId.isNotEmpty) _buildFilterChip(_getGenreName(selectedGenreId)),
                    if (selectedCountryCode.isNotEmpty) _buildFilterChip(_getCountryName(selectedCountryCode)),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedGenreId = "";
                          selectedCountryCode = "";
                          selectedSortBy = "popularity.desc";
                          searchResults = [];
                        });
                      },
                      child: const Icon(Icons.cancel, size: 20, color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
            ),

          // --- RESULTS ---
          Expanded(
            child: isSearching
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E054)))
                : searchResults.isEmpty
                ? const Center(child: Text("Search or filter to discover", style: TextStyle(color: Colors.grey)))
                : GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, childAspectRatio: 0.67, crossAxisSpacing: 10, mainAxisSpacing: 10,
              ),
              itemCount: searchResults.length,
              itemBuilder: (context, index) => _buildPosterTile(searchResults[index]),
            ),
          ),
          if (isMoreLoading)
            const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(color: Color(0xFF00E054)))),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, {bool isSort = false}) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: const Color(0xFF2C3440),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSort ? Colors.orange : const Color(0xFF00E054), width: 1)
      ),
      child: Text(label, style: TextStyle(color: isSort ? Colors.orange : const Color(0xFF00E054), fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildPosterTile(Map show) {
    final rating = show['vote_average']?.toStringAsFixed(1) ?? '0.0';
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ShowDetailScreen(show: show))),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: show['poster_path'] != null
                ? CachedNetworkImage(imageUrl: "${ApiConfig.imageBaseUrl}${show['poster_path']}", fit: BoxFit.cover, placeholder: (context, url) => Container(color: Colors.grey[900]))
                : Container(color: Colors.grey[900], child: const Icon(Icons.tv, color: Colors.white24)),
          ),
          if (rating != '0.0')
            Positioned(
              top: 6, right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(4)),
                child: Row(children: [
                  const Icon(Icons.star, size: 10, color: Color(0xFF00E054)),
                  const SizedBox(width: 2),
                  Text(rating, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}