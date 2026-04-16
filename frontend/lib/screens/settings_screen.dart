// Vaarta by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi
// settings_screen.dart - Settings & Personal Vocabulary Management

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic> _vocabulary = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVocabulary();
  }

  Future<void> _loadVocabulary() async {
    final state = context.read<VaartaState>();
    try {
      final response = await http.get(
        Uri.parse('http://${state.serverUrl}/vocabulary'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _vocabulary = Map<String, dynamic>.from(data['vocabulary'] ?? {});
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[Vaarta] Failed to load vocabulary: $e');
      setState(() {
        _isLoading = false;
        _error = 'Could not connect to server';
      });
    }
  }

  Future<void> _deleteWord(String word) async {
    final state = context.read<VaartaState>();
    try {
      final response = await http.delete(
        Uri.parse(
            'http://${state.serverUrl}/vocabulary/${Uri.encodeComponent(word)}'),
      );
      if (response.statusCode == 200) {
        setState(() => _vocabulary.remove(word));
      }
    } catch (e) {
      debugPrint('[Vaarta] Failed to delete word: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VaartaState>(
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF8F7F4),
          appBar: AppBar(
            title: const Text(
              'Settings',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
            centerTitle: false,
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Domain selector
              _buildSectionHeader('Active Domain', Icons.category_outlined),
              const SizedBox(height: 10),
              _buildDomainSelector(state),
              const SizedBox(height: 32),

              // Personal vocabulary
              _buildSectionHeader(
                  'Personal Vocabulary', Icons.auto_fix_high_outlined),
              const SizedBox(height: 4),
              Text(
                'Saved corrections are applied automatically to future translations.',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 12),
              _buildVocabularyList(),
              const SizedBox(height: 32),

              // Supported Languages
              _buildSectionHeader('Supported Languages', Icons.translate),
              const SizedBox(height: 10),
              _buildLanguageGrid(),
              const SizedBox(height: 32),

              // About
              _buildAbout(),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  Widget _buildDomainSelector(VaartaState state) {
    return Row(
      children: [
        _buildDomainOption(state, 'general', 'General', Icons.public),
        const SizedBox(width: 8),
        _buildDomainOption(
            state, 'medical', 'Medical', Icons.local_hospital_outlined),
        const SizedBox(width: 8),
        _buildDomainOption(
            state, 'transport', 'Transport', Icons.directions_bus_outlined),
      ],
    );
  }

  Widget _buildDomainOption(
      VaartaState state, String value, String label, IconData icon) {
    final isActive = state.activeDomain == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => state.setDomain(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF1A1A1A) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? const Color(0xFF1A1A1A) : Colors.grey[300]!,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isActive ? Colors.white : Colors.grey[500],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.grey[700],
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVocabularyList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
            child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFF1A1A1A),
        )),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Center(
          child: Text(
            _error!,
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ),
      );
    }

    if (_vocabulary.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.spellcheck, size: 28, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(
                'No saved corrections yet.\nCorrections will appear here as you use Vaarta.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: _vocabulary.entries.map((entry) {
          return ListTile(
            title: Row(
              children: [
                Text(
                  entry.key,
                  style: TextStyle(
                    color: Colors.red[400],
                    decoration: TextDecoration.lineThrough,
                    fontSize: 14,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child:
                      Icon(Icons.arrow_forward, size: 14, color: Colors.grey[400]),
                ),
                Text(
                  entry.value.toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF4CAF50),
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon:
                  Icon(Icons.delete_outline, size: 18, color: Colors.grey[400]),
              onPressed: () => _deleteWord(entry.key),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLanguageGrid() {
    const languages = [
      'Hindi', 'Bengali', 'Marathi', 'Telugu', 'Tamil',
      'Gujarati', 'Urdu', 'Kannada', 'Odia', 'Malayalam', 'English',
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: languages.map((lang) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Text(
            lang,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAbout() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'V',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'VAARTA',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                  Text(
                    'v1.0.0',
                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Real-Time Multilingual Voice Translation',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          Text(
            'by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'CHRIST (Deemed to be University), Delhi NCR',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
