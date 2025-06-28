import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

// Model class for drug information
class DrugInfo {
  final String brandName;
  final String genericName;
  final String manufacturer;
  final String dosageForm;
  final String route;
  final List<String> activeIngredients;
  final List<String> indications;
  final List<String> warnings;
  final List<String> adverseReactions;
  final String description;

  DrugInfo({
    required this.brandName,
    required this.genericName,
    required this.manufacturer,
    required this.dosageForm,
    required this.route,
    required this.activeIngredients,
    required this.indications,
    required this.warnings,
    required this.adverseReactions,
    required this.description,
  });

  factory DrugInfo.fromJson(Map<String, dynamic> json) {
    final results = json['results'][0];
    final openfda = results['openfda'] ?? {};
    
    return DrugInfo(
      brandName: _extractFirstString(openfda['brand_name']),
      genericName: _extractFirstString(openfda['generic_name']),
      manufacturer: _extractFirstString(openfda['manufacturer_name']),
      dosageForm: _extractFirstString(openfda['dosage_form']),
      route: _extractFirstString(openfda['route']),
      activeIngredients: _extractStringList(results['active_ingredient']),
      indications: _extractStringList(results['indications_and_usage']),
      warnings: _extractStringList(results['warnings']),
      adverseReactions: _extractStringList(results['adverse_reactions']),
      description: _extractFirstString(results['description']),
    );
  }

  static String _extractFirstString(dynamic value) {
    if (value == null) return 'Not available';
    if (value is List && value.isNotEmpty) return value[0];
    return 'Not available';
  }

  static List<String> _extractStringList(dynamic value) {
    if (value == null) return ['Not available'];
    if (value is List) return List<String>.from(value);
    return ['Not available'];
  }
}

// FDA API Service
class FdaService {
  static const String baseUrl = 'https://api.fda.gov/drug/label.json';

  Future<List<DrugInfo>> searchDrugByGenericName(String query, {int limit = 10}) async {
    if (query.isEmpty) return [];
    
    final url = '$baseUrl?search=openfda.generic_name:"$query"&limit=$limit';
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['results'] == null || data['results'].isEmpty) {
        return [];
      }
      
      List<DrugInfo> drugs = [];
      for (var result in data['results']) {
        try {
          drugs.add(DrugInfo.fromJson({'results': [result]}));
        } catch (e) {
          print('Error parsing drug info: $e');
        }
      }
      return drugs;
    } else {
      // Try searching by brand name if generic name search fails
      return searchDrugByBrandName(query, limit: limit);
    }
  }

  Future<List<DrugInfo>> searchDrugByBrandName(String query, {int limit = 10}) async {
    if (query.isEmpty) return [];
    
    final url = '$baseUrl?search=openfda.brand_name:"$query"&limit=$limit';
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['results'] == null || data['results'].isEmpty) {
        return [];
      }
      
      List<DrugInfo> drugs = [];
      for (var result in data['results']) {
        try {
          drugs.add(DrugInfo.fromJson({'results': [result]}));
        } catch (e) {
          print('Error parsing drug info: $e');
        }
      }
      return drugs;
    } else {
      throw Exception('Failed to load drug information');
    }
  }
}

// Providers
final fdaServiceProvider = Provider<FdaService>((ref) => FdaService());

final drugSearchQueryProvider = StateProvider<String>((ref) => '');

final drugSearchResultsProvider = FutureProvider.family<List<DrugInfo>, String>(
  (ref, query) async {
    if (query.isEmpty) return [];
    final fdaService = ref.read(fdaServiceProvider);
    return fdaService.searchDrugByGenericName(query);
  },
);