import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class FileStats {
  final String filename;
  final int changes;
  final int branches;
  final List<String> branchNames;
  
  FileStats({required this.filename, required this.changes, required this.branches, this.branchNames = const []});
  
  factory FileStats.fromJson(Map<String, dynamic> json) {
    return FileStats(
      filename: json['filename'] as String,
      changes: json['changes'] as int,
      branches: json['branches'] as int,
      branchNames: (json['branchNames'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
    );
  }
}

class BranchStatistics {
  final int totalBranchesAnalyzed;
  final List<FileStats> topFiles;
  final String lastUpdated;
  
  BranchStatistics({
    required this.totalBranchesAnalyzed,
    required this.topFiles,
    required this.lastUpdated,
  });
  
  factory BranchStatistics.fromJson(Map<String, dynamic> json) {
    final topFilesData = json['topFiles'] as List<dynamic>? ?? [];
    return BranchStatistics(
      totalBranchesAnalyzed: json['totalBranchesAnalyzed'] as int? ?? 0,
      topFiles: topFilesData.map((e) => FileStats.fromJson(e as Map<String, dynamic>)).toList(),
      lastUpdated: json['lastUpdated']?.toString() ?? '',
    );
  }
}

class Statistics extends StatefulComponent {
  const Statistics({super.key});

  @override
  State<Statistics> createState() => _StatisticsState();
}

class _StatisticsState extends State<Statistics> {
  BranchStatistics? statistics;
  bool isLoading = true;
  String error = '';

  @override
  void initState() {
    super.initState();
    _fetchStatistics();
  }

  Future<void> _fetchStatistics() async {
    try {
      // Due to the rewrite rules in firebase.json, /api/statistics routes to getBranchStatistics function
      final response = await http.get(Uri.parse('/api/statistics'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            statistics = BranchStatistics.fromJson(data);
            isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            error = 'Failed to load statistics (${response.statusCode})';
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Error connecting to API';
          isLoading = false;
        });
      }
    }
  }

  @override
  Component build(BuildContext context) {
    if (isLoading) {
      return div(classes: 'glass-card', [
        h3(classes: 'title', [.text('Branch Statistics')]),
        p(classes: 'loading-text', [.text('Loading statistics...')]),
      ]);
    }
    
    if (error.isNotEmpty) {
      return div(classes: 'glass-card result-error', [
        h3(classes: 'title', [.text('Branch Statistics')]),
        p(classes: 'result-desc', [.text(error)]),
      ]);
    }
    
    if (statistics == null) {
      return .empty();
    }
    
    return div(classes: 'glass-card', [
      h3(classes: 'title', [.text('Repository Statistics')]),
      p(classes: 'subtitle', [.text('Based on ${statistics!.totalBranchesAnalyzed} triaged branches')]),
      
      div(classes: 'stats-container', [
        h4(classes: 'stats-header', [.text('Files Changed in Most Branches')]),
        table(classes: 'stats-table', [
          thead([
            tr([
              th([.text('File')]),
              th([.text('Changes')]),
              th([.text('Branches')]),
            ])
          ]),
          tbody([
            for (final file in (statistics!.topFiles
                .where((f) => !f.filename.contains('/test/') && !f.filename.startsWith('test/') && !f.filename.endsWith('_test.dart'))
                .toList()
              ..sort((a, b) => b.branches.compareTo(a.branches))).take(10))
              tr([
                td([.text(file.filename)]),
                td([.text(file.changes.toString())]),
                td([
                  details(
                    classes: 'branch-details',
                    [
                      summary([.text(file.branches.toString())]),
                      div(classes: 'branch-links', [
                        for (final branch in file.branchNames)
                          a(
                            href: '?issue=${branch.replaceAll('triage-issue-', '')}',
                            classes: 'branch-link',
                            [.text('#${branch.replaceAll('triage-issue-', '')}')]
                          )
                      ])
                    ]
                  )
                ]),
              ])
          ])
        ])
      ])
    ]);
  }
}
