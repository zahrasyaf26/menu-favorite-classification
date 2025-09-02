import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  List<Map<String, dynamic>> _predictedFavorites = [];
  Map<String, int> _frequency = {};
  late Map<String, dynamic> _decisionTreeModel;

  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      String data = await DefaultAssetBundle.of(context).loadString('assets/decision_tree_structure.json');
      Map<String, dynamic> model = json.decode(data);
      if (model.isEmpty) throw Exception("Model decision tree kosong.");
      setState(() {
        _decisionTreeModel = model;
      });
    } catch (e) {
      debugPrint("Error saat memuat model: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: \${e.toString()}")));
    }
  }

  int encodeRecurring(String recurring) => recurring.toLowerCase().contains("sudah") ? 1 : 0;

  int encodePrice(String price) {
    switch (price.toLowerCase()) {
      case "terlalu mahal": return 3;
      case "sudah sesuai": return 2;
      case "sedikit mahal": return 1;
      default: return 0;
    }
  }

  int encodeTaste(String taste) {
    switch (taste.toLowerCase()) {
      case "sangat sedap": return 3;
      case "cukup sedap": return 2;
      case "kurang sedap": return 1;
      default: return 0;
    }
  }

  Future<void> _predictFromFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      String csvString = await file.readAsString(encoding: utf8);
      List<List<dynamic>> rows = const CsvToListConverter().convert(csvString, eol: '\n');
      if (rows.length < 2) throw Exception("File CSV kosong atau tidak valid.");
      final header = rows.first.map((e) => e.toString()).toList();

      if (!header.contains("Apakah Anda sudah pernah menjadi pelanggan di Kafe Ngadem sebelumnya?") ||
          !header.contains("Item apakah yang anda pesan dari menu yang tersedia?") ||
          !header.contains("Apakah menurut Anda harga item menu tersebut sudah sesuai?") ||
          !header.contains("Apakah menurut Anda rasa item menu tersebut sudah cukup sedap dan memuaskan?") ||
          !header.contains("Apakah menurut anda pesanan anda dapat menjadi menu favorit di Kafe Ngadem?")) {
        throw Exception("Header CSV tidak valid atau tidak lengkap.");
      }

      // Ambil tanggal mulai dan akhir dari input pengguna
      final DateTime? startDate = _parseDate(_startDateController.text);
      final DateTime? endDate = _parseDate(_endDateController.text);

