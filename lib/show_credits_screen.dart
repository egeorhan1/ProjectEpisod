import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../api_config.dart';

class ShowCreditsScreen extends StatefulWidget {
  final int showId;
  final String showName;

  const ShowCreditsScreen({super.key, required this.showId, required this.showName});

  @override
  State<ShowCreditsScreen> createState() => _ShowCreditsScreenState();
}

class _ShowCreditsScreenState extends State<ShowCreditsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List cast = [];
  Map<String, List> crewByJob = {};
  List<String> sortedJobTitles = []; // Sıralanmış başlıkları burada tutacağız
  bool isLoading = true;

  // --- ÖNEM SIRALAMASI ---
  // Bu listedeki roller en üstte, listenin sırasına göre gözükür.
  final List<String> jobPriority = [
    'Director',
    'Series Director',
    'Creator',
    'Writer',
    'Executive Producer',
    'Producer',
    'Original Music Composer',
    'Director of Photography',
    'Editor',
    'Art Direction',
    'Costume Design',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    fetchCredits();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> fetchCredits() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/tv/${widget.showId}/aggregate_credits?api_key=${ApiConfig.apiKey}&language=en-US');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        setState(() {
          cast = data['cast'];

          List fullCrew = data['crew'];
          crewByJob = {};

          for (var member in fullCrew) {
            if (member['jobs'] != null && member['jobs'].isNotEmpty) {
              String job = member['jobs'][0]['job'] ?? 'Other';
              if (!crewByJob.containsKey(job)) {
                crewByJob[job] = [];
              }
              crewByJob[job]!.add(member);
            }
          }

          // --- SIRALAMA MANTIĞI ---
          sortedJobTitles = crewByJob.keys.toList();
          sortedJobTitles.sort((a, b) {
            int indexA = jobPriority.indexOf(a);
            int indexB = jobPriority.indexOf(b);

            // Eğer rol listede yoksa en sona at (99 değeriyle)
            if (indexA == -1) indexA = 99;
            if (indexB == -1) indexB = 99;

            return indexA.compareTo(indexB);
          });

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
        backgroundColor: const Color(0xFF14181C),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.showName, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.normal)),
            const Text("Cast & Crew", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00E054),
          labelColor: const Color(0xFF00E054),
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: "CAST"),
            Tab(text: "CREW"),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E054)))
          : TabBarView(
        controller: _tabController,
        children: [
          _buildCastList(),
          _buildCrewList(),
        ],
      ),
    );
  }

  Widget _buildCastList() {
    if (cast.isEmpty) return const Center(child: Text("No cast data", style: TextStyle(color: Colors.grey)));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: cast.length,
      itemBuilder: (context, index) {
        final person = cast[index];
        return _buildPersonTile(
          name: person['name'],
          sub: person['roles'] != null ? person['roles'][0]['character'] : "Unknown",
          path: person['profile_path'],
          extra: "${person['total_episode_count']} eps",
        );
      },
    );
  }

  Widget _buildCrewList() {
    if (sortedJobTitles.isEmpty) return const Center(child: Text("No crew data", style: TextStyle(color: Colors.grey)));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: sortedJobTitles.length,
      itemBuilder: (context, index) {
        final jobTitle = sortedJobTitles[index];
        final members = crewByJob[jobTitle]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: Text(jobTitle.toUpperCase(),
                  style: const TextStyle(color: Color(0xFF00E054), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.5)),
            ),
            ...members.map((m) => _buildPersonTile(
              name: m['name'],
              sub: m['jobs'][0]['job'],
              path: m['profile_path'],
            )).toList(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Divider(color: Colors.white10),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPersonTile({required String name, required String sub, String? path, String? extra}) {
    return ListTile(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: Colors.grey[900],
        backgroundImage: path != null ? CachedNetworkImageProvider("https://image.tmdb.org/t/p/w185$path") : null,
        child: path == null ? const Icon(Icons.person, color: Colors.white24, size: 20) : null,
      ),
      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      trailing: extra != null ? Text(extra, style: const TextStyle(color: Colors.white24, fontSize: 11)) : null,
    );
  }
}