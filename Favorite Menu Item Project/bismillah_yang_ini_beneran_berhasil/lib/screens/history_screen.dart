import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> historyData = prefs.getStringList("prediction_history") ?? [];

    try {
      List<Map<String, dynamic>> parsedHistory = historyData.map((entry) {
        Map<String, dynamic> decoded = json.decode(entry);
        return decoded;
        throw const FormatException("Format data histori tidak valid.");
      }).toList();

      setState(() {
        _history = parsedHistory;
      });
    } catch (e) {
      debugPrint("Error saat memuat histori: $e");
    }
  }

  Future<void> _deleteHistoryItem(int index) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> historyData = prefs.getStringList("prediction_history") ?? [];

    if (index >= 0 && index < historyData.length) {
      historyData.removeAt(index);
      await prefs.setStringList("prediction_history", historyData);
    }

    setState(() {
      _history.removeAt(index);
    });
  }

  String _formatDate(String timestamp) {
    final dateTime = DateTime.tryParse(timestamp);
    if (dateTime != null) {
      return DateFormat('dd MMMM yyyy – HH:mm').format(dateTime);
    }
    return "Tanggal tidak diketahui";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Histori Prediksi"), backgroundColor: Colors.orange),
      body: _history.isEmpty
          ? const Center(child: Text("Belum ada histori prediksi."))
          : ListView.builder(
        itemCount: _history.length,
        itemBuilder: (context, index) {
          var item = _history[index];
          var predictions = item['predictions'] as List<dynamic>;
          String timestamp = item['timestamp'] ?? "";

          return Card(
            margin: const EdgeInsets.all(8),
            child: ExpansionTile(
              title: Text("Prediksi: ${_formatDate(timestamp)}"),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteHistoryItem(index),
              ),
              children: predictions
                  .map((pred) => ListTile(
                leading: const Icon(Icons.star, color: Colors.orange),
                title: Text(pred["Order"]),
              ))
                  .toList(),
            ),
          );
        },
      ),
    );
  }
}