// Filter berdasarkan tanggal jika input valid
      final data = rows.sublist(1).where((row) {
        try {
          final timestampString = row[0].toString();
          final rowDate = _parseDate(timestampString);
          if (rowDate == null) return false;
          if (startDate != null && rowDate.isBefore(startDate)) return false;
          if (endDate != null && rowDate.isAfter(endDate)) return false;
          return true;
        } catch (_) {
          return false;
        }
      }).expand((row) {
        List<Map<String, dynamic>> items = [];
        final recurring = row[1]?.toString() ?? "";
        for (var i = 2; i <= 10; i += 4) {
          if (i < row.length) {
            final order = row[i]?.toString() ?? "";
            final price = (i + 1) < row.length ? row[i + 1]?.toString() ?? "" : "";
            final taste = (i + 2) < row.length ? row[i + 2]?.toString() ?? "" : "";
            final favorite = (i + 3) < row.length ? row[i + 3]?.toString() ?? "" : "";
            if (order.isNotEmpty) {
              items.add({
                "Recurring": recurring,
                "Order": order,
                "Price": price,
                "Taste": taste,
                "Favorite": favorite,
              });
            }
          }
        }
        return items;
      }).toList();

      List<Map<String, dynamic>> predictions = _predict(data);
      predictions = _getTop5(predictions);

      setState(() {
        _predictedFavorites = predictions;
        _frequency = _generateFrequency(predictions);
      });

      await _saveToHistory(predictions);
    } catch (e) {
      debugPrint("Error saat membaca file: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: \${e.toString()}")));
    }
  }

  List<Map<String, dynamic>> _predict(List<Map<String, dynamic>> data) {
    List<Map<String, dynamic>> result = [];
    for (var row in data) {
      int recurring = encodeRecurring(row["Recurring"] ?? "");
      int price = encodePrice(row["Price"] ?? "");
      int taste = encodeTaste(row["Taste"] ?? "");
      Map<String, dynamic>? node = _decisionTreeModel;

      while (node != null && node['name'] != "Leaf") {
        double value = 0.0;
        switch (node['name']) {
          case "Recurring": value = recurring.toDouble(); break;
          case "Price": value = price.toDouble(); break;
          case "Taste": value = taste.toDouble(); break;
        }
        node = value <= node['threshold'] ? node['left'] : node['right'];
      }

      if (node != null && node['value'][0][1] > node['value'][0][0]) {
        double confidence = node['value'][0][1] / (node['value'][0][0] + node['value'][0][1]);
        result.add({"Order": row["Order"], "Predicted": "Ya", "Confidence": (confidence * 100).toStringAsFixed(1)});
      }
    }

    return result;
  }

  List<Map<String, dynamic>> _getTop5(List<Map<String, dynamic>> predictions) {
    Map<String, int> countMap = {};
    for (var p in predictions) {
      countMap[p['Order']] = (countMap[p['Order']] ?? 0) + 1;
    }
    final sorted = countMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).map((e) => {"Order": e.key, "Count": e.value}).toList();
  }

  Map<String, int> _generateFrequency(List<Map<String, dynamic>> list) {
    final freq = <String, int>{};
    for (var item in list) {
      final order = item["Order"];
      freq[order] = item["Count"];
    }
    return freq;
  }

  Future<void> _saveToHistory(List<Map<String, dynamic>> predictions) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList("prediction_history") ?? [];
    Map<String, dynamic> entry = {
      "timestamp": DateTime.now().toIso8601String(),
      "predictions": predictions,
    };
    history.add(json.encode(entry));
    await prefs.setStringList("prediction_history", history);
  }

  Future<void> _exportToCSV() async {
    if (_predictedFavorites.isEmpty) return;
    List<List<dynamic>> csvData = [
      ["Menu", "Prediksi", "Confidence (%)"]
    ];
    for (var item in _predictedFavorites) {
      csvData.add([item["Order"], item["Predicted"] ?? "Ya", item["Confidence"] ?? "-"]);
    }
    String csv = const ListToCsvConverter().convert(csvData);
    final directory = await getExternalStorageDirectory();
    final path = directory?.path ?? ".";
    final file = File("$path/prediksi_output.csv");
    await file.writeAsString(csv);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hasil prediksi berhasil diekspor ke prediksi_output.csv")));
  }

  Widget _buildHorizontalBarChart() {
    if (_frequency.isEmpty) return const SizedBox.shrink();
    final items = _frequency.entries.toList();
    final barGroups = items.asMap().entries.map((entry) {
      final index = entry.key;
      final value = entry.value.value.toDouble();
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: value,
            width: 30,
            borderRadius: BorderRadius.circular(8),
            gradient: const LinearGradient(
              colors: [Colors.deepPurple, Colors.purpleAccent],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
        ],
      );
    }).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        height: 280,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        width: items.length * 120,
        child: BarChart(
          BarChartData(
            barGroups: barGroups,
            alignment: BarChartAlignment.spaceAround,
            groupsSpace: 64,
            maxY: _frequency.values.reduce((a, b) => a > b ? a : b).toDouble() + 1,
            gridData: FlGridData(
              show: true,
              drawHorizontalLine: true,
              getDrawingHorizontalLine: (value) => FlLine(
                color: Colors.grey.shade300,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 90,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < items.length) {
                      return RotatedBox(
                        quarterTurns: 1,
                        child: Text(
                          items[index].key,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      );
                    }
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Upload & Prediksi"), backgroundColor: Colors.orange),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              const Text("Unggah Data Pelanggan", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
              const SizedBox(height: 8),
              const Text("Upload file CSV pelanggan untuk memprediksi menu favorit mereka."),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Filter berdasarkan rentang tanggal (mm/dd/yyyy):"),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _startDateController,
                            decoration: InputDecoration(labelText: 'Tanggal Mulai'),
                            keyboardType: TextInputType.text,
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _endDateController,
                            decoration: InputDecoration(labelText: 'Tanggal Akhir'),
                            keyboardType: TextInputType.text,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _predictFromFile,
                icon: const Icon(Icons.upload_file),
                label: const Text("Upload CSV"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              ),
              const SizedBox(height: 16),
              if (_predictedFavorites.isNotEmpty) ...[
                ElevatedButton.icon(
                  onPressed: _exportToCSV,
                  icon: const Icon(Icons.save_alt),
                  label: const Text("Export Hasil"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                ),
                const SizedBox(height: 16),
                const Text("Top 5 Menu Favorit yang Diprediksi:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Column(
                  children: _predictedFavorites.map((item) {
                    return ListTile(
                      leading: const Icon(Icons.fastfood, color: Colors.teal),
                      title: Text(item["Order"]),
                      subtitle: Text("Predicted as Favorite${item["Confidence"] != null ? " – Confidence: ${item["Confidence"]}%" : ""}"),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                _buildHorizontalBarChart(),
              ] else
                const SizedBox(height: 100, child: Center(child: Text("Belum ada hasil prediksi."))),
            ],
          ),
        ),
      ),
    );
  }
  DateTime? _parseDate(String input) {
    try {
      final parts = input.split('/');
      if (parts.length != 3) return null;
      final month = int.parse(parts[0]);
      final day = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }
}
