import 'package:flutter/material.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14181C),
      appBar: AppBar(
        title: const Text("Recent Activity", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF14181C),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildActivityItem("John", "Breaking Bad", "Season 5 Episode 14", 5, "watched"),
          const Divider(color: Colors.white10),
          _buildActivityItem("Emma", "The Bear", "Season 2 Episode 6", 4, "watched"),
          const Divider(color: Colors.white10),
          _buildActivityItem("Mike", "Succession", "Season 1 Episode 1", 0, "watched"), // No rating
          const Divider(color: Colors.white10),
          _buildActivityItem("Sarah", "Severance", "Added to Watchlist", -1, "added"), // Watchlist action
        ],
      ),
    );
  }

  Widget _buildActivityItem(String user, String show, String info, int rating, String actionType) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Picture (Avatar)
          CircleAvatar(
            backgroundColor: Colors.grey[800],
            child: Text(user[0], style: const TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 15),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                    children: [
                      TextSpan(text: "$user ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      TextSpan(text: actionType == "watched" ? "watched " : "added "),
                      TextSpan(text: show, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      if (actionType == "added") const TextSpan(text: " to their watchlist"),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(info, style: const TextStyle(color: Colors.white24, fontSize: 13)),

                // Stars (Only if they rated it)
                if (rating > 0) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: List.generate(5, (index) => Icon(
                      Icons.star,
                      size: 14,
                      color: index < rating ? const Color(0xFF00E054) : Colors.grey[800],
                    )),
                  ),
                ],
              ],
            ),
          ),

          // Small Show Poster Placeholder
          Container(
            width: 40,
            height: 60,
            decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white10)
            ),
            child: const Icon(Icons.tv, size: 20, color: Colors.white24),
          )
        ],
      ),
    );
  }
}